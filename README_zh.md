# Android 15 动态分析注入框架（Frida）—— 中文文档

一套经过真实踩坑验证的完整工程包：在 **MuMu Android 15 模拟器**（x86_64、已 root、无 Magisk）上部署 **Frida 17.23.3**，并完成**远程 attach / spawn 注入、自动化部署轮询、APK 开机自启部署、模拟器内（Termux）自治部署**。

这是我人生第一个开源项目。这里记录了所有摸索过程的产物：

- 什么能用、什么不能用；
- 我踩过的每一个坑（以及对应的正确解法）；
- 可直接复制使用的部署脚本；
- 真实会话中脱敏后的完整日志。

> 项目边界：只到 **「Frida 部署成功且注入生效」** 为止。目标 App 的具体 hook 逻辑不在范围内；脚本统一使用通用目标包名占位符，你可以把它指向任何你有权限测试的应用。

---

## 目录

- [功能特性](#功能特性)
- [环境要求](#环境要求)
- [仓库结构](#仓库结构)
- [快速开始](#快速开始)
- [部署链路（原理）](#部署链路原理)
- [注入命令参考](#注入命令参考)
- [模拟器内自治（Termux）](#模拟器内自治termux)
- [APK 开机部署器](#apk-开机部署器)
- [调试方法论](#调试方法论)
- [踩坑与正确方案](#踩坑与正确方案)
- [脱敏会话日志](#脱敏会话日志)
- [免责声明](#免责声明)

---

## 功能特性

- **隐身部署 frida-server**：改名为 `fsyd`，安装到 `/system/bin/fsyd`，监听 `0.0.0.0:47243`，并清理 `/data/local/tmp` 下的特征文件。
- **ADB 远程通道**：`adb forward tcp:47243 tcp:47243` 后通过 `-H 127.0.0.1:47243` 连接。
- **attach 与 spawn 两种注入方式**：CLI（`frida_tools.repl`）与 Python API 均可用，统一 `--runtime=v8 --eternalize`。
- **幂等自动部署轮询**：`deploy_master.ps1` 每 2 分钟轮询一次——等待开机、探测存活 ADB 端口、端口转发、确保 fsyd 运行、目标进程出现后（带冷却等待）自动注入。
- **APK 开机部署器**：一个小型安卓应用（`com.marvis.frideployer`），开机时复制 JS 脚本、拉起 fsyd、启动目标应用（`BootReceiver` + `goAsync` 规避后台限制）。
- **模拟器内自治（Termux）**：在模拟器内通过 Termux 安装 frida-tools 与 devkit，实现不依赖 PC 的部署。
- **二分调试方法论**：用 native-only / Java-only / 全量脚本对照定位崩溃根因。
- **完整脱敏日志**：开发过程中的真实会话日志。

## 环境要求

| 组件 | 值 |
|------|----|
| 模拟器 | MuMu（网易）15.0 |
| 系统 | Android 15，API 35，x86_64，已 root，**无 Magisk / Zygisk** |
| Frida | 17.23.3（frida-server 改名为 `fsyd`） |
| Frida 工具链 | `frida-tools`（CLI）、`frida` Python API |
| 运行器 | V8（`--runtime=v8`） |
| 宿主机 | Windows 11 |
| ADB | MuMu 自带：`C:\Program Files\Netease\MuMu\nx_device\15.0\shell\adb.exe` |
| MuMu 控制台 | `C:\Program Files\Netease\MuMu\nx_main\`（MuMuManager / mumu-cli） |

## 仓库结构

```
Frida-mumu-android15/
├── README.md                 # 英文文档
├── README_zh.md              # 本文件（中文）
├── docs/
│   ├── GOTCHAS.md            # 所有踩坑与正确方案（英文）
│   └── GOTCHAS_zh.md         # 所有踩坑与正确方案（中文）
├── scripts/
│   ├── probe_java.js         # 迷你探针：检查 Java/require/Process 是否可用
│   ├── probe_system.js       # 迷你探针：用 JS File API 读取 /proc 文件
│   ├── demo_hook.js          # 通用演示 hook（Java + native 拦截器）
│   ├── bisect_native.js      # 仅 native hook（用于崩溃隔离）
│   ├── bisect_java.js        # 仅 Java hook（用于崩溃隔离）
│   └── README.md             # 各脚本使用说明
├── host/
│   ├── deploy_master.ps1     # 幂等 2 分钟轮询自动部署（Windows）
│   ├── deploy_auto.ps1       # 一次性：等待→转发→部署→注入
│   ├── deploy_cli.py         # CLI 常驻注入（eternalize）
│   ├── deploy_keep.py        # Python API spawn+attach+保活
│   ├── verify_cpu.py         # 验证目标内 /proc/cpuinfo
│   └── probe_java.py         # 远程 attach Java 探针
├── termux/
│   ├── termux_setup.sh       # 切换 TUNA 镜像 + apt update
│   ├── termux_install_frida2.sh # 安装 python + frida-tools
│   ├── termux_dl_devkit.sh   # 从镜像链下载 frida-devkit
│   └── termux_try_frida.sh   # 诊断 pip/编译问题
├── android/
│   ├── README.md             # 构建说明
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/marvis/frideployer/
│       │   ├── MainActivity.java
│       │   └── BootReceiver.java
│       └── assets/demo_hook.js
├── logs/                     # 脱敏真实会话日志
└── bin/
    └── GET_FRIDA_SERVER.md   # 如何获取 frida-server 并改名 fsyd
```

## 快速开始

### 1. 获取并部署 frida-server

从 [官方 Frida releases](https://github.com/frida/frida/releases) 下载 `frida-server-17.23.3-android-x86_64`，改名为 `fsyd`：

```bash
adb push fsyd /data/local/tmp/fsyd
adb shell su -c "cp /data/local/tmp/fsyd /system/bin/fsyd && chmod 755 /system/bin/fsyd"
# 清理特征文件（隐身卫生）
adb shell su -c "rm -f /data/local/tmp/frida-server* /data/local/tmp/re.frida.server*"
# 启动
adb shell su -c "nohup /system/bin/fsyd -l 0.0.0.0:47243 > /data/local/tmp/fsyd.log 2>&1 &"
```

镜像下载说明见 [bin/GET_FRIDA_SERVER.md](bin/GET_FRIDA_SERVER.md)。

### 2. 端口转发

```bash
adb forward tcp:47243 tcp:47243
```

### 3. 验证通道

```bash
adb shell su -c "pidof fsyd"
# -> 2723（示例）
frida-ps -H 127.0.0.1:47243
```

### 4. 注入（attach 模式）

```bash
python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l scripts/demo_hook.js --runtime=v8 --eternalize -q
```

### 5. 注入（spawn 模式）

```bash
python -m frida_tools.repl -H 127.0.0.1:47243 -f com.example.target -l scripts/demo_hook.js --runtime=v8 --eternalize -q
```

把 `com.example.target` 换成你有权测试的包名。

## 部署链路（原理）

```
MuMu 冷启动
   │
   ├─ BootReceiver（APK）→ 复制 JS 脚本、启动 fsyd
   │
   └─ PC 轮询器（deploy_master.ps1，每 2 分钟）
        ├─ 探测存活 ADB 端口（MuMu 冷启动后端口可能变化）
        ├─ 等待 sys.boot_completed
        ├─ adb forward tcp:47243 tcp:47243
        ├─ 确保 fsyd 运行（su + nohup）
        ├─ 等待目标 PID，冷却 12 秒
        └─ attach 注入（--eternalize），记录 flag
```

关键细节：

- **MuMu 的 ADB 端口冷启动后不稳定**。`deploy_master.ps1` 会探测多个候选端口（`16416, 16384, 16432, 7555, 5555`）取可用者。
- **attach 前务必冷却**：目标 PID 出现后再等约 12 秒，让应用走完启动关键路径；过早 attach 会干扰启动导致崩溃。
- **`--eternalize`**：即使 CLI 客户端断开，注入的运行时也保持存活。
- **flag 文件**（`attach_done.flag`）记录上次注入的 PID，轮询器只在 PID 变化时重新注入（例如应用被强杀后重启）。

## 注入命令参考

| 目的 | 命令 |
|------|------|
| 按 PID attach（CLI） | `python -m frida_tools.repl -H 127.0.0.1:47243 -p <PID> -l <script.js> --runtime=v8 --eternalize -q` |
| 按包名 spawn（CLI） | `python -m frida_tools.repl -H 127.0.0.1:47243 -f <pkg> -l <script.js> --runtime=v8 --eternalize -q` |
| Python API attach | 见 `host/deploy_keep.py` |
| 列出进程 | `frida-ps -H 127.0.0.1:47243` |

**Frida 17.x 注意事项（重要）：**

- 内置 Java bridge 已从核心移除。**CLI 仍暴露全局 `Java`**；**Python API 没有**。Python API 脚本里需显式加载 bridge：`require('frida-java-bridge')`。
- 该版本中 `Module.findExportByName` 已改名为 `Module.findGlobalExportByName`。

## 模拟器内自治（Termux）

在模拟器内安装 Termux，依次执行 `termux/` 下的脚本：

1. `termux_setup.sh` — apt 切换 TUNA 镜像 + `apt update`
2. `termux_install_frida2.sh` — `apt install python`，再 `pip install frida-tools`
3. `termux_dl_devkit.sh` — 通过 GitHub 镜像链（gh-proxy、ghfast 等）下载 `frida-devkit-android-x86_64-17.23.3.tar.xz`
4. `termux_try_frida.sh` — 诊断编译/pip 问题

之后即可在模拟器内不依赖 PC 运行 frida 脚本：

```bash
/data/data/com.termux/files/usr/bin/frida -H 127.0.0.1:47243 -p <PID> -l demo.js
```

## APK 开机部署器

`android/` 是一个极简安卓应用（`com.marvis.frideployer`），功能：

- 开机（`ACTION_BOOT_COMPLETED` / `QUICKBOOT_POWERON`）时用 `goAsync()` 启动后台线程；
- 把内置 JS 脚本（`assets/demo_hook.js`）复制到 `/data/local/tmp/`；
- 确保 `fsyd` 已运行（需要 root）；
- 启动配置的目标应用。

构建（需要 JDK 17 + Android SDK + Gradle 8.5）：

```bash
cd android
gradle assembleDebug
# 输出：app/build/outputs/apk/debug/app-debug.apk
adb install app/build/outputs/apk/debug/app-debug.apk
```

Java 源码是自包含的（除 Android 基础插件外无额外 Gradle 插件），也可以用 `javac` + `d8` + `apksigner` 手动编译，见 `android/README.md`。

## 调试方法论

当注入脚本导致目标崩溃时，用**二分注入**定位：

1. 注入 `bisect_native.js`（仅 native hook）→ 若稳定，说明 native 没问题。
2. 注入 `bisect_java.js`（仅 Java hook）→ 若稳定，说明 Java hook 没问题。
3. 注入全量脚本 → 若崩溃，说明问题出在**组合 / load 期交互**。

本项目实测：全量脚本在 **load 期**执行 Java 自检（用 Java 流读取 `/proc/self/maps` + `/proc/cpuinfo`），叠加 native `read` hook 后，目标进程立即崩溃（启动 worker 线程 SIGSEGV）。把 load 期自检移除（改为 `rpc.exports` 手动触发）后即稳定。

通用规则：

- 如果你同时 hook 了 native 文件读取，不要在脚本 load 期做重型 Java I/O。
- 等应用稳定后再 attach（本环境实测 12 秒以上）。
- 优先 `--eternalize`，让脚本在客户端断开后继续存活。

## 踩坑与正确方案

所有坑与对应解法完整记录在 [docs/GOTCHAS.md](docs/GOTCHAS.md)（英文）和 [docs/GOTCHAS_zh.md](docs/GOTCHAS_zh.md)（中文）。要点：

1. **Frida 17.x Java bridge**：Python API 没有 → 显式加载 `frida-java-bridge`。
2. **Android 15 上 `frida-inject` 不可用**：改用远程通道（`fsyd` + `adb forward`）。
3. **MuMu 重启后 ADB 端口变化**：先探测候选端口。
4. **过早 attach 导致目标崩溃**：PID 出现后冷却 12 秒。
5. **load 期自检 + native read hook → 瞬间 SIGSEGV**：移除 load 期 Java 自检，改 RPC 手动触发。
6. **PC 端 `adb input`/`sendevent` 在 MuMu 失效**：用 `am start` 拉 Activity，或用 PC 鼠标点击。
7. **`adb emu geo fix` 在 MuMu 失败**：改用 MuMuManager / Nemu GPS 虚拟定位。
8. **目标未登录时不注册传感器**：验证传感器相关 hook 前先登录。

## 脱敏会话日志

`logs/` 中存放开发机上的真实会话输出（脱敏后）：部署轮询记录、attach 结果、fsyd 状态、崩溃诊断。所有目标应用标识已替换为占位符（`com.example.target`）。时间戳为真实值。

## ⚠️ 免责声明 (Disclaimer)

本项目及相关代码、文档仅供**移动安全技术学习、研究和授权测试**使用。

1. **授权范围**：任何人在使用本项目进行测试前，必须确保已获得目标系统或应用的**明确书面授权**。未经授权的测试行为可能违反《中华人民共和国网络安全法》等相关法律法规。
2. **禁止用途**：严禁将本项目用于任何非法用途，包括但不限于：未经授权入侵他人系统、窃取数据、破坏系统运行、制作或传播恶意软件、实施网络攻击等。
3. **模拟器限制**：本项目提供的所有示例和操作流程，**仅适用于个人隔离环境（如模拟器）**。严禁在真实用户设备、生产环境或未授权的系统上进行测试。
4. **责任豁免**：使用者须自行承担因使用本项目而产生的一切后果。作者不对任何因使用、修改或分发本项目而导致的直接或间接损失、法律责任承担任何责任。
5. **合规提醒**：请遵守当地法律法规及目标平台的服务条款。如发现任何安全漏洞，请通过正规渠道向厂商或平台报告，切勿公开或滥用。

**使用本项目即表示您已阅读并同意上述声明。**

## License

MIT
