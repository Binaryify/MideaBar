import AppKit
import SwiftUI

enum Theme {
    static let background = Color(white: 0.07)
    static let tile = Color(white: 0.115)
    static let tileStroke = Color.white.opacity(0.06)
    static let secondary = Color(white: 0.52)
    static let accent = Color(red: 0.80, green: 0.73, blue: 0.62)
}

/// 菜单栏弹出的控制面板。
struct ControlPanel: View {
    let store: ACStore

    private var enabled: Bool { store.hasStatus && store.link != .connecting }
    private var controlsEnabled: Bool { enabled && store.power }

    var body: some View {
        VStack(spacing: 14) {
            header
            ACUnitView(isOn: store.power && store.hasStatus, tint: store.mode?.airTint ?? .white)
            tempRow
            TempSlider(value: store.temp, onChange: store.setTemp, onStep: store.stepTemp)
                .disabled(!controlsEnabled)
            tiles
                .disabled(!controlsEnabled)
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack {
            Image(systemName: "thermometer.medium")
                .foregroundStyle(Theme.secondary)
            Text("室内").foregroundStyle(Theme.secondary)
            Text(store.indoor.map { Format.temp($0) + "°C" } ?? "--")
                .fontWeight(.semibold)
            if let out = store.outdoor {
                Text("室外 \(Format.temp(out))°C")
                    .foregroundStyle(Theme.secondary)
                    .padding(.leading, 6)
            }
            Spacer()
            PowerButton(isOn: store.power, action: store.togglePower)
                .disabled(!enabled)
        }
        .font(.system(size: 13))
    }

    // MARK: - 温度 + 节能

    private var tempRow: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(store.hasStatus ? Format.temp(store.temp) : "--")
                    .font(.system(size: 46, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: store.temp))
                    .animation(.snappy, value: store.temp)
                Text("°C")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .opacity(store.power ? 1 : 0.45)
            Spacer()
            Button(action: store.toggleEco) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf")
                        .foregroundStyle(store.eco ? Theme.accent : Theme.secondary)
                    Text("节能模式").font(.system(size: 13, weight: .medium))
                    PillSwitch(isOn: store.eco)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.tileStroke))
            }
            .buttonStyle(.plain)
            .disabled(!controlsEnabled)
        }
    }

    // MARK: - 功能卡片

    private var tiles: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ACMode.allCases) { m in
                    Button { store.setMode(m) } label: { Label(m.label, systemImage: m.symbol) }
                }
            } label: {
                OptionTile(symbol: store.mode?.symbol ?? "questionmark",
                           title: "模式", value: store.mode?.label ?? store.modeName)
            }
            Menu {
                ForEach(FanSpeed.allCases) { f in
                    Button(f.label) { store.setFan(f) }
                }
            } label: {
                OptionTile(symbol: "fan", title: "风速", value: store.fanLabel)
            }
            Button(action: store.toggleStrong) {
                OptionTile(symbol: "bolt", title: "强劲", value: store.strong ? "开" : "关",
                           trailing: .dot(store.strong))
            }
            Menu {
                ForEach(Airflow.allCases) { a in
                    Button(a.label) { store.setAirflow(a) }
                }
            } label: {
                OptionTile(symbol: "wind", title: "扫风", value: store.airflow.label)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 6) {
            Group {
                switch store.link {
                case .connected:
                    Image(systemName: store.fault ? "exclamationmark.triangle" : "checkmark.shield")
                case .failed:
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                default:
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 14)
            Text(store.fault && store.link == .connected ? "设备报告故障" : store.link.label)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Menu {
                if !store.sn.isEmpty { Text("设备 SN：\(store.sn)") }
                Button("重新连接", action: store.reconnect)
                Toggle("按键提示音", isOn: Binding(get: { store.beep }, set: { store.beep = $0 }))
                Divider()
                Button("退出 MideaBar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondary)
        .padding(.top, 2)
    }
}

// MARK: - 组件

struct PowerButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Theme.accent : Theme.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.tile))
                .overlay(Circle().stroke(isOn ? Theme.accent.opacity(0.6) : Theme.tileStroke, lineWidth: 1.5))
                .shadow(color: isOn ? Theme.accent.opacity(0.35) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isOn)
    }
}

struct PillSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent.opacity(0.85) : Color(white: 0.25))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).padding(2.5)
            }
            .animation(.snappy(duration: 0.2), value: isOn)
    }
}

struct OptionTile: View {
    enum Trailing { case chevron, dot(Bool) }

    let symbol: String
    let title: String
    let value: String
    var trailing: Trailing = .chevron

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: symbol).font(.system(size: 15))
                Spacer()
                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                case .dot(let on):
                    Circle().fill(on ? Theme.accent : Color(white: 0.3)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 18)
            .foregroundStyle(Theme.secondary)
            Spacer(minLength: 10)
            Text(title).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.tileStroke))
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 「−  [====|----]  +」温度滑块，下方标出范围。
struct TempSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    let onStep: (Double) -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                stepButton("minus", delta: -TempRange.step)
                track
                stepButton("plus", delta: TempRange.step)
            }
            HStack {
                Text("\(Int(TempRange.min))°")
                Spacer()
                Text("\(Int(TempRange.max))°")
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 42)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        Button { onStep(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.tile))
                .overlay(Circle().stroke(Theme.tileStroke))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
    }

    private var track: some View {
        GeometryReader { geo in
            let knobW: CGFloat = 22
            let frac = (value - TempRange.min) / (TempRange.max - TempRange.min)
            let x = CGFloat(frac) * (geo.size.width - knobW)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.13))
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.16), Theme.accent.opacity(0.75)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: x + knobW)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                    .frame(width: knobW, height: geo.size.height - 4)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: x)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = (g.location.x - knobW / 2) / (geo.size.width - knobW)
                onChange(TempRange.min + Double(min(max(f, 0), 1)) * (TempRange.max - TempRange.min))
            })
            .animation(.snappy(duration: 0.15), value: value)
        }
        .frame(height: 34)
    }
}
