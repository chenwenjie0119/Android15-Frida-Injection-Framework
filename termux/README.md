# termux/ — in-emulator (Termux) autonomous deploy scripts

Run these **inside the emulator** (via Termux) to make the emulator deploy frida by itself, no PC required.

| Script | Purpose |
|--------|---------|
| `termux_setup.sh` | Switch apt to TUNA mirror and `apt update`. |
| `termux_install_frida2.sh` | `apt install python`, then `pip install frida-tools`. |
| `termux_dl_devkit.sh` | Download `frida-devkit-android-x86_64-17.23.3.tar.xz` through a GitHub mirror fallback chain. |
| `termux_try_frida.sh` | Diagnose pip/build failures. |

Order:

```bash
sh termux_setup.sh
sh termux_install_frida2.sh
sh termux_dl_devkit.sh
```

Then you can inject from inside the emulator:

```bash
/data/data/com.termux/files/usr/bin/frida -H 127.0.0.1:47243 -p <PID> -l demo_hook.js
```

Notes:

- Termux `pip install frida` often fails because no prebuilt wheel exists for this target; prefer the official devkit download (`termux_dl_devkit.sh`).
- The devkit lands in `/data/data/com.termux/files/home/`.
