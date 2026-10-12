import AppKit

/// 界面语言：跟随系统，或手动指定。
/// 手动指定写入本 App 的 AppleLanguages 偏好，系统据此选 .lproj；生效需重启 App。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en
    var id: Self { self }

    var label: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .zhHans: "简体中文"
        case .en: "English"
        }
    }

    /// 只看本 App 自己的偏好域；全局域里的 AppleLanguages 是系统语言列表，不算手动指定。
    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        let code = (domain?["AppleLanguages"] as? [String])?.first
        return code.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// 保存选择并重启 App。
    static func apply(_ language: AppLanguage) {
        guard language != current else { return }
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        relaunch()
    }

    /// 等本进程退出后再 open 一次，否则 open 只会激活仍在运行的旧实例。
    private static func relaunch() {
        let path = Bundle.main.bundlePath
        if path.hasSuffix(".app") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", path]
            try? p.run()
        }
        NSApp.terminate(nil)
    }
}
