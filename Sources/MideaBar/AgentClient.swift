import Foundation

/// 与 Go 桥接进程 midea-ac-agent 通信：stdin 写命令、stdout 读事件，一行一个 JSON。
/// 只负责进程生命周期与收发，不理解业务（状态归 ACStore）。
final class AgentClient {
    struct Event: Decodable {
        let type: String
        // link
        let state: String?
        let message: String?
        let sn: String?
        // status
        let power: Bool?
        let mode: String?
        let temp: Double?
        let fan: String?
        let fanCode: Int?
        let swingUD: Bool?
        let swingLR: Bool?
        let eco: Bool?
        let strong: Bool?
        let indoor: Double?
        let outdoor: Double?
        let fault: Bool?
    }

    /// 在主线程回调。
    var onEvent: ((Event) -> Void)?
    /// 进程意外退出时在主线程回调。
    var onExit: (() -> Void)?

    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()

    /// App 包外的常见安装位置（从 Finder 启动的 App 拿不到 shell 的 PATH，只能列出固定目录）。
    private static let installDirs = ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]

    /// 查找 agent：App 包内 Contents/MacOS → 环境变量 MIDEA_AGENT → 常见安装位置。
    private static func agentURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "midea-ac-agent") {
            return url
        }
        if let path = ProcessInfo.processInfo.environment["MIDEA_AGENT"] {
            return URL(fileURLWithPath: path)
        }
        return installDirs
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).appendingPathComponent("midea-ac-agent") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func start() throws {
        guard let url = Self.agentURL() else {
            throw NSError(domain: "MideaBar", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到 midea-ac-agent，请放到 ~/.local/bin"])
        }
        let p = Process()
        p.executableURL = url
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            DispatchQueue.main.async { self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                self.process = nil
                self.onExit?()
            }
        }
        try p.run()
        process = p
        stdin = inPipe.fileHandleForWriting
    }

    func stop() {
        let p = process
        process = nil
        try? stdin?.close() // agent 读到 EOF 后断开蓝牙并退出
        stdin = nil
        p?.terminate()
    }

    func send(_ command: [String: Any]) {
        guard let stdin,
              var data = try? JSONSerialization.data(withJSONObject: command) else { return }
        data.append(0x0A)
        try? stdin.write(contentsOf: data)
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let event = try? JSONDecoder().decode(Event.self, from: line) {
                onEvent?(event)
            }
        }
    }
}
