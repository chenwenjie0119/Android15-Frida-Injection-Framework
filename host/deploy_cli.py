# deploy_cli.py - keep-alive CLI inject (eternalize)
# Spawns frida_tools.repl against the remote channel and keeps stdin open so
# the CLI does not exit (which would drop the injected runtime).
import subprocess, time, os

# --- EDIT ME ---
PY = r'C:\Program Files\Tencent\Marvis\MarvisAgent\1.60.2800.657\runtime\python311\python.exe'
JS = r'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\scripts\demo_hook.js'
TARGET_PKG = 'com.example.target'
LOG_DIR = r'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\logs'
LOG = os.path.join(LOG_DIR, 'cli_keep.log')
PID_FILE = os.path.join(LOG_DIR, 'cli_keep.pid')

cmd = [PY, '-m', 'frida_tools.repl', '-H', '127.0.0.1:47243', '-f', TARGET_PKG,
       '-l', JS, '--runtime=v8', '--eternalize', '-q']
with open(LOG, 'w', encoding='utf-8', errors='replace') as logf:
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                         stdout=logf, stderr=subprocess.STDOUT)
    with open(PID_FILE, 'w') as pf:
        pf.write(str(p.pid))
    # keep stdin pipe open so CLI does not exit on EOF
    while True:
        time.sleep(60)
