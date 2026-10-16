# bin/ — frida-server acquisition

GitHub has a 100 MB per-file soft limit, so this repo does **not** vendor the frida-server binary (~116 MB unpacked). Download it instead:

## 1. Download frida-server 17.23.3

From [official Frida releases](https://github.com/frida/frida/releases/tag/17.23.3):

- `frida-server-17.23.3-android-x86_64.xz` (MuMu Android 15 x86_64)

Local mirrors if GitHub is slow:

```
https://gh-proxy.com/https://github.com/frida/frida/releases/download/17.23.3/frida-server-17.23.3-android-x86_64.xz
https://ghfast.top/https://github.com/frida/frida/releases/download/17.23.3/frida-server-17.23.3-android-x86_64.xz
```

## 2. Decompress & rename to fsyd

```bash
xz -d frida-server-17.23.3-android-x86_64.xz
mv frida-server-17.23.3-android-x86_64 fsyd
```

## 3. Deploy to /system/bin

```bash
adb push fsyd /data/local/tmp/fsyd
adb shell su -c "cp /data/local/tmp/fsyd /system/bin/fsyd && chmod 755 /system/bin/fsyd"
# stealth hygiene: remove marker files
adb shell su -c "rm -f /data/local/tmp/frida-server* /data/local/tmp/re.frida.server*"
adb shell su -c "nohup /system/bin/fsyd -l 0.0.0.0:47243 > /data/local/tmp/fsyd.log 2>&1 &"
```

## 4. Verify

```bash
adb shell su -c "pidof fsyd"
adb forward tcp:47243 tcp:47243
frida-ps -H 127.0.0.1:47243
```

## Why rename?

- `/system/bin/fsyd` is the default location this repo's deploy scripts expect.
- A custom name avoids the well-known `frida-server` string in `ps` output / `/proc` scans (stealth hygiene). The listener port is also non-default (47243).
