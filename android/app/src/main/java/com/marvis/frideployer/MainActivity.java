package com.marvis.frideployer;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.DataOutputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;

public class MainActivity extends Activity {
    private TextView logView;
    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        logView = new TextView(this);
        logView.setPadding(24, 24, 24, 24);
        logView.setTextSize(14);
        setContentView(logView);
        appendLog("Frida Deployer starting...");
        new Thread(this::deploy).start();
    }

    private void appendLog(final String line) {
        android.util.Log.i("FridaDeployer", line);
        handler.post(() -> logView.append("\n" + line));
    }

    private void deploy() {
        // 1. root check (optional; PC closed-loop handles fsyd+injection)
        boolean rooted = isRooted();
        appendLog(rooted ? "root OK" : "no root (PC closed-loop will handle fsyd/inject)");
        if (!rooted) {
            // still start target app so PC poller can find and inject it
            appendLog("start target: " + exec("am start -n " + targetActivity()).trim());
            appendLog("=== deploy (apps only) done ===");
            return;
        }
        // 2. copy deploy script to app private dir then su-cp to /data/local/tmp
        String jsPath = "/data/local/tmp/deploy_script.js";
        try {
            InputStream in = getAssets().open("demo_hook.js");
            byte[] buf = new byte[65536];
            int n;
            OutputStream out = openFileOutput("demo_hook.js", MODE_PRIVATE);
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            out.close();
            in.close();
            String priv = new java.io.File(getFilesDir(), "demo_hook.js").getAbsolutePath();
            String cp = execRoot("cp -f '" + priv + "' " + jsPath + " && chmod 644 " + jsPath + " && ls -l " + jsPath);
            appendLog("js copied -> " + jsPath + " (" + cp.trim() + ")");
        } catch (Exception e) {
            appendLog("js copy failed: " + e.getMessage());
            return;
        }
        // 3. ensure fsyd (frida-server) running
        String fsyd = execRoot("pidof fsyd || /system/bin/fsyd > /data/local/tmp/fsyd.log 2>&1 & echo started");
        appendLog("fsyd: " + fsyd.trim());
        // 4. start target app
        appendLog("start target: " + execRoot("am start -n " + targetActivity()).trim());
        appendLog("=== deploy done ===");
        appendLog("注: 目标应用的 frida 注入由 PC 端轮询任务每2分钟自动完成");
        appendLog("真机(可写/system)由本 APK 内嵌注入器自动注入");
    }

    // EDIT ME: target activity of the app you want to deploy/inject
    private String targetActivity() {
        return "com.example.target/.ui.LauncherUI";
    }

    private boolean isRooted() {
        try {
            Process p = Runtime.getRuntime().exec("su");
            DataOutputStream os = new DataOutputStream(p.getOutputStream());
            os.writeBytes("id\n");
            os.flush();
            String out = new BufferedReader(new InputStreamReader(p.getInputStream())).readLine();
            return out != null && out.contains("uid=0");
        } catch (Exception e) {
            return false;
        }
    }

    private String exec(String cmd) {
        try {
            Process p = Runtime.getRuntime().exec(cmd);
            p.waitFor();
            StringBuilder sb = new StringBuilder();
            String line;
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            while ((line = br.readLine()) != null) sb.append(line).append(" | ");
            return sb.toString();
        } catch (Exception e) {
            return "EX: " + e.getMessage();
        }
    }

    private String execRoot(String cmd) {
        try {
            Process p = Runtime.getRuntime().exec("su");
            DataOutputStream os = new DataOutputStream(p.getOutputStream());
            os.writeBytes(cmd + "\n");
            os.writeBytes("exit\n");
            os.flush();
            StringBuilder sb = new StringBuilder();
            String line;
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            while ((line = br.readLine()) != null) sb.append(line).append(" | ");
            p.waitFor();
            return sb.toString();
        } catch (Exception e) {
            return "EX: " + e.getMessage();
        }
    }
}
