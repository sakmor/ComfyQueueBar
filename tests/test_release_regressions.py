"""Release review regressions: durable cancellation, validation and safe downloads."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import uuid


PROJECT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, PROJECT / 'agent_bridge' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


server = load('review_server', 'server.py')
runner = load('review_runner', 'batch_runner.py')


class ReleaseRegressions(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.graph = self.root / 'graph.json'
        self.graph.write_text(json.dumps({'1': {'class_type': 'Example', 'inputs': {}}}))
        self.bridge = server.Bridge(self.root)
        self.worker = runner.BatchRunner(self.root)
        self.addCleanup(self.worker.pool.shutdown, wait=True)
        self.args = {'batch_id': str(uuid.uuid4()), 'endpoint': 'http://localhost:8188',
                     'output_dir': str(self.root), 'segments': [{'graph': str(self.graph)}]}
        self.launch = patch.object(server, 'ensure_runner')
        self.launch.start()
        self.addCleanup(self.launch.stop)

    def batch(self):
        self.bridge.batch_call('submit_batch', self.args)
        return server.read_json(self.bridge.batch_path(self.args['batch_id']))

    def test_invalid_settings_rejected_before_persisting_or_launching(self):
        for key, value in [('retries', 1.5), ('max_resubmits', True), ('pipeline_depth', 0.5),
                           ('retries', 101), ('poll_seconds', 0), ('download_timeout_seconds', 0),
                           ('http_timeout_seconds', float('nan')), ('stall_seconds', float('inf'))]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.bridge.batch_call('submit_batch', {**self.args, 'settings': {key: value}})
        self.assertFalse(self.bridge.batch_path(self.args['batch_id']).exists())
        server.ensure_runner.assert_not_called()

    def test_relative_segment_output_and_empty_segments_rejected(self):
        for args in [{**self.args, 'segments': []},
                     {**self.args, 'segments': [{'graph': str(self.graph), 'output_dir': '../elsewhere'}]}]:
            with self.assertRaises(ValueError):
                self.bridge.batch_call('submit_batch', args)

    def test_full_batch_uuid_prevents_client_prefix_collisions(self):
        batch = self.batch()
        other = copy.deepcopy(self.args)
        other['batch_id'] = self.args['batch_id'][:8] + str(uuid.uuid4())[8:]
        result = self.bridge.batch_call('submit_batch', other)
        self.assertNotEqual(batch['segments'][0]['client_id'], result['segments'][0]['client_id'])

    def test_cancel_survives_stale_runner_save_and_blocks_submission(self):
        stale = self.batch()
        self.bridge.batch_call('cancel_batch', {'batch_id': stale['batch_id']})
        self.worker.save(stale)
        self.assertTrue(server.read_json(self.bridge.batch_path(stale['batch_id']))['cancel_requested'])
        http = SimpleNamespace(request=lambda *a, **kw: self.fail('cancelled batch submitted work'))
        self.worker.submit(http, stale, stale['segments'][0])
        self.assertNotIn('submit_attempts', stale['segments'][0])

    def test_unknown_submission_honors_retry_limit(self):
        batch = self.batch()
        batch['settings']['max_resubmits'] = 1
        segment = batch['segments'][0]
        with patch.object(self.worker, 'find_client', return_value=(None, None)), patch.object(runner, 'now', return_value=1000), patch.object(runner, 'notify'):
            for expected in ('pending', 'failed'):
                segment.update(state='submit_unknown', unknown_since=0)
                self.worker.reconcile(None, batch, segment)
                self.assertEqual(segment['state'], expected)
        self.assertTrue(batch['halt'])

    def test_exact_history_checked_outside_recent_window(self):
        calls = []
        def get(path):
            calls.append(path)
            if path == '/queue':
                return {'queue_running': [], 'queue_pending': []}
            if path == '/history/exact-id':
                return {'exact-id': {'status': {'completed': True, 'status_str': 'success'}}}
            self.fail('Must use exact history before bounded recent history')
        result = self.worker.find_client(SimpleNamespace(json=get), 'client', 'exact-id')
        self.assertEqual(result, ('exact-id', 'history'))
        self.assertEqual(len(calls), 2)

    def test_missing_success_status_never_starts_download(self):
        batch = self.batch()
        segment = batch['segments'][0]
        segment['prompt_id'] = 'exact'
        for status in ({}, {'completed': True}, {'completed': False, 'status_str': 'success'}):
            http = SimpleNamespace(json=lambda _: {'exact': {'status': status}})
            with patch.object(self.worker, 'start_download') as download:
                self.worker.collect(http, batch, segment)
                download.assert_not_called()

    def test_finished_download_completes_even_if_server_went_offline(self):
        batch = self.batch()
        segment = batch['segments'][0]
        segment['state'] = 'downloading'
        def finish(batch, segment):
            segment['state'] = 'completed'
        with patch.object(self.worker, 'finish_download', side_effect=finish), patch.object(self.worker, 'server_ok') as probe, patch.object(runner, 'notify'):
            self.assertFalse(self.worker.step(batch))
            self.assertEqual(batch['status'], 'completed')
            probe.assert_not_called()

    def test_download_rejects_unsafe_names_without_writing(self):
        for name in ('../outside', '/tmp/outside', '..', 'a/b.png', 'a\\b.png', 'bad\x00name'):
            with self.subTest(name=name), patch.object(runner.subprocess, 'run') as curl, self.assertRaises(ValueError):
                self.worker.download('http://localhost', runner.DEFAULTS, {'filename': name}, self.root)
            curl.assert_not_called()

    def test_download_preserves_distinct_subfolders_and_existing_files(self):
        (self.root / 'same.png').write_bytes(b'keep existing output')
        def curl(command, **kwargs):
            Path(command[command.index('-o') + 1]).write_bytes(b'downloaded')
            Path(command[command.index('-D') + 1]).write_text('HTTP/1.1 200 OK\r\nContent-Length: 10\r\n')
            return SimpleNamespace(returncode=0, stderr=b'')
        with patch.object(runner.subprocess, 'run', side_effect=curl):
            outputs = [self.worker.download('http://localhost', runner.DEFAULTS,
                        {'filename': 'same.png', 'subfolder': folder}, self.root) for folder in ('a', 'b')]
        self.assertNotEqual(outputs[0]['path'], outputs[1]['path'])
        self.assertEqual((self.root / 'same.png').read_bytes(), b'keep existing output')
        self.assertTrue(all(Path(o['path']).read_bytes() == b'downloaded' for o in outputs))
        self.assertEqual(list(self.root.glob('*.part')), [])


if __name__ == '__main__':
    unittest.main()
