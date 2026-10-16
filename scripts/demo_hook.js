// demo_hook.js — generic demo hook (Java + native interceptor)
// Purpose: verify that attach/spawn injection works end-to-end.
// Usage: python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l demo_hook.js --runtime=v8 --eternalize -q
// Note: only hook APIs you are authorized to observe.

if (typeof Java === 'undefined') {
    try { Java = require('frida-java-bridge'); } catch (e) { send('JavaBridgeErr ' + e); }
}

// ---- Java side: hook System.currentTimeMillis as a harmless demo ----
try {
    if (typeof Java !== 'undefined') {
        Java.perform(function () {
            var Sys = Java.use('java.lang.System');
            Sys.currentTimeMillis.implementation = function () {
                var t = this.currentTimeMillis();
                send('[java] currentTimeMillis -> ' + t);
                return t;
            };
            send('[java] hook installed');
        });
    } else {
        send('[java] bridge unavailable, skipped');
    }
} catch (e) {
    send('[java] hook error: ' + e);
}

// ---- Native side: log open() calls as a harmless demo ----
try {
    var openPtr = Module.findGlobalExportByName('open');
    if (openPtr) {
        Interceptor.attach(openPtr, {
            onEnter: function (args) {
                var path = args[0].readCString();
                if (path && path.indexOf('/proc/') === 0) {
                    this.p = path;
                }
            },
            onLeave: function () {
                if (this.p) {
                    send('[native] open /proc file: ' + this.p);
                    this.p = null;
                }
            }
        });
        send('[native] open() hooked');
    } else {
        send('[native] open not found');
    }
} catch (e) {
    send('[native] hook error: ' + e);
}

send('demo_hook loaded');
