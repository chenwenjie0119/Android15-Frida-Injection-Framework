# GOTCHAS — Pitfalls & Correct Solutions

A complete record of every problem hit while deploying Frida 17.23.3 on a MuMu Android 15 emulator (x86_64, rooted, no Magisk), and the exact solution that worked.

All target-app names are genericized to `com.example.target`.

---

## 1. Frida 17.x removed the built-in Java bridge

**Symptom**: Python API script throws `ReferenceError: Java is not defined` / `TypeError: Java.perform is not a function`.

**Root cause**: Frida 17.x moved the Java bridge out of the core. The CLI (`frida_tools.repl`) still injects a global `Java`; the Python API (`frida.get_device_manager()...create_script`) does not.

**Fix**: In Python-API scripts, load the bridge explicitly:

```js
if (typeof Java === 'undefined') {
    try { Java = require('frida-java-bridge'); } catch (e) { send('JavaBridgeErr ' + e); }
}
```

Or simply use the CLI for anything that needs `Java`.

## 2. `Module.findExportByName` was renamed

**Symptom**: `TypeError: Module.findExportByName is not a function` under Frida 17.x.

**Fix**: use `Module.findGlobalExportByName` (and `Module.getGlobalExportByName`) instead.

## 3. `frida-inject` is unusable on Android 15

**Symptom**: `frida-inject-17.23.3-android-arm64` fails on the Android 15 emulator; APK-style injection into a running app does not work via the standalone inject binary.

**Fix**: use the **remote channel**: deploy `fsyd` (renamed frida-server) inside the emulator, `adb forward tcp:47243 tcp:47243`, then attach/spawn through `-H 127.0.0.1:47243` with the Frida CLI or Python API.

## 4. MuMu ADB port is not stable across cold boots

**Symptom**: `adb connect 127.0.0.1:16416` works before a reboot, but after cold boot the port is different (`16384`, `16432`, `7555`, `5555`, …).

**Fix**: probe candidate ports before every run:

```powershell
foreach ($p in @('16416','16384','16432','7555','5555')) {
    & $adb connect "127.0.0.1:$p" | Out-Null
    $st = (& $adb -s "127.0.0.1:$p" get-state 2>$null)
    if ($st -eq 'device') { $ser = "127.0.0.1:$p"; break }
}
```

Also note MuMuManager instance index confusion: `--vmindex 1` in `MuMuManager control` is not the same as the ADB device list index (which showed `emulator-5556` / instance 3).

## 5. Attaching too early crashes the target

**Symptom**: injection right after the target process appears destabilizes startup; the app dies or misbehaves seconds later.

**Fix**: wait for the process to settle before attaching. In this environment, sleep **12s+** after the PID first appears (and re-check the PID, because a very early restart may have happened). Then attach.

## 6. Load-time Java self-check + native read hooks → instant SIGSEGV

**Symptom**: full script with a `Java.perform(runSelfCheck)` at load time (reading `/proc/self/maps` + `/proc/cpuinfo` via Java `FileInputStream`, 131KB+ of data) plus native `read` hooks crashes the target process instantly — SIGSEGV in a startup worker thread (`wc_srvinit`-like thread, `0xb` / `SEGV_MAPERR`).

**Root cause**: at injection time, all target threads are paused. The load-time self-check does heavy Java I/O on `/proc` while native `read` hooks are intercepting those same reads; the interference trips a null/low-address access in an early worker thread.

**Fix**: remove the load-time self-check entirely; expose it via `rpc.exports.selfcheck = runSelfCheck` so you can trigger it manually. Generated `*_noself*.js` variants are the stable ones for injection.

## 7. Residual runtime crash after removing load-time self-check

**Symptom**: with `noself` variant, the process still dies minutes later in a background Java thread (`HeapTaskDaemon`) with `SIGSEGV code 128 fault addr 0x0` — only when the full hook set is active. Native-only and Java-only subsets are both stable.

