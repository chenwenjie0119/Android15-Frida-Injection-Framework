// probe_system.js — minimal probe: read /proc files via JS File API
// Usage: python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l probe_system.js --runtime=v8 -q
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
send('cpuinfo len=' + ci.length);
send('cpuinfo head=' + ci.substring(0, 120));
var maps = read('/proc/self/maps');
send('maps len=' + maps.length);
send('maps frida=' + (maps.indexOf('frida') >= 0 ? 'LEAK' : 'GONE'));
