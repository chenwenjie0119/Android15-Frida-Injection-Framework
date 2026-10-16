# 踩坑记录（GOTCHAS）—— 踩过的坑与正确方案

在 MuMu Android 15 模拟器（x86_64、已 root、无 Magisk）上部署 Frida 17.23.3 过程中遇到的每一个问题，以及最终验证有效的正确解法。

所有目标应用统一泛化为 `com.example.target`。

---

## 1. Frida 17.x 移除了内置 Java bridge

**现象**：Python API 脚本报 `ReferenceError: Java is not defined` / `TypeError: Java.perform is not a function`。

**根因**：Frida 17.x 把 Java bridge 移出了核心。CLI（`frida_tools.repl`）仍会注入全局 `Java`；Python API（`frida.get_device_manager()...create_script`）不会。

**解法**：Python API 脚本里显式加载 bridge：

```js
if (typeof Java === 'undefined') {
    try { Java = require('frida-java-bridge'); } catch (e) { send('JavaBridgeErr ' + e); }
}
```

或者所有需要 `Java` 的场景直接用 CLI。

## 2. `Module.findExportByName` 已改名

**现象**：Frida 17.x 下报 `TypeError: Module.findExportByName is not a function`。

**解法**：改用 `Module.findGlobalExportByName`（或 `Module.getGlobalExportByName`）。

## 3. Android 15 上 `frida-inject` 不可用

**现象**：`frida-inject-17.23.3-android-arm64` 在 Android 15 模拟器上失败，无法用独立 inject 二进制对运行中的应用做 APK 式注入。

**解法**：改用**远程通道**：模拟器内部署 `fsyd`（改名后的 frida-server），`adb forward tcp:47243 tcp:47243`，然后用 Frida CLI 或 Python API 通过 `-H 127.0.0.1:47243` attach/spawn。

## 4. MuMu 冷启动后 ADB 端口不稳定

**现象**：重启前 `adb connect 127.0.0.1:16416` 正常，冷启动后端口变成别的（`16384`、`16432`、`7555`、`5555`…）。

**解法**：每次运行前探测候选端口：

```powershell
foreach ($p in @('16416','16384','16432','7555','5555')) {
    & $adb connect "127.0.0.1:$p" | Out-Null
    $st = (& $adb -s "127.0.0.1:$p" get-state 2>$null)
    if ($st -eq 'device') { $ser = "127.0.0.1:$p"; break }
}
```

注意 MuMuManager 实例索引的坑：`MuMuManager control --vmindex 1` 的索引与 ADB 设备列表索引（显示 `emulator-5556` / 实例 3）不一致。

## 5. attach 太早会导致目标崩溃

**现象**：目标进程刚出现就注入，会干扰应用启动，几秒后应用死掉或异常。

**解法**：等进程稳定后再 attach。本环境实测 PID 出现后 **sleep 12 秒以上**（并重新确认 PID，因为极端情况下应用可能已重启过），再 attach。

## 6. load 期 Java 自检 + native read hook → 瞬间 SIGSEGV

**现象**：全量脚本在 load 期执行 `Java.perform(runSelfCheck)`（用 Java `FileInputStream` 读取 `/proc/self/maps` + `/proc/cpuinfo`，131KB+ 数据），叠加 native `read` hook 后，目标进程注入瞬间崩溃——启动 worker 线程 SIGSEGV（`0xb` / `SEGV_MAPERR`）。

**根因**：注入瞬间目标所有线程都被暂停。load 期自检用 Java 流读 `/proc`，同时 native `read` hook 又在拦截这些读取，两相交织导致早期 worker 线程访问空/低地址。

**解法**：彻底移除 load 期自检，改为 `rpc.exports.selfcheck = runSelfCheck` 手动触发。生成的 `*_noself*.js` 变体才是稳定可注入的版本。

## 7. 移除 load 期自检后仍有运行期延迟崩溃

**现象**：改用 noself 版本后，进程仍会在数分钟后于后台 Java 线程（`HeapTaskDaemon`）触发 `SIGSEGV code 128 fault addr 0x0` 崩溃——仅在全量 hook 集生效时出现。native-only 与 Java-only 子集都稳定。

