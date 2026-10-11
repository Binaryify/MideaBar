<p align="center">
  <img src="website/assets/icon.png" width="128" alt="MideaBar 图标">
</p>

<h1 align="center">MideaBar</h1>

<p align="center">在 macOS 菜单栏里直接用蓝牙控制美的 / 华凌空调——不经手机 App，不经云端。</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black.svg" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.10-orange.svg" alt="Swift 5.10">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT"></a>
</p>

<p align="center"><a href="https://binaryify.github.io/MideaBar/">官网</a> · <a href="website/assets/demo.mp4">演示视频</a> · <a href="docs/agent-protocol.md">通信协议</a></p>

<p align="center">
  <a href="website/assets/demo.mp4"><img src="website/assets/poster.jpg" width="480" alt="MideaBar 演示：点开菜单栏面板、开机、降温到 24℃、打开节能"></a>
</p>

> ⚠️ **免责声明**
>
> 本项目为个人开源项目，与美的集团及其子品牌无任何关联，也未获其授权；「美的」「华凌」等名称和商标归其所有者所有。
> 蓝牙通信协议来自对设备行为的公开研究，仅供学习与在自己的设备上使用，因使用本项目产生的一切后果由使用者自行承担。

## 功能

- 菜单栏显示当前设定温度，点击弹出控制面板
- 开关机、调温（16–30℃，步进 0.5）、模式、风速、扫风、节能、强劲
- 显示室内 / 室外温度；开机时空调插画会出风
- 操作即时生效（乐观更新），失败时自动回到设备的真实状态
- 后台断开后自动重启并重新连接

## 工作原理

```
MideaBar（SwiftUI 菜单栏界面）
   │  stdin / stdout，一行一条 JSON
   ▼
midea-ac-agent（后台程序，持有蓝牙长连接）
   │  BLE
   ▼
空调
```

MideaBar 只负责界面，不包含蓝牙协议实现。蓝牙部分由后台程序 `midea-ac-agent` 完成，两者之间的通信协议见 [docs/agent-protocol.md](docs/agent-protocol.md)，任何实现了该协议的程序都可以替换它。

参考实现：[midea-ble-go](https://github.com/midea-ble/midea-ble-go) 的 `cmd/midea-ac-agent`。

## 构建

需要 macOS 14+、Xcode 命令行工具，以及一个编译好的 `midea-ac-agent`。

```bash
git clone https://github.com/binaryify/MideaBar.git
cd MideaBar
make app AGENT=/path/to/midea-ac-agent
```

产物在 `build/MideaBar.app`，拖进「应用程序」即可。也可以直接打包并启动：

```bash
make run AGENT=/path/to/midea-ac-agent
```

首次启动时 macOS 会请求蓝牙权限，请允许。**请通过 Finder 或 `open` 启动 App**：直接在终端里运行 App 内的可执行文件，蓝牙权限会归到终端名下。

### 开发调试

不打包时，用环境变量指定后台程序路径：

```bash
swift build
MIDEA_AGENT=/path/to/midea-ac-agent .build/debug/MideaBar
```

### 修改图标

图标由 [Icon/make-icon.swift](Icon/make-icon.swift) 用 SwiftUI 代码绘制，修改后重新生成：

```bash
make icon
```

## 项目结构

```
MideaBar/
├── Sources/MideaBar/
│   ├── MideaBarApp.swift   # 入口：菜单栏图标与温度
│   ├── ControlPanel.swift  # 控制面板与各个控件
│   ├── ACUnitView.swift    # 空调插画与出风动画
│   ├── ACStore.swift       # 状态管理：事件 → 界面状态，用户操作 → 命令
│   ├── AgentClient.swift   # 后台进程的启动、收发与重启
│   └── Models.swift        # 模式 / 风速 / 扫风等枚举
├── Icon/make-icon.swift    # 图标源码
├── Resources/              # Info.plist、AppIcon.icns
├── docs/agent-protocol.md  # App 与后台程序的通信协议
└── website/                # 官网（GitHub Pages），含演示视频与图标
```

## 许可证

[MIT](LICENSE)
