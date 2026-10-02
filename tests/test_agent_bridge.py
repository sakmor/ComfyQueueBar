"""Exercise real Swift app IPC and real MCP stdio without a GPU or agent inference."""
import importlib.util
import io
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('agent_server', PROJECT / 'agent_bridge/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class AgentBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build_dir = tempfile.TemporaryDirectory(prefix='comfyqueuebar-agent-tests-')
        cls.binary = Path(cls.build_dir.name) / 'fixture'
        cache = Path(cls.build_dir.name) / 'module-cache'
        env = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(cache)}
        subprocess.run(['swiftc', '-module-cache-path', str(cache), str(PROJECT / 'Sources/ComfyQueueBar/AgentBridge.swift'),
                        str(PROJECT / 'tests/check-agent-bridge.swift'), '-o', str(cls.binary)], check=True, env=env, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.build_dir.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='comfyqueuebar-agent-state-')
        self.root = Path(self.temp.name)
        self.app = subprocess.Popen([str(self.binary), '--serve', str(self.root)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.bridge = server.Bridge(self.root)
        self.wait_until(lambda: self.bridge.status()['app_available'])

    def tearDown(self):
        self.app.terminate()
        self.app.communicate(timeout=5)
        self.temp.cleanup()

    def wait_until(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.02)
        self.fail('Timed out waiting for fixture')

    def subscribe(self, ids=None):
        return self.bridge.call('subscribe_jobs', {'endpoint': 'http://127.0.0.1:8188', 'prompt_ids': ids or ['job-a', 'job-b']}, threading.Event())['subscription_id']

    def fixture(self, **value):
        server.atomic_json(self.root / 'fixture.json', value)

    def test_swift_lifecycle(self):
        result = subprocess.run([str(self.binary)], capture_output=True, text=True, check=True)
        self.assertIn('lifecycle checks passed', result.stdout)

    def test_delegation_wait_failure_completion_ack_restart(self):
        sid = self.subscribe()
        self.assertFalse(self.bridge.results(sid)['delivery']['idle_conversation_wakeup'])
        self.assertIn('Do not repeatedly', self.bridge.status()['guidance'])
        result = {}
        def wait():
            result.update(self.bridge.call('wait_for_events', {'subscription_id': sid, 'timeout_seconds': 5}, threading.Event()))
        waiter = threading.Thread(target=wait)
        waiter.start()
        time.sleep(0.1)
        self.assertTrue(waiter.is_alive())
        self.fixture(results={'job-a': {'status': 'failed', 'outputs': [], 'error': 'GPU exhausted'}})
        waiter.join(5)
        self.assertFalse(waiter.is_alive())
        self.assertEqual([x['kind'] for x in result['events']], ['job_failed'])
        self.bridge.call('acknowledge_events', {'subscription_id': sid, 'event_ids': [x['id'] for x in result['events']]}, threading.Event())
        self.fixture(results={'job-b': {'status': 'completed', 'outputs': [{'filename': 'clip.mp4', 'url': 'http://example/view'}]}})
        self.wait_until(lambda: any(x['kind'] == 'batch_finished' for x in self.bridge.subscription(sid)['events']))
        restarted = server.Bridge(self.root)
        resumed = restarted.call('resume_subscription', {'subscription_id': sid}, threading.Event())
        self.assertEqual(resumed['subscription']['results']['job-a']['error'], 'GPU exhausted')
        self.assertEqual(resumed['subscription']['results']['job-b']['outputs'][0]['filename'], 'clip.mp4')
        self.assertIn(sid, restarted.attached)
        events = restarted.call('wait_for_events', {'subscription_id': sid}, threading.Event())['events']
        self.assertEqual([x['kind'] for x in events], ['batch_finished'])

    def test_server_change_unknown_and_disconnect_events(self):
        sid = self.subscribe(['missing'])
        self.fixture(endpoint='http://other:8188', connected=True)
        self.wait_until(lambda: self.bridge.subscription(sid)['monitoring_status'] == 'paused_server_changed')
        subscription = self.bridge.subscription(sid)
        self.assertFalse(any(x['kind'] == 'batch_finished' for x in subscription['events']))
        self.assertEqual(subscription['events'][-1]['monitoring_status'], 'paused_server_changed')
        self.fixture(connected=False)
        self.wait_until(lambda: self.bridge.subscription(sid)['monitoring_status'] == 'disconnected')
        events = self.bridge.subscription(sid)['events']
        time.sleep(0.2)
        self.assertEqual(len(events), len(self.bridge.subscription(sid)['events']))

    def test_cancellation_and_app_unavailable(self):
        sid = self.subscribe()
        cancel = threading.Event()
        cancel.set()
        with self.assertRaisesRegex(ValueError, 'cancelled'):
            self.bridge.call('wait_for_events', {'subscription_id': sid}, cancel)
        self.app.terminate()
        self.app.communicate(timeout=5)
        snapshot = server.read_json(self.root / 'snapshot.json')
        snapshot['heartbeat_at'] = time.time() - 100
        server.atomic_json(self.root / 'snapshot.json', snapshot)
        result = self.bridge.call('wait_for_events', {'subscription_id': sid}, threading.Event())
        self.assertEqual(result['waiting_stopped'], 'app_unavailable')
        with self.assertRaisesRegex(ValueError, 'heartbeat'):
            self.subscribe()

    def test_unsubscribe_and_argument_validation(self):
        sid = self.subscribe()
        self.bridge.call('unsubscribe', {'subscription_id': sid}, threading.Event())
        self.fixture(results={'job-a': {'status': 'completed', 'outputs': []}, 'job-b': {'status': 'completed', 'outputs': []}})
        time.sleep(0.15)
        self.assertTrue(self.bridge.subscription(sid)['cancelled'])
        self.assertEqual(self.bridge.subscription(sid)['events'], [])
        for args in [{'subscription_id': '../../secret'}, {'subscription_id': sid, 'timeout_seconds': True}, {'subscription_id': sid, 'timeout_seconds': 3601}]:
            with self.assertRaises(ValueError):
                self.bridge.call('wait_for_events', args, threading.Event())
        for ids in [['../../secret'], ['job', 'job'], [], [3], 'job']:
            with self.assertRaises(ValueError):
                self.bridge.call('subscribe_jobs', {'endpoint': 'http://127.0.0.1:8188', 'prompt_ids': ids}, threading.Event())

    def test_channel_probe_routing_and_durable_ack(self):
        channel = server.Bridge(self.root, channel=True)
        sid = channel.call('subscribe_jobs', {'endpoint': 'http://127.0.0.1:8188', 'prompt_ids': ['own']}, threading.Event())['subscription_id']
        other = self.subscribe(['other'])
        self.fixture(results={'own': {'status': 'completed', 'outputs': []}, 'other': {'status': 'completed', 'outputs': []}})
        self.wait_until(lambda: len(channel.subscription(sid)['events']) > 0)
        self.assertEqual(channel.pending_channel_events(), [])
        with self.assertRaises(ValueError):
            channel.call('confirm_channel', {'nonce': 'wrong'}, threading.Event())
        channel.call('confirm_channel', {'nonce': channel.nonce}, threading.Event())
        events = channel.pending_channel_events()
        self.assertEqual([x['subscription_id'] for x in events], [sid])
        self.assertNotEqual(sid, other)
        ids = [x['event']['id'] for x in events]
        channel.call('acknowledge_events', {'subscription_id': sid, 'event_ids': ids}, threading.Event())
        self.assertEqual(channel.pending_channel_events(), [])

    def test_mcp_stdio_wire_and_cancellation(self):
        process = subprocess.Popen([sys.executable, str(PROJECT / 'agent_bridge/server.py'), '--state-dir', str(self.root)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        responses = queue.Queue()
        reader = threading.Thread(target=lambda: [responses.put(json.loads(line)) for line in process.stdout], daemon=True)
        reader.start()
        def send(value):
            process.stdin.write(json.dumps(value) + '\n')
            process.stdin.flush()
        def receive():
            return responses.get(timeout=5)
        try:
            send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 'test', 'version': '1'}}})
            init = receive()['result']
            self.assertEqual(init['protocolVersion'], '2025-06-18')
            self.assertNotIn('experimental', init['capabilities'])
            self.assertIn('Delegate', init['instructions'])
            send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'})
            self.assertIn('subscribe_jobs', [x['name'] for x in receive()['result']['tools']])
            send({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'subscribe_jobs', 'arguments': {'endpoint': 'http://127.0.0.1:8188', 'prompt_ids': ['wire']}}})
            result = receive()['result']
            self.assertFalse(result['isError'])
            sid = json.loads(result['content'][0]['text'])['subscription_id']
            send({'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'wait_for_events', 'arguments': {'subscription_id': sid, 'timeout_seconds': 5}}})
            send({'jsonrpc': '2.0', 'id': 5, 'method': 'ping'})
            self.assertEqual(receive()['id'], 5)  # The waiting tool does not block transport.
            send({'jsonrpc': '2.0', 'method': 'notifications/cancelled', 'params': {'requestId': 4}})
            time.sleep(0.1)
            send({'jsonrpc': '2.0', 'id': 6, 'method': 'tools/call', 'params': {'name': 'get_results', 'arguments': {'subscription_id': sid}}})
            self.assertEqual(receive()['id'], 6)
            send({'jsonrpc': '2.0', 'id': 7, 'method': 'tools/call', 'params': {'name': 'wait_for_events', 'arguments': {'subscription_id': sid, 'timeout_seconds': 5}}})
            self.fixture(results={'wire': {'status': 'completed', 'outputs': [{'filename': 'wire.mp4'}]}})
            completion = receive()
            self.assertEqual(completion['id'], 7)
            self.assertEqual(json.loads(completion['result']['content'][0]['text'])['events'][0]['kind'], 'batch_finished')
        finally:
            process.stdin.close()
            process.wait(timeout=5)
            process.stdout.close()
            process.stderr.close()
            reader.join(timeout=2)
        self.assertEqual(process.returncode, 0)

    def test_mcp_channel_event_transport(self):
        process = subprocess.Popen([sys.executable, str(PROJECT / 'agent_bridge/server.py'), '--state-dir', str(self.root), '--claude-channel'],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        responses = queue.Queue()
        reader = threading.Thread(target=lambda: [responses.put(json.loads(line)) for line in process.stdout], daemon=True)
        reader.start()
        def send(value):
            process.stdin.write(json.dumps(value) + '\n')
            process.stdin.flush()
        try:
            send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}})
            self.assertEqual(responses.get(timeout=5)['id'], 1)
            send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            probe = responses.get(timeout=5)
            self.assertEqual(probe['params']['meta']['kind'], 'channel_probe')
            nonce = probe['params']['content'].split('nonce ')[1].split('.')[0]
            send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {'name': 'confirm_channel', 'arguments': {'nonce': nonce}}})
            verified = json.loads(responses.get(timeout=5)['result']['content'][0]['text'])
            self.assertTrue(verified['delivery']['push_verified_in_this_session'])
            send({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'subscribe_jobs', 'arguments': {'endpoint': 'http://127.0.0.1:8188', 'prompt_ids': ['channel-job']}}})
            sid = json.loads(responses.get(timeout=5)['result']['content'][0]['text'])['subscription_id']
            self.fixture(results={'channel-job': {'status': 'completed', 'outputs': []}})
            event = responses.get(timeout=5)
            self.assertEqual(event['method'], 'notifications/claude/channel')
            self.assertEqual(event['params']['meta']['subscription_id'], sid)
            self.assertEqual(event['params']['meta']['kind'], 'batch_finished')
            event_id = event['params']['meta']['event_id']
            send({'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'acknowledge_events', 'arguments': {'subscription_id': sid, 'event_ids': [event_id]}}})
            self.assertEqual(responses.get(timeout=5)['id'], 4)
            with self.assertRaises(queue.Empty):
                responses.get(timeout=0.7)
            final = self.bridge.results(sid)['subscription']
            self.assertEqual(final['events'], [])
            self.assertEqual(final['acknowledged_event_count'], 1)
            self.assertTrue(final['finished'])
            stopped = self.bridge.call('wait_for_events', {'subscription_id': sid}, threading.Event())
            self.assertEqual(stopped['waiting_stopped'], 'finished')
        finally:
            process.stdin.close()
            process.wait(timeout=5)
            process.stdout.close()
            process.stderr.close()
            reader.join(timeout=2)
        self.assertEqual(process.returncode, 0)

    def test_channel_wire_probe(self):
        output = io.StringIO()
        channel = server.Bridge(self.root, channel=True)
        transport = server.Server(channel, output)
        try:
            transport.dispatch({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2026-07-28'}})
            transport.dispatch({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            frames = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(frames[0]['result']['protocolVersion'], '2025-06-18')
            self.assertEqual(frames[0]['result']['capabilities']['experimental'], {'claude/channel': {}})
            self.assertEqual(frames[1]['method'], 'notifications/claude/channel')
            self.assertIn(channel.nonce, frames[1]['params']['content'])
        finally:
            transport.pool.shutdown()


if __name__ == '__main__':
    unittest.main()
