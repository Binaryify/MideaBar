# Agent Protocol

[简体中文](agent-protocol.md) · English

MideaBar does not implement the Bluetooth protocol itself. It launches a background program, `midea-ac-agent`, which holds the long-lived Bluetooth connection to the air conditioner. The two exchange **JSON over stdin / stdout, one message per line** (JSON Lines).

Any program that implements this protocol can serve as MideaBar's backend. See `cmd/midea-ac-agent` in [midea-ble-go](https://github.com/midea-ble/midea-ble-go) for a reference implementation.

## Process conventions

- On startup MideaBar looks for the agent in this order and uses the first one found:
  1. `Contents/MacOS/midea-ac-agent` inside the app bundle
  2. The path in the `MIDEA_AGENT` environment variable (for development)
  3. `~/.local/bin/midea-ac-agent`, `/opt/homebrew/bin/midea-ac-agent`, `/usr/local/bin/midea-ac-agent`
- The agent's **stdout must contain only protocol messages**. Logs, progress output and the like go to stderr, which MideaBar ignores.
- When MideaBar quits it closes the agent's stdin. On EOF the agent should disconnect Bluetooth and exit.
- If the agent exits unexpectedly, MideaBar restarts it after 2 seconds and reconnects.
- The agent should execute commands serially: start the next command only after the previous one has completed (or failed).

## Commands (MideaBar → agent)

| Command | Meaning |
|---|---|
| `{"op":"connect","sn":""}` | Connect to a device. With an empty `sn`, the agent picks a device itself (reference implementation: the first entry in its known-device list, or if there is none, scan and connect to the one with the strongest signal). |
| `{"op":"refresh"}` | Query the status once. |
| `{"op":"power","on":true}` | Power on / off. |
| `{"op":"mode","value":"cool"}` | Mode: `auto` / `cool` / `dry` / `heat` / `fan`. |
| `{"op":"temp","temp":25.5}` | Set temperature, 16–30℃ in 0.5 steps. |
| `{"op":"fan","value":"auto"}` | Fan speed: `auto` / `low` / `mid` / `high` / `full`. |
| `{"op":"swing","ud":true,"lr":false}` | Swing: vertical / horizontal. |
| `{"op":"eco","on":true}` | Eco mode. |
| `{"op":"strong","on":true}` | Turbo mode. |
| `{"op":"beep","on":false}` | Whether the AC beeps on commands (a local preference; produces no status event). |

## Events (agent → MideaBar)

### Connection state `link`

```json
{"type":"link","state":"connected","sn":"22040055AC2615"}
{"type":"link","state":"error","message":"handshake failed: …","sn":"22040055AC2615"}
```

| `state` | Meaning |
|---|---|
| `connecting` | Scanning or handshaking |
| `connected` | Connected; also sent after every successful control command |
| `syncing` | Executing a command |
| `error` | Something failed; `message` is a description that can be shown to the user as-is |

When a command fails, the agent should push the device's real status again after the `error`; MideaBar uses it to undo its optimistic UI update.

`message` is displayed verbatim and is not translated by MideaBar, so the agent decides its language.

### Device status `status`

Sent every time a device status is received (including pushes initiated by the device):

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

- `fan` is a standard speed name; when the device adjusts the speed automatically it may be some other numeric string, in which case MideaBar shows `fanCode` as a percentage.
- `mode` may carry values MideaBar doesn't recognize (such as `smart_dry`); the UI shows them as-is.
