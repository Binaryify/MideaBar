import AppKit
import SwiftUI

@main
struct MideaBarApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var store = ACStore()

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(store: store)
                .onAppear {
                    delegate.store = store
                    store.refresh()
                }
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏上的「空调图标 + 设定温度」。
struct MenuBarLabel: View {
    let store: ACStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "air.conditioner.horizontal")
            if store.hasStatus && store.power {
                Text(Format.temp(store.temp) + "°")
            }
        }
    }
}

/// 退出时关闭 agent（它会断开蓝牙后退出）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: ACStore?
    func applicationWillTerminate(_ notification: Notification) { store?.shutdown() }
}

enum Format {
    /// 25 → "25"，25.5 → "25.5"
    static func temp(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
