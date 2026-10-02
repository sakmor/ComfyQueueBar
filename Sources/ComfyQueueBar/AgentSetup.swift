import Foundation

/// Runs only when the user presses the setup button. Never launches model inference.
enum AgentSetup {
    struct Report { var configured: [String] = []; var failed: [String] = [] }
    enum SetupError: LocalizedError {
        case invalidConfiguration, missingPython, missingAdapter, commandFailed, commandTimedOut
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "Existing configuration is invalid; it was left unchanged."
            case .missingPython: return "Python 3.9 or newer was not found."
            case .missingAdapter: return "The bundled MCP adapter was not found."
            case .commandFailed: return "The configuration command failed. The original backup was retained."
            case .commandTimedOut: return "The configuration command timed out. Check the saved configuration before retrying."
            }
        }
    }
    static func executable(_ paths: [String]) -> URL? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    static func python() -> URL? {
        let paths = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/python3" }
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if (try? run(url, arguments: ["-c", "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)"])) != nil { return url }
        }
        return nil
    }
    static func codex() -> URL? {
        executable([
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" })
    }
    static func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); throw SetupError.commandTimedOut }
        guard process.terminationStatus == 0 else { throw SetupError.commandFailed }
    }
    @discardableResult
    static func backup(_ file: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let target = file.appendingPathExtension("comfyqueuebar-backup-" + UUID().uuidString)
        try FileManager.default.copyItem(at: file, to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target
    }
    static func configureClaude(_ file: URL, python: URL, adapter: URL) throws {
        var configuration: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            guard let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else { throw SetupError.invalidConfiguration }
            configuration = parsed
        }
        if let servers = configuration["mcpServers"], !(servers is [String: Any]) { throw SetupError.invalidConfiguration }
        var servers = configuration["mcpServers"] as? [String: Any] ?? [:]
        servers["comfyqueuebar"] = ["command": python.path, "args": [adapter.path]]
        configuration["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try backup(file)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func configure(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                          script: URL, python interpreter: URL, codex cli: URL?, codexHome: URL? = nil) throws -> Report {
        guard FileManager.default.fileExists(atPath: script.path) else { throw SetupError.missingAdapter }
        // Stable location: registration keeps working when the app bundle is moved or updated.
        let adapter = home.appendingPathComponent("Library/Application Support/ComfyQueueBar/MCP/server.py")
        try FileManager.default.createDirectory(at: adapter.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(contentsOf: script).write(to: adapter, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: adapter.path)
        var report = Report()
        do {
            try configureClaude(home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"), python: interpreter, adapter: adapter)
            report.configured.append("Claude")
        } catch { report.failed.append("Claude: " + error.localizedDescription) }
        if let cli {
            do {
                let directory = codexHome ?? home.appendingPathComponent(".codex")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try backup(directory.appendingPathComponent("config.toml"))
                // Delegate TOML editing to Codex's own CLI; preserve unrelated tables/settings.
                var environment = ProcessInfo.processInfo.environment
                environment["CODEX_HOME"] = directory.path
                try run(cli, arguments: ["mcp", "add", "comfyqueuebar", "--", interpreter.path, adapter.path], environment: environment)
                report.configured.append("Codex")
            } catch { report.failed.append("Codex: " + error.localizedDescription) }
        } else { report.failed.append("Codex: executable not found") }
        return report
    }
}
