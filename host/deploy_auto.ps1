# deploy_auto.ps1 - MuMu emulator auto deploy (one-shot)
# Wait device online -> adb forward -> ensure frida-server(fsyd) running -> push script
# -> spawn inject target (eternalize) -> verify hook output
param(
    [string]$Dev = '127.0.0.1:16416',
    [int]$Port = 47243,
    [int]$WaitSec = 300
)

# --- EDIT ME: target package & paths ---
$TARGET_PKG = 'com.example.target'
$ADB = 'C:\Program Files\Netease\MuMu\nx_device\15.0\shell\adb.exe'
$JS  = 'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\scripts\demo_hook.js'
$DEST = '/data/local/tmp/deploy/demo_hook.js'
$LogDir = 'C:\Users\脑袋困掉了\Desktop\Frida-mumu-android15\logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'deploy.log'
$FridaOut = Join-Path $LogDir 'frida_stdout.log'
$FridaErr = Join-Path $LogDir 'frida_stderr.log'

function Log($m) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $m"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

Log '=== AutoDeploy start ==='

# 1. wait device online
Log "wait device $Dev online (max ${WaitSec}s)..."
$online = $false
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
    $st = & $ADB -s $Dev get-state 2>&1
    if ($st -match 'device') { $online = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $online) { Log 'FAIL: device offline'; exit 1 }
Log 'device online'

# 2. wait full boot
$booted = $false
$sw.Restart()
while ($sw.Elapsed.TotalSeconds -lt 120) {
    $b = & $ADB -s $Dev shell "getprop sys.boot_completed" 2>&1
    if ($b -match '1') { $booted = $true; break }
    Start-Sleep -Seconds 5
}
if ($booted) { Log 'system booted' } else { Log 'WARN: boot_completed not confirmed, continue' }

# 3. adb forward
& $ADB -s $Dev forward tcp:$Port tcp:$Port 2>&1 | ForEach-Object { Log "forward: $_" }

# 4. ensure fsyd running
$ps = & $ADB -s $Dev shell "su -c 'ps -A | grep fsyd'" 2>&1
if ($ps -match 'fsyd') {
    Log "fsyd running: $($ps.Trim())"
} else {
    Log 'fsyd not running, start it (background)...'
    & $ADB -s $Dev shell "su -c 'nohup /system/bin/fsyd -l 0.0.0.0:$Port -D >/dev/null 2>&1 &'" 2>&1 | ForEach-Object { Log "start output: $_" }
    Start-Sleep -Seconds 4
    $ps2 = & $ADB -s $Dev shell "su -c 'ps -A | grep fsyd'" 2>&1
    if ($ps2 -match 'fsyd') { Log "fsyd started: $($ps2.Trim())" } else { Log "FAIL: fsyd not started: $ps2"; exit 1 }
}

# 5. push script
& $ADB -s $Dev shell "su -c 'mkdir -p /data/local/tmp/deploy && chmod 777 /data/local/tmp/deploy'" 2>&1 | Out-Null
& $ADB -s $Dev push $JS $DEST 2>&1 | ForEach-Object { Log "push: $_" }
$md5 = & $ADB -s $Dev shell "su -c 'md5sum $DEST'" 2>&1
Log "script md5: $($md5.Trim())"

# 6. force-stop target for clean spawn
& $ADB -s $Dev shell "su -c 'am force-stop $TARGET_PKG'" 2>&1 | Out-Null
Start-Sleep -Seconds 2

# 7. cleanup old frida cli from previous run (stale after emulator reboot)
$PidFile = Join-Path $LogDir 'deploy.frida.pid'
if (Test-Path $PidFile) {
    $oldPid = (Get-Content $PidFile).Trim()
    if ($oldPid) {
        $old = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if ($old -and $old.ProcessName -match 'frida') {
            Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
            Log "killed stale frida cli pid=$oldPid"
        }
    }
}

# 8. spawn inject target (eternalize)
Log "spawn inject target: frida -H 127.0.0.1:$Port -f $TARGET_PKG -l $JS --eternalize"
$fridaProc = Start-Process -FilePath 'frida' -ArgumentList @('-H',"127.0.0.1:$Port",'-f',$TARGET_PKG,'-l',$JS,'--eternalize','-q') -RedirectStandardOutput $FridaOut -RedirectStandardError $FridaErr -PassThru -NoNewWindow

# 9. verify inject result
$verified = $false
for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Seconds 5
    $out = Get-Content $FridaOut -Raw -ErrorAction SilentlyContinue
    if ($out -match 'loaded|hook installed|BISECT|payload') {
        $verified = $true
        Log "inject verified after $i x 5s"
        Log '--- frida output excerpt ---'
        ($out -split "`n" | Select-String -Pattern 'java|native|loaded|hook' | Select-Object -First 8) | ForEach-Object { Log $_.Line.Trim() }
        break
    }
}
if (-not $verified) {
    Log 'WARN: no hook output found, dump below:'
    Get-Content $FridaOut -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { Log $_ }
}

# 10. keep frida cli alive
$PidFile = Join-Path $LogDir 'deploy.frida.pid'
Set-Content -Path $PidFile -Value $fridaProc.Id
Log "frida cli kept alive, pid=$($fridaProc.Id) (saved to $PidFile)"

# 11. final status
$tp = (& $ADB -s $Dev shell "su -c 'ps -A | grep $TARGET_PKG'" 2>&1 | Out-String).Trim()
if ($tp) { Log "target proc: $tp" } else { Log 'target proc: (none)' }
$fs = (& $ADB -s $Dev shell "su -c 'ps -A | grep fsyd'" 2>&1 | Out-String).Trim()
if ($fs) { Log "fsyd: $fs" } else { Log 'fsyd: (none)' }
Log '=== AutoDeploy done ==='
