// bisect_java.js — Java-only hooks for crash isolation
// Purpose: when the full hook set crashes the target, inject this to check whether
// Java hooks alone are stable. See docs/GOTCHAS.md §7.
// Usage: python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l bisect_java.js --runtime=v8 -q

send('BISECT java-only start');

if (typeof Java === 'undefined') {
    try { Java = require('frida-java-bridge'); } catch (e) { send('JavaBridgeErr ' + e); }
}

try {
    if (typeof Java !== 'undefined') {
        Java.perform(function () {
            var Runtime = Java.use('java.lang.Runtime');
            Runtime.availableProcessors.implementation = function () {
                var r = this.availableProcessors();
                send('[j] availableProcessors -> ' + r);
                return r;
            };
            send('BISECT java-only hooks installed');
        });
    } else {
        send('BISECT java bridge unavailable');
    }
} catch (e) {
    send('BISECT java error: ' + e);
}
