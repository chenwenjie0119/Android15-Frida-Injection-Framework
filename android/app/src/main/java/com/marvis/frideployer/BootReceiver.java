package com.marvis.frideployer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "FridaDeployer";

    @Override
    public void onReceive(final Context context, Intent intent) {
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !"android.intent.action.QUICKBOOT_POWERON".equals(action)) {
            return;
        }
        Log.i(TAG, "BOOT_COMPLETED received: " + action);
        final PendingResult pr = goAsync();
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    Log.i(TAG, "start target: " + exec("am start -n com.example.target/.ui.LauncherUI").trim());
                    Log.i(TAG, "=== boot deploy (apps only) done ===");
                } catch (Exception e) {
                    Log.i(TAG, "boot deploy err: " + e.getMessage());
                } finally {
                    pr.finish();
                }
            }
        }).start();
    }

    private String exec(String cmd) {
        try {
            Process p = Runtime.getRuntime().exec(cmd);
            p.waitFor();
            StringBuilder sb = new StringBuilder();
            String line;
            java.io.BufferedReader br = new java.io.BufferedReader(
                    new java.io.InputStreamReader(p.getInputStream()));
            while ((line = br.readLine()) != null) sb.append(line).append(" | ");
            return sb.toString();
        } catch (Exception e) {
            return "EX: " + e.getMessage();
        }
    }
}
