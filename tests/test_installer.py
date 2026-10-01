import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def run_installer(self, *args):
        return subprocess.run(['bash', str(ROOT / 'install-comfyui-extension.sh'), *map(str, args)],
                              capture_output=True, text=True)

    def test_usage(self):
        self.assertEqual(self.run_installer().returncode, 2)

    def test_missing_custom_nodes(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertEqual(self.run_installer(temp).returncode, 1)

    def test_install_with_spaces_and_refuse_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            comfy = Path(temp) / 'ComfyUI with spaces'
            (comfy / 'custom_nodes').mkdir(parents=True)
            first = self.run_installer(str(comfy) + os.sep)
            self.assertEqual(first.returncode, 0, first.stderr)
            target = comfy / 'custom_nodes/ComfyQueueBarProgress/__init__.py'
            self.assertEqual(target.read_bytes(),
                             (ROOT / 'comfyui_extension/ComfyQueueBarProgress/__init__.py').read_bytes())
            target.write_text('local modification\n')
            second = self.run_installer(comfy)
            self.assertEqual(second.returncode, 1)
            self.assertEqual(target.read_text(), 'local modification\n')


if __name__ == '__main__':
    unittest.main()
