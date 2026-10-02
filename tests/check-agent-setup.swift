import Foundation

@main
struct AgentSetupCheck {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--configure" {
            let report = try AgentSetup.configure(home: URL(fileURLWithPath: CommandLine.arguments[2]),
                script: URL(fileURLWithPath: CommandLine.arguments[3]), python: URL(fileURLWithPath: CommandLine.arguments[4]),
                codex: URL(fileURLWithPath: CommandLine.arguments[5]))
            require(report.configured == ["Claude", "Codex"], "real CLI registration: \(report.failed)")
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{\"preferences\":{\"theme\":\"dark\"},\"mcpServers\":{\"existing\":{\"command\":\"fixture\",\"args\":[\"kept\"]}}}".utf8)
        try original.write(to: file)
        let script = root.appendingPathComponent("bundled-server.py")
        try Data("# fixture".utf8).write(to: script)
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let config = root.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let originalCodex = Data("model = \"fixture\"\n[mcp_servers.existing]\ncommand = \"keep\"\n".utf8)
        try originalCodex.write(to: config)
        let report = try AgentSetup.configure(home: root, script: script, python: python, codex: URL(fileURLWithPath: "/usr/bin/false"))
        require(report.configured == ["Claude"], "partial results identify successes")
        require(report.failed.count == 1 && report.failed[0].hasPrefix("Codex MCP:"), "partial failure reported")
        let codexAfter = try Data(contentsOf: config)
        require(codexAfter == originalCodex, "failed CLI leaves original config")
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        require((parsed["preferences"] as? [String: String])?["theme"] == "dark", "unrelated Claude settings preserved")
        let servers = parsed["mcpServers"] as! [String: Any]
        require((servers["existing"] as? [String: Any])?["command"] as? String == "fixture", "existing MCP preserved")
        let registration = servers["comfyqueuebar"] as! [String: Any]
        let stable = root.appendingPathComponent("Library/Application Support/ComfyQueueBar/MCP/server.py")
        require(registration["args"] as? [String] == [stable.path], "stable adapter path")
        let copied = try Data(contentsOf: stable)
        require(copied == Data("# fixture".utf8), "adapter copied byte-exactly")
        let backups = try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("comfyqueuebar-backup") }
        require(backups.count == 1, "original Claude backup created")
        let backupData = try Data(contentsOf: backups[0])
        require(backupData == original, "backup byte-exact")
        try AgentSetup.configureClaude(file, python: python, adapter: stable)
        let repeated = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        require((repeated["mcpServers"] as! [String: Any]).count == 2, "repeat setup does not duplicate server")
        for invalid in ["broken-json", "[]", "{\"mcpServers\": []}"] {
            try Data(invalid.utf8).write(to: file)
            do { try AgentSetup.configureClaude(file, python: python, adapter: stable); require(false, "invalid config rejected") } catch { }
            let after = try Data(contentsOf: file)
            require(after == Data(invalid.utf8), "invalid config not overwritten")
        }
        let skill = root.appendingPathComponent("bundled-SKILL.md")
        let skillData = Data("---\nname: comfyqueuebar\ndescription: Fixture\n---\nCheck existing jobs.\n".utf8)
        try skillData.write(to: skill)
        let skillReport = try AgentSetup.configure(home: root, script: script, python: nil, codex: nil, skill: skill)
        require(skillReport.skillsInstalled == ["Claude Code", "Codex"], "skills install independently of MCP prerequisites")
        for client in [".claude", ".agents"] {
            let target = root.appendingPathComponent("\(client)/skills/comfyqueuebar/SKILL.md")
            let installed = try Data(contentsOf: target)
            require(installed == skillData, "skill installed byte-exactly")
            try AgentSetup.installSkill(skill, to: target)
            let folder = target.deletingLastPathComponent()
            let unchanged = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            require(unchanged.count == 1, "identical skill does not create a backup")
            let previous = Data("previous custom skill".utf8)
            try previous.write(to: target)
            try AgentSetup.installSkill(skill, to: target)
            let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("comfyqueuebar-backup") }
            require(backups.count == 1, "changed skill backed up")
            let saved = try Data(contentsOf: backups[0])
            require(saved == previous, "custom skill backup byte-exact")
        }
        print("Agent setup checks passed: preservation, backups, stable paths, partial failure, invalid files, independent skill installation")
    }
}
