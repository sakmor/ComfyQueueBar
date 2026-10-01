"""Exercise the observer without a ComfyUI process or external dependencies."""
import asyncio
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.registered = []
        self.reset_calls = []
        self.routes = {}
        web = types.ModuleType('aiohttp.web')
        web.Request = object
        web.Response = object
        web.json_response = lambda payload: payload
        aiohttp = types.ModuleType('aiohttp')
        aiohttp.web = web
        server = types.ModuleType('server')
        routes = types.SimpleNamespace(get=lambda path: lambda fn: self.routes.setdefault(path, fn))
        server.PromptServer = types.SimpleNamespace(instance=types.SimpleNamespace(routes=routes))
        execution = types.ModuleType('execution')
        execution.reset_progress_state = lambda *args: self.reset_calls.append(args)
        progress = types.ModuleType('comfy_execution.progress')

        class Handler:
            def __init__(self, name):
                self.name = name

        progress.ProgressHandler = Handler
        progress.add_progress_handler = self.registered.append
        self.execution = execution
        stubs = {'aiohttp': aiohttp, 'aiohttp.web': web, 'server': server,
                 'execution': execution, 'comfy_execution': types.ModuleType('comfy_execution'),
                 'comfy_execution.progress': progress}
        with patch.dict(sys.modules, stubs):
            spec = importlib.util.spec_from_file_location(
                'queuebar_test_extension', ROOT / 'comfyui_extension/ComfyQueueBarProgress/__init__.py')
            self.module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.module)
        self.handler = self.module._progress_handler

    def state(self, value, maximum, name='running'):
        return {'value': value, 'max': maximum, 'state': types.SimpleNamespace(value=name)}

    def test_fraction_and_clamping(self):
        self.handler.update_handler('12', 1, 3, self.state(1, 3), 'job-a')
        self.assertEqual(self.handler.snapshot()['percent'], 33.3)
        self.handler.update_handler('12', 9, 3, self.state(9, 3), 'job-a')
        self.assertEqual(self.handler.snapshot()['percent'], 100)
        self.handler.update_handler('12', -1, 3, self.state(-1, 3), 'job-a')
        self.assertEqual(self.handler.snapshot()['percent'], 0)

    def test_unknown_fraction_and_finished_node(self):
        self.handler.start_handler('2', self.state(0, 1), 'job-a')
        self.assertIsNone(self.handler.snapshot()['percent'])
        self.handler.start_handler('2', self.state(1, 0), 'job-a')
        self.assertIsNone(self.handler.snapshot()['percent'])
        self.handler.finish_handler('2', self.state(1, 1, 'finished'), 'job-a')
        self.assertEqual(self.handler.snapshot()['percent'], 100)
        self.assertEqual(self.handler.snapshot()['state'], 'finished')

    def test_snapshot_is_independent(self):
        self.handler.start_handler(2, self.state(1, 2), 'job-a')
        snapshot = self.handler.snapshot()
        snapshot['prompt_id'] = 'changed'
        self.assertEqual(self.handler.snapshot()['prompt_id'], 'job-a')
        self.assertEqual(self.handler.snapshot()['node_id'], '2')

    def test_each_prompt_resets_snapshot_and_registers_after_original_reset(self):
        self.handler.start_handler('2', self.state(1, 2), 'old-job')
        self.execution.reset_progress_state('new-job', 'graph')
        self.assertEqual(self.reset_calls, [('new-job', 'graph')])
        self.assertEqual(self.registered, [self.handler])
        self.assertTrue(all(value is None for value in self.handler.snapshot().values()))
        self.execution.reset_progress_state('next-job', 'next-graph')
        self.assertEqual(len(self.registered), 2)

    def test_route_returns_current_snapshot(self):
        self.handler.start_handler('9', self.state(3, 4), 'job-a')
        response = asyncio.run(self.routes['/comfyqueuebar/queue-progress'](None))
        self.assertEqual(response['prompt_id'], 'job-a')
        self.assertEqual(response['percent'], 75)
        self.assertEqual(self.module.NODE_CLASS_MAPPINGS, {})


if __name__ == '__main__':
    unittest.main()
