#!/usr/bin/env python3
"""Read-only, one-shot probe of the host's Codex App Tools MCP connection.

This never sends a message or starts a turn. A successful tool listing is only
transport evidence; it does not prove that an idle desktop thread can wake.
"""
import json
import os
from pathlib import Path
import subprocess
import threading
import queue


def probe(node=None, server=None, timeout=8):
    node = node or os.environ.get('CODEX_MCP_NODE_PATH')
    if server is None:
        roots = (Path.home() / '.codex/plugins/cache/openai-bundled/codex-app-tools').glob('*/server.mjs')
        candidates = sorted(roots, key=lambda p: p.stat().st_mtime, reverse=True)
        server = str(candidates[0]) if candidates else None
    if not node or not server or not os.environ.get('CODEX_APP_TOOLS_PIPE_PATH'):
        return {'transport': 'unavailable', 'idle_wake': 'unverified', 'reason': 'Codex host connection or official client is unavailable'}
    requests = [
        {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-03-26', 'capabilities': {}, 'clientInfo': {'name': 'ComfyQueueBar', 'version': '1'}}},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}},
    ]
    try:
        process = subprocess.Popen([node, server], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        messages = queue.Queue()
        def receive():
            for line in process.stdout:
                messages.put(line)
        threading.Thread(target=receive, daemon=True).start()
        try:
            process.stdin.write(''.join(json.dumps(x) + '\n' for x in requests))
            process.stdin.flush()
            lines = []
            import time
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    line = messages.get(timeout=max(0.01, deadline - time.monotonic()))
                except queue.Empty:
                    break
                lines.append(line)
                try:
                    if json.loads(line).get('id') == 2:
                        break
                except ValueError:
                    pass
            output = ''.join(lines)
        finally:
            process.terminate()
            try:
                process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
    except OSError:
        return {'transport': 'unavailable', 'idle_wake': 'unverified', 'reason': 'Could not start the official Codex App Tools client'}
    for line in output.splitlines():
        try:
            response = json.loads(line)
        except ValueError:
            continue
        if response.get('id') != 2:
            continue
        if 'error' in response:
            return {'transport': 'unavailable', 'idle_wake': 'unverified', 'reason': 'Codex host rejected or closed the app tool connection'}
        names = [item.get('name') for item in response.get('result', {}).get('tools', [])]
        return {'transport': 'available', 'idle_wake': 'unverified', 'send_tool_available': 'send_message_to_thread' in names,
                'reason': 'Tool discovery alone does not verify event-triggered continuation of an idle thread'}
    return {'transport': 'unavailable', 'idle_wake': 'unverified', 'reason': 'Codex host returned no tool discovery result'}


if __name__ == '__main__':
    print(json.dumps(probe(), ensure_ascii=False))
