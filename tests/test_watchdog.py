"""Watchdog: unexpected idle queue, missed script heartbeats, and queue_drained events (mock ComfyUI)."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tests'))
from test_batch_runner import MockComfy  # noqa: E402

spec = importlib.util.spec_from_file_location('agent_server_watch', PROJECT / 'agent_bridge/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)
spec = importlib.util.spec_from_file_location('batch_runner_watch', PROJECT / 'agent_bridge/batch_runner.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cqb-watch-')
        self.root = Path(self.temp.name)
        self.notify_log = self.root / 'notify.jsonl'
        os.environ['COMFYQUEUEBAR_NO_NOTIFY'] = '1'
        os.environ['COMFYQUEUEBAR_NOTIFY_LOG'] = str(self.notify_log)
        self.mock = MockComfy()
        self.started = []
        server.ensure_runner = lambda root: self.started.append(root)  # the test drives the watchdog directly
        self.bridge = server.Bridge(self.root)
        self.watchdog = runner.Watchdog(self.root, poll_seconds=0)
        # A live app heartbeat and one subscription on the mock endpoint, as the Swift app would write them.
        self.sid = str(uuid.uuid4())
        self.write_snapshot()
        (self.root / 'subscriptions.json').write_text(json.dumps({self.sid: {
            'subscription_id': self.sid, 'endpoint': self.mock.url, 'prompt_ids': ['x'], 'label': 'test', 'created_at': time.time() - 1,
            'cancelled': False, 'results': {}, 'events': [], 'acknowledged': []}}))
        self.keep = threading.Event()
        threading.Thread(target=self.refresh_snapshot, daemon=True).start()

    def write_snapshot(self):
        runner.atomic_json(self.root / 'snapshot.json', {'enabled': True, 'heartbeat_at': time.time(), 'endpoint': self.mock.url})

    def refresh_snapshot(self):
        while not self.keep.wait(1):
            self.write_snapshot()

    def tearDown(self):
        self.keep.set()
        self.mock.close()
        self.temp.cleanup()

    def call(self, name, args):
        return self.bridge.call(name, args, threading.Event())

    def events(self, kind):
        return [e for e in self.call('get_results', {'subscription_id': self.sid})['subscription']['events'] if e['kind'] == kind]

    def notifications(self):
        return [json.loads(l) for l in self.notify_log.read_text().splitlines()] if self.notify_log.exists() else []

    def test_idle_queue_while_work_is_expected(self):
        result = self.call('expect_work', {'endpoint': self.mock.url, 'label': 'tortoise batch', 'until_seconds': 600, 'idle_after_seconds': 2})
        self.assertEqual(self.started, [self.root])
        self.assertEqual(result['expectation']['idle_after_seconds'], 2)
        self.watchdog.tick(force=True)
        self.assertEqual(self.events('queue_idle_unexpected'), [], 'not idle long enough yet')
        time.sleep(2.2)
        self.watchdog.tick(force=True)
        self.watchdog.tick(force=True)
        events = self.events('queue_idle_unexpected')
        self.assertEqual(len(events), 1, 'one alert per idle period')
        self.assertEqual(events[0]['label'], 'tortoise batch')
        self.assertGreaterEqual(events[0]['data']['idle_seconds'], 2)
        self.assertTrue(any('GPU idle' in n['title'] for n in self.notifications()))
        # wait_for_events returns it immediately; acknowledging stops replay.
        waited = self.call('wait_for_events', {'subscription_id': self.sid, 'timeout_seconds': 5})
        self.assertEqual(waited['waiting_stopped'], 'event')
        self.call('acknowledge_events', {'subscription_id': self.sid, 'event_ids': [events[0]['id']]})
        self.assertEqual(self.events('queue_idle_unexpected'), [])
        # Work arriving resets the idle period; clearing the expectation stops alerts.
        self.call('expect_work', {'endpoint': self.mock.url, 'label': 'tortoise batch', 'until_seconds': 0})
        time.sleep(2.2)
        self.watchdog.tick(force=True)
        self.assertEqual(len(self.notifications()), 1)

    def test_busy_queue_does_not_alert(self):
        self.call('expect_work', {'endpoint': self.mock.url, 'label': 'busy', 'until_seconds': 600, 'idle_after_seconds': 1})
        self.mock.run_seconds = 5
        with self.mock.lock:
            self.mock.queue.append([1, 'p1', {}, {'client_id': 'agent'}, []])
        for _ in range(3):
            time.sleep(0.6)
            self.watchdog.tick(force=True)
        self.assertEqual(self.events('queue_idle_unexpected'), [])

    def test_missed_heartbeat_reports_last_message(self):
        self.call('heartbeat', {'label': 'h3 batch.py', 'ttl_seconds': 1, 'message': 'waiting for C05 output', 'endpoint': self.mock.url})
        self.watchdog.tick(force=True)
        self.assertEqual(self.events('heartbeat_missed'), [])
        # A script can also beat from the shell without an MCP session.
        subprocess.run([sys.executable, str(PROJECT / 'agent_bridge/server.py'), '--state-dir', str(self.root), '--heartbeat', 'h3 batch.py',
                        '--ttl', '1', '--message', 'retrying KeyError for C06', '--endpoint', self.mock.url],
                       check=True, capture_output=True, env={**os.environ, 'COMFYQUEUEBAR_NO_RUNNER': '1'})
        time.sleep(1.3)
        self.watchdog.tick(force=True)
        self.watchdog.tick(force=True)
        events = self.events('heartbeat_missed')
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['data']['last_message'], 'retrying KeyError for C06')
        self.assertTrue(any('stuck or crashed' in n['message'] for n in self.notifications()))
        self.call('heartbeat', {'label': 'h3 batch.py', 'ttl_seconds': 0})
        time.sleep(1.2)
        self.watchdog.tick(force=True)
        self.assertEqual(len(self.events('heartbeat_missed')), 1)

    def test_queue_drained_after_last_success(self):
        self.mock.run_seconds = 0.5
        with self.mock.lock:
            self.mock.queue.append([1, 'final-prompt', {}, {'client_id': 'agent'}, []])
        self.watchdog.tick(force=True)  # observes busy
        self.assertEqual(self.events('queue_drained'), [])
        deadline = time.time() + 10
        while time.time() < deadline and not self.events('queue_drained'):
            time.sleep(0.3)
            self.watchdog.tick(force=True)
        events = self.events('queue_drained')
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['data']['last_prompt_id'], 'final-prompt')
        self.assertEqual(events[0]['data']['outputs'][0]['filename'], 'seg_final-pr.mp4')
        waited = self.call('wait_for_events', {'subscription_id': self.sid, 'timeout_seconds': 2})
        self.assertIn('queue_drained', [e['kind'] for e in waited['events']])
        self.watchdog.tick(force=True)
        self.assertEqual(len(self.events('queue_drained')), 1, 'no repeat while the queue stays empty')


if __name__ == '__main__':
    unittest.main()
