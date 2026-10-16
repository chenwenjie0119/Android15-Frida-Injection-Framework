# deploy_master.ps1 - MuMu auto deploy (idempotent, polled every 2 min)
# Generic version: injects the configured target package (change $TARGET_PKG).
# Wire this into Windows Task Scheduler on a 2-minute repeat, or run manually.
$adb = 'C:\Program Files\Netease\MuMu\nx_device\15.0\shell\adb.exe'
$py  = 'C:\Program Files\Tencent\Marvis\MarvisAgent\1.60.2800.657\runtime\python311\python.exe'
$js  = 'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\scripts\demo_hook.js'
$ser = '127.0.0.1:16416'
$log = 'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\logs\master.log'
$flag = 'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\logs\attach_done.flag'

# --- EDIT ME: target package ---
$TARGET_PKG = 'com.example.target'

function Log($m) {
  Add-Content $log ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m)
}
function AdbShell($c) {
  & $adb -s $ser shell $c 2>$null | ForEach-Object { $_.Trim() }
}
function AdbState {
  (& $adb -s $ser get-state 2>$null | ForEach-Object { $_.Trim() })
}

Log 'master tick'
# probe adb port (MuMu port may change after cold boot)
$ser = ''
foreach ($p in @('16416','16384','16432','7555','5555')) {
  & $adb connect "127.0.0.1:$p" 2>$null | Out-Null
  $st = (& $adb -s "127.0.0.1:$p" get-state 2>$null | ForEach-Object { $_.Trim() })
  if ($st -eq 'device') { $ser = "127.0.0.1:$p"; break }
}
if (-not $ser) { Log 'adb offline'; exit 0 }
Log ("adb port=" + $ser)

$boot = AdbShell 'getprop sys.boot_completed'
if ($boot -ne '1') { Log 'not booted yet'; exit 0 }

Log 'booted, forwarding'
& $adb -s $ser forward tcp:47243 tcp:47243 | Out-Null

$fs = AdbShell "su -c 'pidof fsyd'"
if (-not $fs) {
  AdbShell "su -c 'nohup /system/bin/fsyd -l 0.0.0.0:47243 > /data/local/tmp/fsyd.log 2>&1 &'" | Out-Null
  Start-Sleep -Seconds 10
  $fs = AdbShell "su -c 'pidof fsyd'"
}
Log ('fsyd pid=' + $fs)

# --- target attach inject (wait for boot settle, re-inject on pid change) ---
$wp = AdbShell "su -c 'pidof $TARGET_PKG'"
if (-not $wp) {
  AdbShell "am start -n $TARGET_PKG/.ui.LauncherUI" | Out-Null
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $wp = AdbShell "su -c 'pidof $TARGET_PKG'"
    if ($wp) { break }
  }
}
$prevPid = ''
if (Test-Path $flag) { $prevPid = ((Get-Content $flag -Raw) -split ' ')[0].Trim() }
if ($wp -and $wp -ne $prevPid) {
  Log ('target pid=' + $wp + ' settling, inject after 12s')
  Start-Sleep -Seconds 12
  $wp2 = AdbShell "su -c 'pidof $TARGET_PKG'"
  if ($wp2 -ne $wp) { $wp = $wp2; Start-Sleep -Seconds 8 }
  Log ('target pid=' + $wp + ' attach inject')
  & $py -m frida_tools.repl -H 127.0.0.1:47243 -p $wp -l $js --runtime=v8 --eternalize -q *> 'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\logs\attach_log.txt'
  $attach = Get-Content 'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\logs\attach_log.txt' -Raw
  if ($attach -match 'Failed to attach|Unable to|Error:') {
    Log ('attach FAILED, keep flag for retry')
  } else {
    Set-Content $flag ($wp + ' ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Log 'target injected'
  }
} else {
  Log ('target skip (pid=' + $wp + ', prev=' + $prevPid + ')')
}
Log 'master tick done'
