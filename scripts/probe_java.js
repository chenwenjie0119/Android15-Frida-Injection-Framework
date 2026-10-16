// probe_java.js — minimal probe: check Java bridge / require / Process availability
// Usage: python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l probe_java.js --runtime=v8 -q
send('typeof Java = ' + (typeof Java) +
     ' / typeof require = ' + (typeof require) +
     ' / Process = ' + (typeof Process !== 'undefined' ? 'ok' : 'no'));
