# Android 15 Dynamic Analysis Injection Framework (Frida)

A complete, battle-tested engineering kit for deploying **Frida 17.23.3** on a **MuMu Android 15** emulator (x86_64, rooted, no Magisk), and using it for **remote attach / spawn injection, automated deploy loops, APK-based boot deploy, and in-emulator (Termux) autonomy**.

This is my first open-source project. It documents everything I learned the hard way:
- what worked and what didn't,
- every pitfall I hit (and the exact fix),
- clean, copy-paste deploy scripts,
- sanitized logs from a real session.

> Scope: the project stops at **"Frida is deployed and injection works"**. Target-app-specific hook logic is intentionally out of scope; scripts use a generic target placeholder so you can point them at any app you are authorized to test.

---

## Table of Contents

- [Features](#features)
- [Environment](#environment)
- [Repo Layout](#repo-layout)
- [Quick Start](#quick-start)
- [Deploy Chain (How It Works)](#deploy-chain-how-it-works)
- [Injection Command Reference](#injection-command-reference)
- [In-Emulator Autonomy (Termux)](#in-emulator-autonomy-termux)
- [APK Boot Deployer](#apk-boot-deployer)
- [Debugging Methodology](#debugging-methodology)
- [Known Pitfalls & Fixes](#known-pitfalls--fixes)
- [Sanitized Session Logs](#sanitized-session-logs)
- [Disclaimer](#disclaimer)

---

## Features

- **Stealth-deployed frida-server**: renamed `fsyd`, installed at `/system/bin/fsyd`, listens on `0.0.0.0:47243`, marker files cleaned from `/data/local/tmp`.
- **Remote channel over ADB**: `adb forward tcp:47243 tcp:47243`, then connect via `-H 127.0.0.1:47243`.
- **Both attach & spawn injection** through the Frida CLI (`frida_tools.repl`) and the Python API, with `--runtime=v8 --eternalize`.
- **Idempotent auto-deploy loop**: `deploy_master.ps1` polled every 2 minutes — waits for boot, finds the live ADB port, forwards, ensures `fsyd`, and injects once the target PID appears (with settle delay).
- **APK boot deployer**: a small Android app (`com.marvis.frideployer`) that copies the JS payload, starts `fsyd`, and launches the target on boot (`BootReceiver` + `goAsync` to survive background restrictions).
- **In-emulator autonomy (Termux)**: frida-tools + devkit installed inside the emulator via Termux, enabling deploy without a PC.
- **Bisect debugging methodology**: isolate crash causes by injecting native-only / Java-only / full script variants.
- **Full sanitized logs** from the development session.

## Environment

| Component | Value |
|-----------|-------|
| Emulator | MuMu (Netease) 15.0 |
| Android | 15, API 35, x86_64, rooted, **no Magisk / Zygisk** |
| Frida | 17.23.3 (frida-server renamed to `fsyd`) |
| Frida tooling | `frida-tools` (CLI), `frida` Python API |
| Runtime | V8 (`--runtime=v8`) |
| Host | Windows 11 |
| ADB | MuMu bundled: `C:\Program Files\Netease\MuMu\nx_device\15.0\shell\adb.exe` |
| MuMu console | `C:\Program Files\Netease\MuMu\nx_main\` (MuMuManager / mumu-cli) |

## Repo Layout

```
Frida-mumu-android15/
├── README.md                 # English doc (this file)
├── README_zh.md              # 中文文档
├── docs/
│   ├── GOTCHAS.md            # All pitfalls & correct solutions (EN)
│   └── GOTCHAS_zh.md         # 所有踩坑与正确方案 (中文)
├── scripts/
│   ├── probe_java.js         # tiny probe: Java/require/Process presence
│   ├── probe_system.js       # tiny probe: read /proc files via JS File API
│   ├── demo_hook.js          # generic demo hook (Java + native interceptor)
│   ├── bisect_native.js      # native-only hook (for crash isolation)
│   ├── bisect_java.js        # Java-only hook (for crash isolation)
│   └── README.md             # how to use each script
├── host/
│   ├── deploy_master.ps1     # idempotent 2-min polled auto deploy (Windows)
│   ├── deploy_auto.ps1       # one-shot wait->forward->deploy->inject
│   ├── deploy_cli.py         # keep-alive CLI inject (eternalize)
│   ├── deploy_keep.py        # Python API spawn+attach+keepalive
│   ├── verify_cpu.py         # verify /proc/cpuinfo inside target
│   └── probe_java.py         # remote attach Java probe
├── termux/
│   ├── termux_setup.sh       # switch to TUNA mirror + apt update
│   ├── termux_install_frida2.sh # install python + frida-tools
│   ├── termux_dl_devkit.sh   # download frida-devkit from mirror chain
│   └── termux_try_frida.sh   # diagnose pip/build issues
├── android/
│   ├── README.md             # build instructions
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/marvis/frideployer/
│       │   ├── MainActivity.java
│       │   └── BootReceiver.java
│       └── assets/demo_hook.js
├── logs/                     # sanitized real session logs
└── bin/
    └── GET_FRIDA_SERVER.md   # how to obtain frida-server & rename to fsyd
```

## Quick Start

### 1. Get & deploy frida-server

Download `frida-server-17.23.3-android-x86_64` from the [official Frida releases](https://github.com/frida/frida/releases), rename it to `fsyd`, then:

```bash
adb push fsyd /data/local/tmp/fsyd
adb shell su -c "cp /data/local/tmp/fsyd /system/bin/fsyd && chmod 755 /system/bin/fsyd"
# clean marker files (stealth hygiene)
adb shell su -c "rm -f /data/local/tmp/frida-server* /data/local/tmp/re.frida.server*"
# start it
adb shell su -c "nohup /system/bin/fsyd -l 0.0.0.0:47243 > /data/local/tmp/fsyd.log 2>&1 &"
```

See [bin/GET_FRIDA_SERVER.md](bin/GET_FRIDA_SERVER.md) for download mirror notes.

### 2. Forward the port

```bash
adb forward tcp:47243 tcp:47243
```

### 3. Verify the channel

```bash
adb shell su -c "pidof fsyd"
# -> 2723 (example)
frida-ps -H 127.0.0.1:47243
```

### 4. Inject (attach mode)

```bash
python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l scripts/demo_hook.js --runtime=v8 --eternalize -q
```

### 5. Inject (spawn mode)

```bash
python -m frida_tools.repl -H 127.0.0.1:47243 -f com.example.target -l scripts/demo_hook.js --runtime=v8 --eternalize -q
```

Replace `com.example.target` with the package you are authorized to test.

## Deploy Chain (How It Works)

```
MuMu cold boot
   │
   ├─ BootReceiver (APK) -> copies JS payload, starts fsyd
   │
   └─ PC poller (deploy_master.ps1, every 2 min)
        ├─ find live ADB port (MuMu may change it after cold boot)
        ├─ wait sys.boot_completed
        ├─ adb forward tcp:47243 tcp:47243
        ├─ ensure fsyd running (su, nohup)
        ├─ wait target PID, settle 12s
        └─ attach inject with --eternalize, record flag
```

Key details:

- **MuMu ADB port is not stable** across cold boots. `deploy_master.ps1` probes several candidate ports (`16416, 16384, 16432, 7555, 5555`) and picks the live one.
- **Always settle before attach**: after the target PID appears, sleep ~12s so the app finishes its startup critical path; early attach can destabilize boot.
- **`--eternalize`** keeps the injected runtime alive even if the CLI client disconnects.
- The **flag file** (`attach_done.flag`) stores the last injected PID so the poller re-injects only when the PID changes (e.g. app was force-stopped and restarted).

## Injection Command Reference

| Goal | Command |
|------|---------|
| Attach by PID (CLI) | `python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l <script.js> --runtime=v8 --eternalize -q` |
| Spawn by package (CLI) | `python -m frida_tools.repl -H 127.0.0.1:47243 -f <pkg> -l <script.js> --runtime=v8 --eternalize -q` |
| Attach (Python API) | see `host/deploy_keep.py` |
| List processes | `frida-ps -H 127.0.0.1:47243` |

**Frida 17.x notes (important):**

- The built-in Java bridge was removed from the core. The **CLI** still exposes a global `Java`; the **Python API** does **not**. In Python-API scripts, load the bridge explicitly: `require('frida-java-bridge')`.
- `Module.findExportByName` was renamed to `Module.findGlobalExportByName` in this line.

## In-Emulator Autonomy (Termux)

Install Termux in the emulator, then run the scripts in `termux/`:

1. `termux_setup.sh` — switch apt to TUNA mirror + `apt update`
2. `termux_install_frida2.sh` — `apt install python`, then `pip install frida-tools`
3. `termux_dl_devkit.sh` — download `frida-devkit-android-x86_64-17.23.3.tar.xz` through a GitHub mirror chain (gh-proxy, ghfast, etc.)
4. `termux_try_frida.sh` — diagnose build/pip issues

Then, from inside the emulator, you can run frida scripts without any PC involvement:

```bash
/data/data/com.termux/files/usr/bin/frida -H 127.0.0.1:47243 -p <PID> -l demo.js
```

## APK Boot Deployer

`android/` contains a minimal Android app (`com.marvis.frideployer`) that:

- On boot (`ACTION_BOOT_COMPLETED` / `QUICKBOOT_POWERON`), uses `goAsync()` to start a background thread,
- Copies the bundled JS payload (`assets/demo_hook.js`) to `/data/local/tmp/`,
- Ensures `fsyd` is running (with root),
- Launches the configured target app.

Build (requires JDK 17 + Android SDK + Gradle 8.5):

```bash
cd android
gradle assembleDebug
# output: app/build/outputs/apk/debug/app-debug.apk
adb install app/build/outputs/apk/debug/app-debug.apk
```

The Java sources are self-contained (no Gradle plugins beyond Android basics), so you can also compile manually with `javac` + `d8` + `apksigner` — see `android/README.md`.

## Debugging Methodology

When the injected script crashes the target, use **bisect injection**:

1. Inject `bisect_native.js` (native-only hooks) → if stable, natives are fine.
2. Inject `bisect_java.js` (Java-only hooks) → if stable, Java hooks are fine.
3. Inject the full script → if it crashes, the problem is the **combination / load-time interaction**.

Observed in this project: a full script whose **load time** performed a Java self-check (reading `/proc/self/maps` + `/proc/cpuinfo` via Java streams) on top of native `read` hooks crashed the target process instantly (SIGSEGV in a startup worker thread). Removing the load-time self-check (and making it manually triggerable via `rpc.exports`) fixed it.

General rules:

- Never run heavy Java I/O at script load time if you also hook native file reads.
- Wait for the app to settle before attaching (12s+ in this environment).
- Prefer `--eternalize` so scripts survive client disconnects.

## Known Pitfalls & Fixes

Every pitfall is documented with the exact fix in [docs/GOTCHAS.md](docs/GOTCHAS.md) (English) and [docs/GOTCHAS_zh.md](docs/GOTCHAS_zh.md) (中文). Highlights:

1. **Frida 17.x Java bridge**: absent in Python API → load `frida-java-bridge` explicitly.
2. **`frida-inject` is unusable on Android 15**: use the remote channel (`fsyd` + `adb forward`) instead of local binary injection.
3. **MuMu ADB port changes on reboot**: probe candidate ports before connecting.
4. **Early attach crashes the target**: settle 12s after PID appears.
5. **Load-time self-check + native read hooks → instant SIGSEGV**: remove load-time Java self-check; trigger manually via RPC.
6. **PC-side `adb input`/`sendevent` don't work on MuMu**: use `am start` to bring up the Activity or interact via PC mouse.
7. **`adb emu geo fix` fails on MuMu**: use MuMuManager / Nemu GPS virtual location instead.
8. **Target not logged in registers no sensor**: login before verifying sensor-related hooks.

## Sanitized Session Logs

`logs/` contains sanitized real session output from the development machine: deploy ticks, attach results, fsyd status, and crash diagnostics. All target-app identifiers were replaced with placeholders (`com.example.target`). Timestamps are real.

## ⚠️ 免责声明 (Disclaimer)

本项目及相关代码、文档仅供**移动安全技术学习、研究和授权测试**使用。

1. **授权范围**：任何人在使用本项目进行测试前，必须确保已获得目标系统或应用的**明确书面授权**。未经授权的测试行为可能违反《中华人民共和国网络安全法》等相关法律法规。
2. **禁止用途**：严禁将本项目用于任何非法用途，包括但不限于：未经授权入侵他人系统、窃取数据、破坏系统运行、制作或传播恶意软件、实施网络攻击等。
3. **模拟器限制**：本项目提供的所有示例和操作流程，**仅适用于个人隔离环境（如模拟器）**。严禁在真实用户设备、生产环境或未授权的系统上进行测试。
4. **责任豁免**：使用者须自行承担因使用本项目而产生的一切后果。作者不对任何因使用、修改或分发本项目而导致的直接或间接损失、法律责任承担任何责任。
5. **合规提醒**：请遵守当地法律法规及目标平台的服务条款。如发现任何安全漏洞，请通过正规渠道向厂商或平台报告，切勿公开或滥用。

**使用本项目即表示您已阅读并同意上述声明。**

## License

MIT
