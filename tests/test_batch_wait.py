import importlib.util
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path

spec = importlib.util.spec_from_file_location('batch_wait_server', Path(__file__).resolve().parents[1] / 'agent_bridge/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class BatchWaitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.batch_id = str(uuid.uuid4())
        self.path = self.root / 'batches' / (self.batch_id + '.json')
        self.batch = {'batch_id': self.batch_id, 'status': 'queued', 'segments': [{'state': 'pending'}], 'events': []}
        server.atomic_json(self.path, self.batch)
        self.bridge = server.Bridge(self.root)

    def test_wait_covers_pending_running_and_download_before_completion(self):
        result = {}
        worker = threading.Thread(target=lambda: result.update(self.bridge.call('wait_for_batch', {'batch_id': self.batch_id, 'timeout_seconds': 5}, threading.Event())))
        worker.start()
        for status in ('waiting_for_queue', 'running', 'downloading'):
            self.batch['status'] = status
            server.atomic_json(self.path, self.batch)
            time.sleep(0.15)
            self.assertTrue(worker.is_alive())
        self.batch['status'] = 'completed'
        self.batch['segments'][0]['state'] = 'completed'
        server.atomic_json(self.path, self.batch)
        worker.join(2)
        self.assertFalse(worker.is_alive())
        self.assertEqual(result['waiting_stopped'], 'completed')

    def test_attention_timeout_and_cancel_are_not_success(self):
        self.batch['status'] = 'needs_attention'
        server.atomic_json(self.path, self.batch)
        self.assertEqual(self.bridge.call('wait_for_batch', {'batch_id': self.batch_id}, threading.Event())['waiting_stopped'], 'needs_attention')
        self.batch['status'] = 'running'
        server.atomic_json(self.path, self.batch)
        self.assertEqual(self.bridge.call('wait_for_batch', {'batch_id': self.batch_id, 'timeout_seconds': 1}, threading.Event())['waiting_stopped'], 'timeout')
        cancelled = threading.Event()
        cancelled.set()
        with self.assertRaisesRegex(ValueError, 'batch remains active'):
            self.bridge.call('wait_for_batch', {'batch_id': self.batch_id}, cancelled)


if __name__ == '__main__':
    unittest.main()
