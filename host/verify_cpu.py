# verify_cpu.py - verify /proc/cpuinfo content as seen inside the target process
# Usage: python verify_cpu.py <PID>
import frida, time, sys

HOST = '127.0.0.1:47243'
PID = int(sys.argv[1])

d = frida.get_device_manager().add_remote_device(HOST)
s = d.attach(PID)

code = r'''
function read(path) {
    try {
        var f = new File(path, 'r');
        var buf = f.readBytes(65536);
        f.close();
        var s = '';
        for (var i = 0; i < buf.length; i++) s += String.fromCharCode(buf[i]);
        return s;
    } catch (e) { return 'ERR ' + e; }
}
var ci = read('/proc/cpuinfo');
send('CI len=' + ci.length);
send('CI head=' + ci.substring(0, 120));
'''
sc = s.create_script(code)
sc.on('message', lambda m, d: print('MSG:', m.get('payload', m)))
sc.load()
time.sleep(6)
