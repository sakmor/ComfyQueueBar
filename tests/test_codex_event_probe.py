import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('codex_event_probe', Path(__file__).resolve().parents[1] / 'agent_bridge/codex_event_probe.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CodexEventProbeTests(unittest.TestCase):
    def test_missing_host_never_claims_wakeup(self):
        with patch.dict(os.environ, {}, clear=True):
            result = module.probe(node=sys.executable, server='unused')
        self.assertEqual(result['transport'], 'unavailable')
        self.assertEqual(result['idle_wake'], 'unverified')

    def test_discovery_is_not_wakeup_verification(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'fake.py'
            fake.write_text('import sys,json\nfor line in sys.stdin:\n r=json.loads(line)\n if r.get("id")==2:\n  print(json.dumps({"id":2,"result":{"tools":[{"name":"send_message_to_thread"}]}}),flush=True)\n')
            with patch.dict(os.environ, {'CODEX_APP_TOOLS_PIPE_PATH': '/fixture'}, clear=True):
                result = module.probe(node=sys.executable, server=str(fake))
        self.assertEqual(result['transport'], 'available')
        self.assertTrue(result['send_tool_available'])
        self.assertEqual(result['idle_wake'], 'unverified')


if __name__ == '__main__':
    unittest.main()
