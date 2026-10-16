# scripts/ — Frida injection scripts

All scripts are generic and target-app agnostic. Replace `com.example.target` / `<PID>` with your own authorized test subject.

| File | Purpose |
|------|---------|
| `probe_java.js` | Minimal: check whether `Java` bridge / `require` / `Process` are available in this Frida version. |
| `probe_system.js` | Minimal: read `/proc/cpuinfo` and `/proc/self/maps` via the JS `File` API. |
| `demo_hook.js` | Generic demo hook: one Java hook + one native `open()` interceptor. Verifies injection end-to-end. |
| `bisect_native.js` | Native-only hooks. Use for crash isolation (GOTCHAS §7). |
| `bisect_java.js` | Java-only hooks. Use for crash isolation (GOTCHAS §7). |

## Usage

Attach by PID:

```
python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l scripts/demo_hook.js --runtime=v8 --eternalize -q
```

Spawn by package:

```
python -m frida_tools.repl -H 127.0.0.1:47243 -f com.example.target -l scripts/demo_hook.js --runtime=v8 --eternalize -q
```

Notes:

- Frida 17.x: CLI exposes global `Java`; Python API does not — scripts above handle both via `require('frida-java-bridge')`.
- Use `--runtime=v8`; default runtime may behave differently.
- Use `--eternalize` in production so the script survives client disconnect.
- After target PID appears, wait ~12s before attaching (see GOTCHAS §5).
