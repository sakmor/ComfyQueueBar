import Foundation

/// Runs only when the user presses the setup button. Never launches model inference.
enum AgentSetup {
    struct Report { var configured: [String] = []; var skillsInstalled: [String] = []; var failed: [String] = [] }
    enum SetupError: LocalizedError {
        case invalidConfiguration, missingPython, missingAdapter, invalidSkillSource, invalidSkillTarget, commandFailed, commandTimedOut
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "Existing configuration is invalid; it was left unchanged."
            case .missingPython: return "Python 3.9 or newer was not found."
            case .missingAdapter: return "The bundled MCP adapter was not found."
            case .invalidSkillSource: return "The bundled ComfyQueueBar skill was not found or is not a regular file."
            case .invalidSkillTarget: return "The existing ComfyQueueBar skill path is not a regular file; it was left unchanged."
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
    static func installSkill(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else { throw SetupError.invalidSkillSource }
        let data = try Data(contentsOf: source)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: destination.path) {
            let targetValues = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard targetValues.isRegularFile == true, targetValues.isSymbolicLink != true else { throw SetupError.invalidSkillTarget }
            if try Data(contentsOf: destination) != data { try backup(destination) }
        }
        try data.write(to: destination, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
    static func configure(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                          script: URL, python interpreter: URL?, codex cli: URL?, codexHome: URL? = nil,
                          skill: URL? = nil) throws -> Report {
        guard FileManager.default.fileExists(atPath: script.path) else { throw SetupError.missingAdapter }
        var report = Report()
        // Stable location: registration keeps working when the app bundle is moved or updated.
        let adapter = home.appendingPathComponent("Library/Application Support/ComfyQueueBar/MCP/server.py")
        if let interpreter {
            try FileManager.default.createDirectory(at: adapter.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(contentsOf: script).write(to: adapter, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: adapter.path)
            do {
                try configureClaude(home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"), python: interpreter, adapter: adapter)
                report.configured.append("Claude")
            } catch { report.failed.append("Claude MCP: " + error.localizedDescription) }
        } else {
            report.failed.append("Claude MCP: " + SetupError.missingPython.localizedDescription)
        }
        if let cli, let interpreter {
            do {
                let directory = codexHome ?? home.appendingPathComponent(".codex")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try backup(directory.appendingPathComponent("config.toml"))
                // Delegate TOML editing to Codex's own CLI; preserve unrelated tables/settings.
                var environment = ProcessInfo.processInfo.environment
                environment["CODEX_HOME"] = directory.path
                try run(cli, arguments: ["mcp", "add", "comfyqueuebar", "--", interpreter.path, adapter.path], environment: environment)
                report.configured.append("Codex")
            } catch { report.failed.append("Codex MCP: " + error.localizedDescription) }
        } else if cli == nil { report.failed.append("Codex MCP: executable not found") }
        else { report.failed.append("Codex MCP: " + SetupError.missingPython.localizedDescription) }
        if let skill {
            let installs = [
                ("Claude Code", home.appendingPathComponent(".claude/skills/comfyqueuebar/SKILL.md")),
                ("Codex", home.appendingPathComponent(".agents/skills/comfyqueuebar/SKILL.md")),
            ]
            for (client, destination) in installs {
                do {
                    try installSkill(skill, to: destination)
                    report.skillsInstalled.append(client)
                } catch { report.failed.append(client + " skill: " + error.localizedDescription) }
            }
        }
        return report
    }
}
