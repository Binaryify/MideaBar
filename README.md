<p align="center">
  <img src="website/assets/icon.png" width="128" alt="MideaBar 图标">
</p>

<h1 align="center">MideaBar</h1>

<p align="center">在 macOS 菜单栏里直接用蓝牙控制美的 / 华凌空调——不经手机 App，不经云端。</p>

<p align="center">
  <a href="https://github.com/Binaryify/MideaBar/actions/workflows/ci.yml"><img src="https://github.com/Binaryify/MideaBar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Binaryify/MideaBar/releases"><img src="https://img.shields.io/github/v/release/Binaryify/MideaBar" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black.svg" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.10-orange.svg" alt="Swift 5.10">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT"></a>
</p>

<p align="center">简体中文 · <a href="README.en.md">English</a></p>

<p align="center"><a href="https://binaryify.github.io/MideaBar/">官网</a> · <a href="website/assets/demo.mp4">演示视频</a> · <a href="docs/protocol.md">蓝牙协议</a></p>

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
- 蓝牙直连，不需要配对、账号或任何额外程序；断线自动重连
- 界面支持简体中文 / English，默认跟随系统，也可手动切换

## 工作原理

```
SwiftUI 界面（ControlPanel / ACStore）
   │
ACLink（CoreBluetooth：扫描、连接、重发、重连）
   │
MideaProtocol（帧、AES-CCM 加密、ECDH 握手、家电帧）
   │  BLE
   ▼
空调
```

App 从空调的蓝牙广播里读出序列号和 MAC，推出根密钥，再经 ECDH 握手协商会话密钥，之后用加密的美的家电帧收发控制与状态。完整说明见 [docs/protocol.md](docs/protocol.md)。

协议部分（`MideaProtocol`）是纯 Swift 实现、不依赖蓝牙，有单元测试；一致性向量取自参考实现 [midea-ble-go](https://github.com/midea-ble/midea-ble-go)。

## 安装

1. 从 [Releases](https://github.com/Binaryify/MideaBar/releases) 下载 `MideaBar-*.zip`，解压后把 `MideaBar.app` 拖进「应用程序」。支持 macOS 14+，Apple 芯片与 Intel 通用。
2. App 未经 Apple 公证，首次打开前执行一次：

   ```bash
   xattr -dr com.apple.quarantine /Applications/MideaBar.app
   ```

3. 打开 MideaBar，按提示允许蓝牙权限。App 会扫描附近的空调，连接信号最强的一台，之后优先连接这台。

目前只在作者的一台空调上验证过。其他带蓝牙的美的 / 华凌型号理论上可用，欢迎在 [Issues](https://github.com/Binaryify/MideaBar/issues) 反馈结果。

## 从源码构建

需要 macOS 14+ 和 Xcode。

```bash
git clone https://github.com/binaryify/MideaBar.git
cd MideaBar
make test   # 协议单元测试
make run    # 打包并启动
```

产物在 `build/MideaBar.app`。

`make dist` 会再打成发布用的 zip。推送 `v*` 标签（如 `v0.1.0`）时，GitHub Actions 会自动构建并发布到 Releases。

首次启动时 macOS 会请求蓝牙权限，请允许。**请通过 Finder 或 `open` 启动 App**：直接在终端里运行 App 内的可执行文件，蓝牙权限会归到终端名下。本地构建是临时签名，每次重新构建后系统都会再问一次蓝牙权限。

### 调试日志

连接过程写入系统日志，可以这样查看：

```bash
log stream --info --predicate 'subsystem == "com.github.binaryify.mideabar"'
```

### 界面语言

界面默认跟随系统语言，目前支持简体中文与英文；也可以在面板右下角的设置菜单 →「语言」里手动切换（App 会自动重启）。代码里直接写中文（`Text("室内")`、`String(localized: "制冷")`），中文即翻译键；英文译文在 [Resources/en.lproj/Localizable.strings](Resources/en.lproj/Localizable.strings)。新增语言：添加 `Resources/<语言>.lproj/`，在 `Info.plist` 的 `CFBundleLocalizations` 里登记，并在 `AppLanguage` 里加一项。

文档同样中英各一份（`README.md` / `README.en.md`、`docs/protocol.md` / `docs/protocol.en.md`），修改时请同步两边。官网的英文文案在 `website/index.html` 末尾脚本的 `EN` 对象里。

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
│   ├── ACStore.swift       # 状态管理：设备状态 → 界面，用户操作 → 命令
│   ├── ACLink.swift        # CoreBluetooth：扫描、连接、握手时序、重发、重连
│   ├── AppLanguage.swift   # 界面语言：跟随系统 / 手动切换
│   └── Models.swift        # 模式 / 风速 / 扫风的显示名与图标
├── Sources/MideaProtocol/  # 蓝牙协议：帧、加密、握手、家电帧（纯算法）
├── Tests/                  # 协议单元测试
├── Icon/make-icon.swift    # 图标源码
├── Resources/              # Info.plist、AppIcon.icns、*.lproj（界面翻译）
├── docs/protocol.md        # 蓝牙协议说明（另有 .en.md 英文版）
└── website/                # 官网（GitHub Pages，中英双语），含演示视频与图标
```

## 许可证

[MIT](LICENSE)
