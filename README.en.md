<p align="center">
  <img src="website/assets/icon.png" width="128" alt="MideaBar icon">
</p>

<h1 align="center">MideaBar</h1>

<p align="center">Control Midea / Hualing air conditioners from the macOS menu bar over Bluetooth — no phone app, no cloud.</p>

<p align="center">
  <a href="https://github.com/Binaryify/MideaBar/actions/workflows/ci.yml"><img src="https://github.com/Binaryify/MideaBar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Binaryify/MideaBar/releases"><img src="https://img.shields.io/github/v/release/Binaryify/MideaBar" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black.svg" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.10-orange.svg" alt="Swift 5.10">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT"></a>
</p>

<p align="center"><a href="README.md">简体中文</a> · English</p>

<p align="center"><a href="https://binaryify.github.io/MideaBar/?lang=en">Website</a> · <a href="website/assets/demo.mp4">Demo video</a> · <a href="docs/agent-protocol.en.md">Agent protocol</a></p>

<p align="center">
  <a href="website/assets/demo.mp4"><img src="website/assets/poster.jpg" width="480" alt="MideaBar demo: open the menu bar panel, power on, cool down to 24℃, turn on Eco"></a>
</p>

> ⚠️ **Disclaimer**
>
> This is a personal open-source project. It is not affiliated with or authorized by Midea Group or any of its sub-brands; "Midea", "Hualing" and related names and trademarks belong to their respective owners.
> The Bluetooth protocol comes from public research into device behavior and is provided for learning and for use with your own devices only. You use this project at your own risk.

## Features

- Shows the set temperature in the menu bar; click it to open the control panel
- Power, temperature (16–30℃ in 0.5° steps), mode, fan speed, swing, Eco and Turbo
- Shows indoor / outdoor temperature; the AC illustration blows air while it's on
- Changes apply instantly (optimistic updates) and roll back to the device's real state on failure
- Restarts the background agent and reconnects automatically if it dies
- UI in Simplified Chinese / English — follows the system language by default, or switch manually

## How it works

```
MideaBar (SwiftUI menu bar UI)
   │  stdin / stdout, one JSON message per line
   ▼
midea-ac-agent (background program holding the BLE connection)
   │  BLE
   ▼
Air conditioner
```

MideaBar only draws the UI and contains no Bluetooth protocol code. The Bluetooth side is handled by the background program `midea-ac-agent`; the protocol between the two is described in [docs/agent-protocol.en.md](docs/agent-protocol.en.md), and any program implementing it can be used instead.

Reference implementation: `cmd/midea-ac-agent` in [midea-ble-go](https://github.com/midea-ble/midea-ble-go).

## Installation

1. Download `MideaBar-*.zip` from [Releases](https://github.com/Binaryify/MideaBar/releases), unzip it and drag `MideaBar.app` into Applications. Requires macOS 14+; universal binary for Apple silicon and Intel.
2. Get the background program `midea-ac-agent` and put it at `~/.local/bin/midea-ac-agent` (see the [lookup order](docs/agent-protocol.en.md#process-conventions)).
3. The app is not notarized by Apple. Before opening it for the first time, run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/MideaBar.app
   ```

4. Open MideaBar and allow Bluetooth access when prompted.

## Building from source

Requires macOS 14+ and the Xcode Command Line Tools.

```bash
git clone https://github.com/binaryify/MideaBar.git
cd MideaBar
make app                                   # without the agent; looked up outside the app at runtime
make app AGENT=/path/to/midea-ac-agent     # bundle the agent into the app
```

The result is `build/MideaBar.app`. To build and launch in one step:

```bash
make run AGENT=/path/to/midea-ac-agent
```

`make dist` additionally packs a release zip. Pushing a `v*` tag (e.g. `v0.1.0`) makes GitHub Actions build and publish it to Releases.

macOS asks for Bluetooth permission on first launch — allow it. **Launch the app from Finder or with `open`**: if you run the executable inside the app directly from a terminal, the Bluetooth permission is attributed to the terminal instead.

### Development

Without packaging, point to the agent with an environment variable:

```bash
swift build
MIDEA_AGENT=/path/to/midea-ac-agent .build/debug/MideaBar
```

### UI language

The UI follows the system language by default and currently supports Simplified Chinese and English. You can also switch manually in the settings menu at the bottom-right of the panel → "Language" (the app restarts automatically). Source code uses the Chinese text directly (`Text("室内")`, `String(localized: "制冷")`), and that Chinese text is the translation key; English translations live in [Resources/en.lproj/Localizable.strings](Resources/en.lproj/Localizable.strings). To add a language: add `Resources/<lang>.lproj/`, register it under `CFBundleLocalizations` in `Info.plist`, and add a case to `AppLanguage`.

Documents also come in both languages (`README.md` / `README.en.md`, `docs/agent-protocol.md` / `docs/agent-protocol.en.md`) — please keep both in sync. The website's English copy is in the `EN` object in the script at the end of `website/index.html`.

### Changing the icon

The icon is drawn in SwiftUI by [Icon/make-icon.swift](Icon/make-icon.swift). Regenerate it after editing:

```bash
make icon
```

## Project structure

```
MideaBar/
├── Sources/MideaBar/
│   ├── MideaBarApp.swift   # Entry point: menu bar icon and temperature
│   ├── ControlPanel.swift  # Control panel and its controls
│   ├── ACUnitView.swift    # AC illustration and airflow animation
│   ├── ACStore.swift       # State: events → UI state, user actions → commands
│   ├── AgentClient.swift   # Launching, talking to and restarting the agent
│   ├── AppLanguage.swift   # UI language: follow system / manual switch
│   └── Models.swift        # Mode / fan speed / swing enums
├── Icon/make-icon.swift    # Icon source
├── Resources/              # Info.plist, AppIcon.icns, *.lproj (UI translations)
├── docs/agent-protocol.md  # App ↔ agent protocol (English: .en.md)
└── website/                # Website (GitHub Pages, Chinese / English), demo video and icons
```

## License

[MIT](LICENSE)
