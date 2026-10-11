## 安装

1. 下载下方的 `MideaBar-*.zip`，解压后把 `MideaBar.app` 拖进「应用程序」。
2. 准备后台程序 `midea-ac-agent`（见 [通信协议](https://github.com/Binaryify/MideaBar/blob/main/docs/agent-protocol.md)），放到 `~/.local/bin/midea-ac-agent`。
3. App 未经 Apple 公证，首次打开前在终端执行一次：
   ```bash
   xattr -dr com.apple.quarantine /Applications/MideaBar.app
   ```
4. 打开 MideaBar，按提示允许蓝牙权限。

支持 macOS 14 及以上，Apple 芯片与 Intel 通用。
