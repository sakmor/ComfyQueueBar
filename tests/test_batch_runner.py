"""Batch runner against a fault-injecting mock ComfyUI (no GPU, no agent inference).

Covers: upload timeout, submit outcome unknown (accepted but connection dropped),
ComfyUI restart that wipes queue/history, other users' jobs in the queue, and
node_errors. Asserts no duplicate submission and SHA256-verified outputs.
"""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import urllib.parse
import uuid

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('agent_server_batch', PROJECT / 'agent_bridge/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class MockComfy:
    def __init__(self):
        self.lock = threading.Lock()
        self.queue = []          # [number, prompt_id, prompt, extra, outputs]
        self.history = {}
        self.accepted = []       # (client_id, prompt_id) for every accepted /prompt
        self.uploads = []
        self.counter = 0
        self.offline_until = 0
        self.faults = {'upload_hang': 0, 'prompt_drop': set(), 'restart_after_submit': set(), 'reject': set()}
        self.outputs = {}
        mock = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, code, body, ctype='application/json'):
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                self.send_response(code)
                self.send_header('Content-Type', ctype)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                if self.command != 'HEAD':
                    self.wfile.write(data)

            def offline(self):
                if time.time() < mock.offline_until:
                    self.close_connection = True
                    self.connection.close()
                    return True
                return False

            def do_GET(self):
                if self.offline():
                    return
                url = urllib.parse.urlparse(self.path)
                mock.tick()
                with mock.lock:
                    if url.path == '/system_stats':
                        return self.reply(200, {'system': {'os': 'mock'}})
                    if url.path == '/queue':
                        return self.reply(200, {'queue_running': mock.queue[:1], 'queue_pending': mock.queue[1:]})
                    if url.path == '/history':
                        return self.reply(200, mock.history)
                    if url.path.startswith('/history/'):
                        pid = url.path.split('/')[-1]
                        return self.reply(200, {pid: mock.history[pid]} if pid in mock.history else {})
                    if url.path == '/view':
                        name = urllib.parse.parse_qs(url.query)['filename'][0]
                        return self.reply(200, mock.outputs[name], 'application/octet-stream')
                self.reply(404, {})

            do_HEAD = do_GET

            def do_POST(self):
                if self.offline():
                    return
                body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                if self.path == '/upload/image':
                    with mock.lock:
                        hang = mock.faults['upload_hang'] > 0
                        mock.faults['upload_hang'] -= 1
                    if hang:
                        time.sleep(2.5)  # longer than the runner's upload timeout
                        return
                    mock.uploads.append(len(body))
                    return self.reply(200, {'name': 'ref.png', 'subfolder': '', 'type': 'input'})
                if self.path == '/prompt':
                    payload = json.loads(body)
                    client = payload['client_id']
                    if client in mock.faults['reject']:
                        return self.reply(400, {'error': 'invalid prompt', 'node_errors': {'3': 'bad'}})
                    with mock.lock:
                        mock.counter += 1
                        pid = str(uuid.uuid4())
                        mock.queue.append([mock.counter, pid, payload['prompt'], {'client_id': client}, []])
                        mock.accepted.append((client, pid))
                        drop = client in mock.faults['prompt_drop']
                        mock.faults['prompt_drop'].discard(client)
                        restart = client in mock.faults['restart_after_submit']
                        mock.faults['restart_after_submit'].discard(client)
                    if restart:
                        threading.Timer(0.3, mock.restart).start()
                    if drop:
                        self.close_connection = True
                        self.connection.close()  # accepted, but the client never learns the prompt_id
                        return
                    return self.reply(200, {'prompt_id': pid, 'number': mock.counter, 'node_errors': {}})
                self.reply(404, {})

        self.httpd = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.url = 'http://127.0.0.1:%d' % self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tick(self):
        """Finish the running prompt ~0.6s after it reached the head of the queue."""
        with self.lock:
            if not self.queue:
                return
            head = self.queue[0]
            started = head[4] or [time.time()]
            head[4] = started
            if time.time() - started[0] < 0.6:
                return
            self.queue.pop(0)
            name = 'seg_%s.mp4' % head[1][:8]
            content = os.urandom(200_000)
            self.outputs[name] = content
            self.history[head[1]] = {'prompt': [head[0], head[1], head[2], head[3], []],
                                     'outputs': {'9': {'gifs': [{'filename': name, 'subfolder': '', 'type': 'output'}]}},
                                     'status': {'status_str': 'success', 'completed': True, 'messages': []}}

    def restart(self):
        with self.lock:
            self.queue.clear()
            self.history.clear()
        self.offline_until = time.time() + 3

    def close(self):
        self.httpd.shutdown()


class BatchRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cqb-batch-')
        self.root = Path(self.temp.name) / 'state'
        self.work = Path(self.temp.name) / 'work'
        self.work.mkdir()
        self.notify_log = Path(self.temp.name) / 'notify.jsonl'
        os.environ['COMFYQUEUEBAR_NO_NOTIFY'] = '1'
        os.environ['COMFYQUEUEBAR_NOTIFY_LOG'] = str(self.notify_log)
        self.mock = MockComfy()
        self.bridge = server.Bridge(self.root)
        (self.work / 'ref.png').write_bytes(b'\x89PNG' + os.urandom(1000))

    def tearDown(self):
        self.mock.close()
        # stop any detached runner by cancelling everything, then let it idle out
        for path in (self.root / 'batches').glob('*.json'):
            batch = json.loads(path.read_text())
            batch['cancel_requested'] = True
            path.write_text(json.dumps(batch))
        self.temp.cleanup()

    def graphs(self, count):
        paths = []
        for index in range(count):
            path = self.work / ('seg%d.json' % index)
            path.write_text(json.dumps({'1': {'class_type': 'EmptyLatentImage', 'inputs': {'batch_size': 5, 'seed': index}}}))
            paths.append(str(path))
        return paths

    def submit(self, graphs, **settings):
        base = {'lost_after_seconds': 2, 'poll_seconds': 0.2, 'http_timeout_seconds': 1, 'upload_timeout_seconds': 1,
                'retries': 4, 'offline_notify_after_seconds': 0.5}
        base.update(settings)
        return self.bridge.call('submit_batch', {
            'endpoint': self.mock.url, 'output_dir': str(self.work / 'out'), 'label': 'test batch',
            'uploads': [{'path': str(self.work / 'ref.png')}],
            'segments': [{'name': 'seg%d' % i, 'graph': g} for i, g in enumerate(graphs)], 'settings': base}, threading.Event())

    def wait(self, batch_id, timeout=60):
        deadline = time.time() + timeout
        while time.time() < deadline:
            status = self.bridge.call('batch_status', {'batch_id': batch_id}, threading.Event())
            if status['status'] in ('completed', 'needs_attention', 'cancelled'):
                return status
            time.sleep(0.3)
        self.fail('batch did not finish: ' + json.dumps(status, indent=1))

    def notifications(self):
        if not self.notify_log.exists():
            return []
        return [json.loads(line) for line in self.notify_log.read_text().splitlines()]

    def test_three_segments_with_upload_timeout_unknown_submit_and_restart(self):
        self.mock.faults['upload_hang'] = 1
        result = self.submit(self.graphs(3))
        batch_id = result['batch_id']
        clients = [s['client_id'] for s in result['segments']]
        self.mock.faults['prompt_drop'].add(clients[1])
        self.mock.faults['restart_after_submit'].add(clients[2])
        status = self.wait(batch_id)
        self.assertEqual(status['status'], 'completed', json.dumps(status, indent=1))

        per_client = {c: [p for cc, p in self.mock.accepted if cc == c] for c in clients}
        self.assertEqual(len(per_client[clients[0]]), 1, 'upload timeout must not duplicate')
        self.assertEqual(len(per_client[clients[1]]), 1, 'unknown submit must be adopted, not resubmitted')
        # Restart wiped the first prompt; exactly one deliberate resubmission, never more.
        self.assertEqual(len(per_client[clients[2]]), 2, 'lost prompt resubmitted exactly once')
        self.assertEqual(len(self.mock.uploads), 1, 'shared reference uploaded once')

        kinds = [e['kind'] for e in status['recent_events']] + [e['kind'] for e in json.loads((self.root / 'batches' / (batch_id + '.json')).read_text())['events']]
        self.assertIn('adopted', kinds)
        self.assertIn('lost', kinds)
        for segment in status['segments']:
            self.assertEqual(segment['state'], 'completed')
            self.assertEqual(len(segment['outputs']), 1)
            output = segment['outputs'][0]
            data = Path(output['path']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), output['sha256'])
            self.assertEqual(data, self.mock.outputs[output['filename']])
            self.assertTrue(output['size_verified_against_server'])
        titles = ' '.join(n['message'] for n in self.notifications())
        self.assertIn('Batch finished', titles)
        self.assertIn('caffeinate', titles)  # restart triggered the offline/sleep hint

    def test_waits_behind_other_users_and_flags_node_errors(self):
        with self.mock.lock:
            self.mock.queue.append([0, 'foreign', {}, {'client_id': 'someone-else'}, [time.time() + 1.5]])
        graphs = self.graphs(2)
        result = self.submit(graphs)
        clients = [s['client_id'] for s in result['segments']]
        self.mock.faults['reject'].add(clients[1])
        time.sleep(1.0)
        self.assertEqual(self.mock.accepted, [], 'must not jump ahead of a foreign job')
        status = self.wait(result['batch_id'])
        self.assertEqual(status['status'], 'needs_attention')
        self.assertEqual(status['segments'][0]['state'], 'completed')
        self.assertEqual(status['segments'][1]['state'], 'failed')
        self.assertIn('node_errors', json.dumps(status['segments'][1]['error']))
        self.assertTrue(any('needs attention' in n['message'] for n in self.notifications()))

    def test_resubmitting_same_batch_id_is_idempotent_and_runner_resumes(self):
        graphs = self.graphs(1)
        batch_id = str(uuid.uuid4())
        self.bridge.call('submit_batch', {
            'batch_id': batch_id, 'endpoint': self.mock.url, 'output_dir': str(self.work / 'out'),
            'segments': [{'graph': graphs[0]}], 'settings': {'poll_seconds': 0.2}}, threading.Event())
        again = self.bridge.call('submit_batch', {'batch_id': batch_id, 'endpoint': self.mock.url, 'output_dir': str(self.work / 'out'),
                                                  'segments': [{'graph': graphs[0]}]}, threading.Event())
        self.assertIn('already exists', again['note'])
        self.assertEqual(self.wait(batch_id)['status'], 'completed')
        self.assertEqual(len(self.mock.accepted), 1)

    def test_runner_killed_mid_batch_resumes_without_duplicates(self):
        import signal
        result = self.submit(self.graphs(3))
        lock = self.root / 'batches' / '.runner.lock'
        deadline = time.time() + 20
        while time.time() < deadline and not self.mock.accepted:
            time.sleep(0.05)
        pid = int(lock.read_text())
        os.kill(pid, signal.SIGKILL)  # simulate crash right after a submit
        time.sleep(0.5)
        status = self.wait(result['batch_id'])  # batch_status restarts the runner
        self.assertEqual(status['status'], 'completed')
        clients = [s['client_id'] for s in result['segments']]
        self.assertEqual(sorted(c for c, _ in self.mock.accepted), sorted(clients))

    def test_rejects_ui_workflow_graphs(self):
        path = self.work / 'ui.json'
        path.write_text(json.dumps({'nodes': [], 'links': []}))
        with self.assertRaisesRegex(ValueError, 'API format'):
            self.bridge.call('submit_batch', {'endpoint': self.mock.url, 'output_dir': str(self.work), 'segments': [{'graph': str(path)}]}, threading.Event())


if __name__ == '__main__':
    unittest.main()
