import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class AgentSetupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='comfyqueuebar-setup-tests-')
        cls.binary = Path(cls.temp.name) / 'setup-check'
        cache = Path(cls.temp.name) / 'module-cache'
        subprocess.run(['swiftc', '-module-cache-path', str(cache), str(PROJECT / 'Sources/ComfyQueueBar/AgentSetup.swift'),
                        str(PROJECT / 'tests/check-agent-setup.swift'), '-o', str(cls.binary)],
                       check=True, capture_output=True, text=True, env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(cache)})

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_configuration_preservation_and_failures(self):
        result = subprocess.run([str(self.binary)], check=True, capture_output=True, text=True)
        self.assertIn('Agent setup checks passed', result.stdout)

    def test_real_codex_cli_in_temporary_home(self):
        candidates = [Path('/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'),
                      Path('/Applications/Codex.app/Contents/Resources/codex'), Path('/opt/homebrew/bin/codex')]
        cli = next((path for path in candidates if path.is_file() and os.access(path, os.X_OK)), None)
        if cli is None:
            self.skipTest('Codex CLI unavailable; pure setup checks still run')
        with tempfile.TemporaryDirectory(prefix='comfyqueuebar-isolated-config-') as directory:
            home = Path(directory)
            config = home / '.codex/config.toml'
            config.parent.mkdir()
            original = 'model = "fixture"\n[mcp_servers.keep]\ncommand = "/bin/echo"\nargs = ["kept"]\n'
            config.write_text(original)
            subprocess.run([str(self.binary), '--configure', str(home), str(PROJECT / 'agent_bridge/server.py'), sys.executable, str(cli)],
                           check=True, capture_output=True, text=True, timeout=30)
            updated = config.read_text()
            self.assertIn('model = "fixture"', updated)
            self.assertIn('[mcp_servers.keep]', updated)
            self.assertIn('[mcp_servers.comfyqueuebar]', updated)
            self.assertIn('Library/Application Support/ComfyQueueBar/MCP/server.py', updated)
            backups = list(config.parent.glob('config.toml.comfyqueuebar-backup-*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), original)
            claude = json.loads((home / 'Library/Application Support/Claude/claude_desktop_config.json').read_text())
            self.assertEqual(claude['mcpServers']['comfyqueuebar']['command'], sys.executable)
            subprocess.run([str(self.binary), '--configure', str(home), str(PROJECT / 'agent_bridge/server.py'), sys.executable, str(cli)],
                           check=True, capture_output=True, text=True, timeout=30)
            self.assertEqual(config.read_text().count('[mcp_servers.comfyqueuebar]'), 1)