**Root cause**: the crash is a runtime interaction between modules (not load time). Not all modules can coexist safely on every app.

**Fix (methodology)**: **bisect injection**. Inject `bisect_native.js` (native-only) → stable; inject `bisect_java.js` (Java-only) → stable; inject the full set → crash. Then progressively re-add modules to find the pair that breaks. In this project the stable production variant removes the problematic runtime path (see `frida_full_noself2.js` lineage) and survived >3 min continuously.

## 8. ADB input / sendevent don't work on MuMu

**Symptom**: PC-side `adb shell input tap` / `sendevent` do not drive the emulator UI.

**Fix**: use `am start -n <pkg>/.ui.LauncherUI` to bring up the target Activity, or interact with the emulator window via PC mouse. For GPS, use MuMu's Nemu GPS virtual location (or `MuMuManager control --vmindex N tool location`) instead of `adb emu geo fix` (which fails because the console port is not the ADB port).

## 9. `adb emu geo fix` fails on MuMu

**Symptom**: `adb emu geo fix` errors out.

**Fix**: `MuMuManager control --vmindex 1 tool location` sets GPS. Verify through the app (system-level injection), not PC-side logs.

## 10. Target not logged in → sensor not registered

**Symptom**: sensor-related hooks appear dead.

**Fix**: log in to the target app first; sensors (and many services) only register after login. Verify after entering the mini-program / main UI.

## 11. Python-API spawn needs resume and keep-alive

**Symptom**: `dev.spawn([pkg])` then `attach` works, but if you forget `dev.resume(pid)` the app never starts; if the script is not eternalized, it dies when the client exits.

**Fix**: always `script.load()` → `dev.resume(pid)`; use `--eternalize` on the CLI or keep the Python client alive (see `host/deploy_keep.py` — it loops a process-list liveness check).

## 12. Running frida-server as root on MuMu

**Symptom**: `nohup /system/bin/fsyd` dies immediately or permission errors.

**Fix**:

```bash
adb shell su -c "nohup /system/bin/fsyd -l 0.0.0.0:47243 > /data/local/tmp/fsyd.log 2>&1 &"
```

Verify with `pidof fsyd`. Clean `/data/local/tmp/frida-server*` / `re.frida.server*` markers for stealth hygiene. Note: MuMu has root but **no Magisk/Zygisk**, so system-less solutions are not available.

## 13. Termux pip install frida fails to build

**Symptom**: `pip install frida` inside Termux fails compiling/installing (no prebuilt wheel for the target).

**Fix**: download the official devkit instead — `frida-devkit-android-x86_64-17.23.3.tar.xz` (see `termux/termux_dl_devkit.sh` with GitHub mirror fallback chain: gh-proxy → ghfast → ghproxy.net → mirror.ghproxy.com → github.moeyy.xyz). Also switch apt to the TUNA mirror (`termux_setup.sh`) before `apt install python`.

## 14. Background restrictions kill the boot deployer

**Symptom**: the APK's boot receiver starts work, then Android kills the background task.

**Fix**: use `goAsync()` + `PendingResult.finish()` inside the receiver and do the work in a separate thread. This holds the broadcast until the copy/start is done.

---

## Verified stable sequence (the "right way")

1. Get `frida-server-17.23.3-android-x86_64`, rename to `fsyd`.
2. `adb push fsyd /data/local/tmp/fsyd`, then `su -c "cp ... /system/bin/fsyd && chmod 755 ..."`.
3. Clean `/data/local/tmp` markers; start `nohup /system/bin/fsyd -l 0.0.0.0:47243 &`.
4. `adb forward tcp:47243 tcp:47243`.
5. `frida-ps -H 127.0.0.1:47243` to confirm.
6. Start target; wait for PID; **sleep 12s**; attach:

```
python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l <script>.js --runtime=v8 --eternalize -q
```

7. For automation: run `host/deploy_master.ps1` on a 2-min Windows Task Scheduler loop; use the `attach_done.flag` to re-inject only when the PID changes.
