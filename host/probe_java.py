# probe_java.py - remote attach Java probe
# Usage: python probe_java.py <PID>
import frida, time, sys

HOST = '127.0.0.1:47243'
PID = int(sys.argv[1])
d = frida.get_device_manager().add_remote_device(HOST)
s = d.attach(PID)
sc = s.create_script("send(typeof Java + ' / ' + typeof require + ' / ' + (typeof Process !== 'undefined' ? 'ok' : 'no'))")
sc.on('message', lambda m, d: print('MSG:', m.get('payload', m)))
sc.load()
time.sleep(3)
