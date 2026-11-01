"""Continuation regressions using app-owned snapshots, without GPU or job submission."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('continuation_server', PROJECT / 'agent_bridge/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class ContinuationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sid = str(uuid.uuid4())
        self.bridge = server.Bridge(self.root)
        self.sub = {'subscription_id': self.sid, 'endpoint': 'http://test:8188',
                    'prompt_ids': ['original-job'], 'created_at': time.time(), 'cancelled': False,
                    'results': {'original-job': {'status': 'running', 'last_verified_at': 1}},
                    'events': [], 'acknowledged': []}
        self.save()
        self.snapshot()

    def save(self):
        server.atomic_json(self.root / 'subscriptions.json', {self.sid: self.sub})

    def snapshot(self, **overrides):
        self.snap = {'enabled': True, 'heartbeat_at': time.time(), 'last_queue_update': time.time(),
                     'endpoint': 'http://test:8188', 'connected': True, 'history_available': True,
                     'running': ['original-job'], 'pending': [], 'notification_mode': 'off',
                     'macos_notification_authorization': 'authorized', **overrides}
        server.atomic_json(self.root / 'snapshot.json', self.snap)

    def wait(self, **args):
        return self.bridge.call('wait_for_completion', {'subscription_id': self.sid,
                                'timeout_seconds': 3, **args}, threading.Event())

    def complete(self):
        self.sub['results']['original-job'] = {'status': 'completed', 'outputs': [{'filename': 'clip.mp4'}]}
        self.save()

    def test_one_wait_survives_old_events_and_brief_disconnect_then_finishes(self):
        self.sub['events'] = [{'id': 'old-disconnect', 'kind': 'monitoring_changed'}]
        self.save()
        output = {}
        worker = threading.Thread(target=lambda: output.update(self.wait(recovery_grace_seconds=2)))
        worker.start()
        self.snapshot(connected=False)
        time.sleep(0.35)
        self.assertTrue(worker.is_alive())
        self.snapshot()
        time.sleep(0.35)
        self.assertTrue(worker.is_alive())
        self.complete()
        worker.join(4)
        self.assertFalse(worker.is_alive())
        self.assertEqual(output['waiting_stopped'], 'finished')
        self.assertEqual(output['continuation']['state'], 'ready_for_review')
        self.assertFalse(output['continuation']['qc_approved'])
        self.assertFalse(output['continuation']['automatic_submission'])
        self.assertEqual(self.bridge.subscription(self.sid)['acknowledged'], [])
        self.assertFalse((self.root / 'commands').exists())

    def test_timeout_is_not_completion_and_preserves_subscription(self):
        before = (self.root / 'subscriptions.json').read_bytes()
        result = self.wait(timeout_seconds=1)
        self.assertEqual(result['waiting_stopped'], 'timeout')
        self.assertEqual(result['continuation']['state'], 'waiting')
        self.assertFalse(result['subscription']['finished'])
        self.assertEqual((self.root / 'subscriptions.json').read_bytes(), before)

    def test_queue_disappearance_refreshes_exact_history_before_bulk_cadence(self):
        original_call = self.bridge.call
        calls = []
        def call(name, args, cancel):
            if name == 'refresh_job':
                calls.append(args['prompt_id'])
                self.complete()
                return {'status': 'completed'}
            return original_call(name, args, cancel)
        self.bridge.call = call
        self.snapshot(running=[])
        result = self.wait(timeout_seconds=60)
        self.assertEqual(calls, ['original-job'])
        self.assertEqual(result['waiting_stopped'], 'finished')
        self.assertEqual(result['history_refreshes'][0]['status'], 'completed')

    def test_unknown_refresh_does_not_loop_or_infer_completion(self):
        original_call = self.bridge.call
        calls = []
        def call(name, args, cancel):
            if name == 'refresh_job':
                calls.append(args['prompt_id'])
                return {'status': 'unknown'}
            return original_call(name, args, cancel)
        self.bridge.call = call
        self.snapshot(running=[])
        output = {}
        worker = threading.Thread(target=lambda: output.update(self.wait(timeout_seconds=60)))
        worker.start()
        time.sleep(0.7)
        self.assertTrue(worker.is_alive())
        self.assertEqual(calls, ['original-job'])
        self.complete()
        worker.join(3)
        self.assertEqual(calls, ['original-job'])
        self.assertEqual(output['waiting_stopped'], 'finished')

    def test_failure_returns_before_other_jobs_and_does_not_retry(self):
        self.sub['prompt_ids'].append('pending-job')
        self.sub['results']['original-job'] = {'status': 'failed', 'error': 'out of memory'}
        self.save()
        result = self.wait()
        self.assertEqual(result['waiting_stopped'], 'job_failed')
        self.assertFalse(result['subscription']['finished'])
        self.assertEqual(result['continuation']['state'], 'needs_attention')
        self.assertFalse((self.root / 'commands').exists())

    def test_server_switch_and_persistent_disconnect_stop_without_success(self):
        self.snapshot(endpoint='http://another:8188')
        self.assertEqual(self.wait()['waiting_stopped'], 'server_changed')
        self.snapshot(connected=False)
        result = self.wait(recovery_grace_seconds=0)
        self.assertEqual(result['waiting_stopped'], 'monitoring_unavailable')
        self.assertEqual(result['subscription']['results']['original-job']['status'], 'unknown')
        self.assertFalse(result['subscription']['finished'])

    def test_cancellation_leaves_existing_job_and_subscription_untouched(self):
        cancel = threading.Event()
        cancel.set()
        with self.assertRaisesRegex(ValueError, 'subscription remains active'):
            self.bridge.call('wait_for_completion', {'subscription_id': self.sid}, cancel)
        self.assertFalse(self.bridge.subscription(self.sid)['cancelled'])
        self.sub['cancelled'] = True
        self.save()
        self.assertEqual(self.wait()['waiting_stopped'], 'cancelled')

    def test_live_verification_time_and_stale_running_are_not_confused(self):
        result = self.bridge.results(self.sid)['subscription']['results']['original-job']
        self.assertEqual(result['status'], 'running')
        self.assertEqual(result['last_verified_at'], self.snap['last_queue_update'])
        self.snapshot(running=[])
        result = self.bridge.results(self.sid)['subscription']['results']['original-job']
        self.assertEqual(result['status'], 'unknown')
        self.assertEqual(result['last_known_status'], 'running')
        self.assertIn('awaiting_history', result['unknown_reason'])
        self.snapshot(last_queue_update=time.time() - 90)
        self.assertEqual(self.bridge.results(self.sid)['subscription']['results']['original-job']['status'], 'unknown')
        self.complete()
        self.assertEqual(self.wait()['waiting_stopped'], 'finished')  # durable terminal history survives stale queue

    def test_notifications_off_are_not_reported_as_completion_delivery(self):
        result = self.bridge.status()['app_notifications']
        self.assertTrue(result['os_permission_granted'])
        self.assertFalse(result['can_notify_completion'])
        self.assertFalse(result['can_notify_user'])
        self.snapshot(notification_mode='batch')
        self.assertTrue(self.bridge.status()['app_notifications']['can_notify_completion'])
        self.snapshot(notification_mode='batch', macos_notification_authorization='denied')
        self.assertFalse(self.bridge.status()['app_notifications']['can_notify_completion'])

    def test_completion_cli_is_read_only_and_returns_exact_job(self):
        self.complete()
        before = (self.root / 'subscriptions.json').read_bytes()
        result = subprocess.run([sys.executable, str(PROJECT / 'agent_bridge/server.py'),
                                 '--state-dir', str(self.root), '--wait-for-completion', self.sid,
                                 '--timeout-seconds', '2'], capture_output=True, text=True, check=True)
        output = json.loads(result.stdout)
        self.assertEqual(output['waiting_stopped'], 'finished')
        self.assertEqual(list(output['subscription']['results']), ['original-job'])
        self.assertEqual((self.root / 'subscriptions.json').read_bytes(), before)
        self.assertFalse(output['delivery']['idle_conversation_wakeup'])

    def test_completion_arguments_are_bounded_and_typed(self):
        for args in [{'timeout_seconds': True}, {'timeout_seconds': 0}, {'timeout_seconds': 3601},
                     {'recovery_grace_seconds': -1}, {'recovery_grace_seconds': True},
                     {'recovery_grace_seconds': 301}]:
            with self.assertRaises(ValueError):
                self.wait(**args)
