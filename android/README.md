# android/ — boot-time deployer APK (optional)

A tiny APK (`com.marvis.frideployer`) that runs **inside the emulator** at boot:

- On `BOOT_COMPLETED` it starts the configured target app (`com.example.target/.ui.LauncherUI` — edit in `MainActivity.java` / `BootReceiver.java`).
- If root is available it also:
  - copies the bundled `demo_hook.js` from assets to `/data/local/tmp/deploy_script.js`;
  - ensures `fsyd` (renamed frida-server) is running.

The actual Frida injection is done by the PC-side poller (`host/deploy_master.ps1`), which watches the target PID every 2 minutes and re-injects when the PID changes.

Key patterns (see `docs/GOTCHAS.md` §14):

- `goAsync()` + `PendingResult.finish()` inside the receiver, work on a separate thread — otherwise Android kills the background task.
- Assets: place `demo_hook.js` under `app/src/main/assets/` before building (or `gradlew :app:assembleDebug`).

## Layout

```
android/
├─ build.gradle            (root)
├─ settings.gradle
└─ app/
   ├─ build.gradle
   └─ src/main/
      ├─ AndroidManifest.xml
      └─ java/com/marvis/frideployer/
         ├─ MainActivity.java
         └─ BootReceiver.java
```
