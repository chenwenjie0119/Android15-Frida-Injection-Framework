// bisect_native.js — native-only hooks for crash isolation
// Purpose: when the full hook set crashes the target, inject this to check whether
// native hooks alone are stable. See docs/GOTCHAS.md §7.
// Usage: python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l bisect_native.js --runtime=v8 -q

send('BISECT native-only start');

try {
    var openPtr = Module.findGlobalExportByName('open');
    if (openPtr) {
        Interceptor.attach(openPtr, {
            onEnter: function (args) {
                var p = args[0].readCString();
                if (p && p.indexOf('/proc/') === 0) { this.p = p; }
            },
            onLeave: function () {
                if (this.p) { send('[n] open ' + this.p); this.p = null; }
            }
        });
    }
    var readPtr = Module.findGlobalExportByName('read');
    if (readPtr) {
        Interceptor.attach(readPtr, {
            onEnter: function (args) {
                this.fd = args[0].toInt32();
                this.buf = args[1];
                this.n = args[2].toInt32();
            },
            onLeave: function (retval) {
                if (this.fd === 0 || this.fd === 1 || this.fd === 2) {
                    send('[n] read fd=' + this.fd + ' n=' + this.n + ' ret=' + retval);
                }
            }
        });
    }
    send('BISECT native-only hooks installed');
} catch (e) {
    send('BISECT native error: ' + e);
}
