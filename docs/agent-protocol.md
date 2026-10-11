# Agent 通信协议

MideaBar 本身不实现蓝牙协议。它启动一个后台程序 `midea-ac-agent`，由后台程序持有和空调的蓝牙长连接，两者通过 **stdin / stdout 收发 JSON，一行一条消息**（JSON Lines）。

任何实现了本协议的程序都能作为 MideaBar 的后台。参考实现见 [midea-ble-go](https://github.com/midea-ble/midea-ble-go) 的 `cmd/midea-ac-agent`。

## 进程约定

- MideaBar 启动时按以下顺序查找 agent，用第一个找到的：
  1. App 包内的 `Contents/MacOS/midea-ac-agent`
  2. 环境变量 `MIDEA_AGENT` 指定的路径（开发调试用）
  3. `~/.local/bin/midea-ac-agent`、`/opt/homebrew/bin/midea-ac-agent`、`/usr/local/bin/midea-ac-agent`
- agent 的 **stdout 只能输出协议消息**。日志、进度提示等一律写到 stderr，MideaBar 会忽略 stderr。
- MideaBar 退出时关闭 agent 的 stdin。agent 读到 EOF 后应断开蓝牙并退出。
- agent 意外退出时，MideaBar 会在 2 秒后重启它并重新连接。
- agent 应串行执行命令：前一条命令完成（或失败）后再执行下一条。

## 命令（MideaBar → agent）

| 命令 | 含义 |
|---|---|
| `{"op":"connect","sn":""}` | 连接设备。`sn` 为空时，agent 自行选择设备（参考实现：先选已知设备列表里的第一台，没有已知设备就扫描并连接信号最强的那台）。 |
| `{"op":"refresh"}` | 主动查询一次状态。 |
| `{"op":"power","on":true}` | 开关机。 |
| `{"op":"mode","value":"cool"}` | 模式：`auto` / `cool` / `dry` / `heat` / `fan`。 |
| `{"op":"temp","temp":25.5}` | 设定温度，16–30℃，步进 0.5。 |
| `{"op":"fan","value":"auto"}` | 风速：`auto` / `low` / `mid` / `high` / `full`。 |
| `{"op":"swing","ud":true,"lr":false}` | 扫风：上下 / 左右。 |
| `{"op":"eco","on":true}` | 节能模式。 |
| `{"op":"strong","on":true}` | 强劲模式。 |
| `{"op":"beep","on":false}` | 控制时空调是否发出提示音（本地偏好，不产生状态事件）。 |

## 事件（agent → MideaBar）

### 连接状态 `link`

```json
{"type":"link","state":"connected","sn":"22040055AC2615"}
{"type":"link","state":"error","message":"握手失败: …","sn":"22040055AC2615"}
```

| `state` | 含义 |
|---|---|
| `connecting` | 正在扫描或握手 |
| `connected` | 已连接；每条控制命令成功后也会发一次 |
| `syncing` | 正在执行一条命令 |
| `error` | 出错，`message` 为可直接展示给用户的说明 |

命令失败时，agent 发出 `error` 之后应再推送一次设备的真实状态，MideaBar 会据此撤销界面上的乐观更新。

### 设备状态 `status`

每收到一次设备状态（包括设备主动推送）就发一条：

```json
{
  "type": "status",
  "power": true,
  "mode": "cool",
  "temp": 25.5,
  "fan": "auto",
  "fanCode": 102,
  "swingUD": false,
  "swingLR": false,
  "eco": false,
  "strong": false,
  "indoor": 25.8,
  "outdoor": 31.9,
  "fault": false
}
```

- `fan` 为标准档位名；设备自动调档时可能是其他数字字符串，此时 MideaBar 用 `fanCode` 显示百分比。
- `mode` 可能出现 MideaBar 不认识的值（如 `smart_dry`），界面会原样显示。