**根因**：崩溃发生在模块间的**运行期交互**（不是 load 期）。不是所有模块都能在所有应用上安全共存。

**解法（方法论）**：**二分注入**。注入 `bisect_native.js`（仅 native）→ 稳定；注入 `bisect_java.js`（仅 Java）→ 稳定；注入全量 → 崩。然后逐步加回模块，找出冲突组合。本项目最终稳定版（`frida_full_noself2.js` 血统）移除了问题运行路径，连续存活 >3 分钟。

## 8. PC 端 adb input / sendevent 在 MuMu 上失效

**现象**：PC 端 `adb shell input tap` / `sendevent` 无法驱动模拟器 UI。

**解法**：用 `am start -n <pkg>/.ui.LauncherUI` 拉起目标 Activity，或用 PC 鼠标直接操作模拟器窗口。GPS 用 MuMu 自带 Nemu 虚拟定位（或 `MuMuManager control --vmindex N tool location`），不要用 `adb emu geo fix`。

## 9. `adb emu geo fix` 在 MuMu 上失败

**现象**：`adb emu geo fix` 报错。

**解法**：用 `MuMuManager control --vmindex 1 tool location` 设置 GPS。通过应用侧验证（系统层注入），不要看 PC 端日志。

## 10. 目标未登录 → 传感器不注册

**现象**：传感器相关 hook 看起来没生效。

**解法**：先登录目标应用；传感器和很多服务只有登录后才注册。进入主界面/小程序后再验证。

## 11. Python API spawn 需要 resume 和保活

**现象**：`dev.spawn([pkg])` 后 `attach` 成功，但忘记 `dev.resume(pid)` 应用永远不启动；脚本未 eternalize 时客户端退出脚本即死。

**解法**：必须 `script.load()` → `dev.resume(pid)`；CLI 用 `--eternalize`，或让 Python 客户端保持存活（见 `host/deploy_keep.py`——循环做进程列表存活检测）。

## 12. MuMu 上以 root 运行 frida-server

**现象**：`nohup /system/bin/fsyd` 立刻退出或权限错误。

**解法**：

```bash
adb shell su -c "nohup /system/bin/fsyd -l 0.0.0.0:47243 > /data/local/tmp/fsyd.log 2>&1 &"
```

用 `pidof fsyd` 验证。隐身卫生：清理 `/data/local/tmp/frida-server*` / `re.frida.server*` 特征文件。注意：MuMu 有 root 但**无 Magisk/Zygisk**，systemless 方案不可用。

## 13. Termux 里 pip install frida 编译失败

**现象**：Termux 内 `pip install frida` 编译/安装失败（目标平台没有预编译 wheel）。

**解法**：改用官方 devkit——`frida-devkit-android-x86_64-17.23.3.tar.xz`（见 `termux/termux_dl_devkit.sh`，带 GitHub 镜像回退链：gh-proxy → ghfast → ghproxy.net → mirror.ghproxy.com → github.moeyy.xyz）。装 python 前先把 apt 切到 TUNA 镜像（`termux_setup.sh`）。

## 14. 后台限制杀掉开机部署器

**现象**：APK 的 boot receiver 开始干活，随后被 Android 杀掉后台任务。

**解法**：receiver 内用 `goAsync()` + `PendingResult.finish()`，把复制/启动工作放到独立线程。这样能持有广播直到复制、启动完成。

---

## 验证稳定的正确流程（“正确方案”）

1. 获取 `frida-server-17.23.3-android-x86_64`，改名 `fsyd`。
2. `adb push fsyd /data/local/tmp/fsyd`，再 `su -c "cp ... /system/bin/fsyd && chmod 755 ..."`。
3. 清理 `/data/local/tmp` 特征文件；启动 `nohup /system/bin/fsyd -l 0.0.0.0:47243 &`。
4. `adb forward tcp:47243 tcp:47243`。
5. `frida-ps -H 127.0.0.1:47243` 确认通道。
6. 启动目标应用；等待 PID；**sleep 12s**；attach：

```
python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l <script>.js --runtime=v8 --eternalize -q
```

7. 自动化：用 Windows 计划任务每 2 分钟跑 `host/deploy_master.ps1`；用 `attach_done.flag` 只在 PID 变化时重新注入。
