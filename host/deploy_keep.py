# deploy_keep.py - Python API spawn + attach + keepalive
# Demonstrates the Frida Python API against the remote channel:
#   add_remote_device('127.0.0.1:47243') -> spawn -> attach -> create_script(v8)
#   -> load -> resume -> periodic liveness check.
import frida, sys, time, json, traceback

# --- EDIT ME ---
DEV_ADDR = '127.0.0.1:47243'
PKG = 'com.example.target'
JS_PATH = r'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\scripts\demo_hook.js'
LOG_PATH = r'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\logs\keep.log'

def log(msg):
    with open(LOG_PATH, 'a', encoding='utf-8') as f:
        f.write('[%s] %s\n' % (time.strftime('%H:%M:%S'), msg))

def on_message(message, data):
    try:
        line = json.dumps(message, ensure_ascii=False)
    except Exception:
        line = str(message)
    log('MSG ' + line)
    print(line, flush=True)

log('=== deploy_keep start ===')
try:
    dev = frida.get_device_manager().add_remote_device(DEV_ADDR)
    log('device ok')
    pid = dev.spawn([PKG])
    log('spawned pid=%d' % pid)
    session = dev.attach(pid)
    log('attached')
    src = open(JS_PATH, encoding='utf-8').read()
    script = session.create_script(src, runtime='v8')
    log('script created runtime=v8')
    script.on('message', on_message)
    script.load()
    log('script loaded')
    dev.resume(pid)
    log('resumed')
    while True:
        time.sleep(10)
        try:
            ps = [p.pid for p in dev.enumerate_processes()]
            alive = pid in ps
        except Exception:
            alive = None
        log('alive check: pid=%d in list=%s' % (pid, alive))
except Exception:
    log('FATAL: ' + traceback.format_exc())
    print(traceback.format_exc(), flush=True)
