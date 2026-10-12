## 安装

1. 下载下方的 `MideaBar-*.zip`，解压后把 `MideaBar.app` 拖进「应用程序」。
2. 准备后台程序 `midea-ac-agent`（见 [通信协议](https://github.com/Binaryify/MideaBar/blob/main/docs/agent-protocol.md)），放到 `~/.local/bin/midea-ac-agent`。
3. App 未经 Apple 公证，首次打开前在终端执行一次：
   ```bash
   xattr -dr com.apple.quarantine /Applications/MideaBar.app
   ```
4. 打开 MideaBar，按提示允许蓝牙权限。

支持 macOS 14 及以上，Apple 芯片与 Intel 通用。界面支持简体中文与英文。

## Installation

1. Download `MideaBar-*.zip` below, unzip it and drag `MideaBar.app` into Applications.
2. Get the background program `midea-ac-agent` (see the [agent protocol](https://github.com/Binaryify/MideaBar/blob/main/docs/agent-protocol.en.md)) and put it at `~/.local/bin/midea-ac-agent`.
3. The app is not notarized by Apple. Before opening it for the first time, run in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MideaBar.app
   ```
4. Open MideaBar and allow Bluetooth access when prompted.

Requires macOS 14 or later; universal binary for Apple silicon and Intel. UI available in Simplified Chinese and English.
