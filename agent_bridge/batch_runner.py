#!/usr/bin/env python3
"""ComfyQueueBar agent batch runner: durable, one-at-a-time ComfyUI submission.

Runs detached from the AI agent. The MCP bridge and the app start it on demand;
a lock file guarantees a single runner per state directory. All batch state lives
in <state-dir>/batches/<batch_id>.json and is rewritten atomically after every
transition, so a crashed or restarted runner resumes exactly where it stopped.

Duplicate-submission rule: every segment has a fixed client_id. Before any
(re)submission the runner looks for that client_id in /queue and /history and
adopts an existing prompt instead of submitting again.
"""
import argparse
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

TERMINAL = ('completed', 'failed', 'cancelled')
DEFAULTS = {
    'lost_after_seconds': 600,      # gone from queue and history this long -> resubmit
    'poll_seconds': 5,
    'http_timeout_seconds': 30,
    'upload_timeout_seconds': 300,
    'download_timeout_seconds': 1800,
    'retries': 6,
    'max_resubmits': 3,
    'offline_notify_after_seconds': 60,
    'pipeline_depth': 1,            # own segments queued behind the running one
    'stall_bytes_per_second': 51200,  # abort a transfer slower than this ...
    'stall_seconds': 20,            # ... for this long, then retry
}


def now():
    return time.time()


def atomic_json(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name('.' + str(uuid.uuid4()) + '.tmp')
    with open(temporary, 'w') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=1)
    os.replace(temporary, path)


def notify(title, message):
    """macOS notification; silently ignored elsewhere or when disabled for tests."""
    if os.environ.get('COMFYQUEUEBAR_NO_NOTIFY'):
        log_path = os.environ.get('COMFYQUEUEBAR_NOTIFY_LOG')
        if log_path:
            with open(log_path, 'a') as stream:
                stream.write(json.dumps({'title': title, 'message': message}) + '\n')
        return
    script = 'display notification %s with title %s' % (json.dumps(message[:240]), json.dumps('ComfyQueueBar: ' + title[:80]))
    try:
        subprocess.run(['osascript', '-e', script], timeout=10, capture_output=True)
    except (OSError, subprocess.SubprocessError):
        pass


class Unreachable(Exception):
    pass


class Http:
    def __init__(self, endpoint, settings, sleep=time.sleep):
        self.endpoint = endpoint.rstrip('/')
        self.settings = settings
        self.sleep = sleep

    def request(self, method, path, body=None, headers=None, timeout=None, retries=None):
        """Retry with exponential backoff; raises Unreachable after the last attempt.
        HTTP 4xx responses are returned (not retried) so callers can read node_errors."""
        timeout = timeout or self.settings['http_timeout_seconds']
        retries = self.settings['retries'] if retries is None else retries
        delay = 1.0
        last = None
        for attempt in range(retries + 1):
            try:
                request = urllib.request.Request(self.endpoint + path, data=body, method=method, headers=headers or {})
                with urllib.request.urlopen(request, timeout=timeout) as response:
                    return response.status, response.read()
            except urllib.error.HTTPError as error:
                if 400 <= error.code < 500:
                    return error.code, error.read()
                last = error
            except (urllib.error.URLError, OSError, TimeoutError) as error:
                last = error
            if attempt < retries:
                self.sleep(min(delay, 30))
                delay *= 2
        raise Unreachable('%s %s failed after %d attempts: %s' % (method, path, retries + 1, last))

    def json(self, path, **kwargs):
        status, data = self.request('GET', path, **kwargs)
        if status != 200:
            raise Unreachable('GET %s returned HTTP %d' % (path, status))
        return json.loads(data or b'{}')


def multipart(fields, file_field, filename, content):
    boundary = uuid.uuid4().hex
    parts = []
    for key, value in fields.items():
        parts.append(('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (boundary, key, value)).encode())
    parts.append(('--%s\r\nContent-Disposition: form-data; name="%s"; filename="%s"\r\nContent-Type: application/octet-stream\r\n\r\n'
                  % (boundary, file_field, filename)).encode() + content + b'\r\n')
    parts.append(('--%s--\r\n' % boundary).encode())
    return b''.join(parts), 'multipart/form-data; boundary=' + boundary


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def wake_settings_for(endpoint):
    """Read the app's saved Wake-on-LAN settings for a matching server profile."""
    try:
        raw = subprocess.run(['defaults', 'export', 'io.github.sakmor.comfyqueuebar', '-'], capture_output=True, timeout=10).stdout
        profiles = json.loads(plistlib.loads(raw).get('serverProfiles', b'[]'))
    except Exception:
        return None
    for profile in profiles:
        if profile.get('endpoint', '').rstrip('/') == endpoint.rstrip('/') and profile.get('wake'):
            return profile['wake']
    return None


def send_wake(wake):
    parts = [int(x, 16) for x in wake['macAddress'].replace('-', ':').split(':')]
    if len(parts) != 6:
        raise ValueError('invalid MAC address')
    packet = b'\xff' * 6 + bytes(parts) * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        udp.sendto(packet, (wake.get('broadcastAddress') or '255.255.255.255', int(wake.get('port') or 9)))


def gpu_metrics(batch):
    """Per-segment GPU execution intervals and the idle gaps between consecutive own segments."""
    spans = sorted((s['gpu_started_at'], s['gpu_finished_at'], s['name']) for s in batch['segments']
                   if s.get('gpu_started_at') and s.get('gpu_finished_at'))
    gaps = []
    for (_, previous_end, previous), (start, _, name) in zip(spans, spans[1:]):
        gaps.append({'after': previous, 'before': name, 'seconds': round(max(0.0, start - previous_end), 3)})
    return {'segments': [{'name': name, 'started_at': start, 'finished_at': end, 'seconds': round(end - start, 3)} for start, end, name in spans],
            'gaps': gaps, 'idle_total_seconds': round(sum(g['seconds'] for g in gaps), 3),
            'note': 'Gaps include time other users\' jobs ran between own segments.'}


class BatchRunner:
    def __init__(self, root, sleep=time.sleep):
        self.root = Path(root)
        self.dir = self.root / 'batches'
        self.sleep = sleep
        self.downloads = {}
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)

    # ---------- state ----------
    def load(self, path):
        return json.loads(path.read_text())

    def save(self, batch):
        batch['updated_at'] = now()
        atomic_json(self.dir / (batch['batch_id'] + '.json'), batch)

    def event(self, batch, kind, message, segment=None, notify_user=False):
        batch.setdefault('events', []).append({'at': now(), 'kind': kind, 'segment': segment, 'message': message})
        batch['events'] = batch['events'][-200:]
        if notify_user and batch.get('notify', True):
            notify(batch.get('label') or batch['batch_id'][:8], message)

    def active_batches(self):
        result = []
        for path in sorted(self.dir.glob('*.json')):
            try:
                batch = self.load(path)
            except (OSError, ValueError):
                continue
            if batch.get('status') not in TERMINAL and batch.get('status') != 'needs_attention':
                result.append(batch)
        return sorted(result, key=lambda b: b.get('created_at', 0))

    # ---------- server ----------
    def server_ok(self, http, batch):
        """Single probe of /system_stats with short timeout; tracks offline state, notifies, wakes."""
        started = now()
        try:
            http.json('/system_stats', timeout=10, retries=1)
            if batch.get('offline_since'):
                self.event(batch, 'server_back', 'ComfyUI reachable again at ' + batch['endpoint'], notify_user=bool(batch.get('offline_notified')))
            batch['offline_since'] = None
            batch['offline_notified'] = False
            slow = now() - started
            if slow > 8:
                batch['server_hint'] = '/system_stats answered slowly (%.1fs); target may be overloaded or waking up.' % slow
            return True
        except (Unreachable, ValueError):
            pass
        batch['offline_since'] = batch.get('offline_since') or now()
        offline = now() - batch['offline_since']
        batch['server_hint'] = ('No response from /system_stats. The target Mac may be asleep or ComfyUI stopped; '
                                'start ComfyUI with `caffeinate -dimsu python main.py ...` to prevent idle sleep.')
        if offline >= batch['settings']['offline_notify_after_seconds'] and not batch.get('offline_notified'):
            batch['offline_notified'] = True
            self.event(batch, 'server_offline', 'ComfyUI unreachable for %ds. Target Mac may be asleep — start ComfyUI with caffeinate. Batch will resume automatically.' % offline, notify_user=True)
        if batch.get('offline_notified') and now() - batch.get('last_wake_at', 0) >= 300:
            batch['last_wake_at'] = now()
            wake = batch.get('wake') or wake_settings_for(batch['endpoint'])
            if wake and wake.get('macAddress') and wake.get('automaticallyWake', True):
                try:
                    send_wake(wake)
                    self.event(batch, 'wake_sent', 'Wake-on-LAN packet sent to ' + wake['macAddress'])
                except (OSError, ValueError) as error:
                    self.event(batch, 'wake_failed', 'Wake-on-LAN failed: %s' % error)
        return False

    def find_client(self, http, client_id):
        """Return (prompt_id, where) for a prompt submitted with client_id, or (None, None)."""
        queue = http.json('/queue')
        for where in ('queue_running', 'queue_pending'):
            for item in queue.get(where, []):
                # item: [number, prompt_id, prompt, extra_data, outputs]
                if len(item) > 3 and isinstance(item[3], dict) and item[3].get('client_id') == client_id:
                    return item[1], where
        history = http.json('/history?max_items=200')
        for prompt_id, record in history.items():
            prompt = record.get('prompt') or []
            if len(prompt) > 3 and isinstance(prompt[3], dict) and prompt[3].get('client_id') == client_id:
                return prompt_id, 'history'
        return None, None

    def others_in_queue(self, http, own_clients):
        queue = http.json('/queue')
        for item in queue.get('queue_running', []) + queue.get('queue_pending', []):
            client = item[3].get('client_id') if len(item) > 3 and isinstance(item[3], dict) else None
            if client not in own_clients:
                return True
        return False

    # ---------- segment steps ----------
    def upload(self, http, batch, segment):
        """Upload references with curl: retries, total timeout, and a low-speed stall abort."""
        settings = batch['settings']
        for item in segment.get('uploads', []) + batch.get('uploads', []):
            key = item['path']
            if key in batch.setdefault('uploaded', {}):
                continue
            name = item.get('name') or Path(item['path']).name
            last = None
            for attempt in range(settings['retries'] + 1):
                command = ['curl', '-fsS', '--connect-timeout', '15', '--max-time', str(settings['upload_timeout_seconds']),
                           '--speed-limit', str(int(settings['stall_bytes_per_second'])),
                           '--speed-time', str(max(1, int(settings['stall_seconds']))),
                           '-F', 'image=@%s;filename=%s' % (item['path'], name), '-F', 'overwrite=true',
                           '-F', 'type=' + item.get('type', 'input'), '-F', 'subfolder=' + item.get('subfolder', ''),
                           http.endpoint + '/upload/image']
                try:
                    result = subprocess.run(command, capture_output=True, timeout=settings['upload_timeout_seconds'] + 60)
                except subprocess.SubprocessError as error:
                    result, last = None, error
                if result is not None and result.returncode == 0:
                    batch['uploaded'][key] = json.loads(result.stdout or b'{}').get('name', name)
                    self.save(batch)
                    break
                if result is not None:
                    if result.returncode == 22 and b'error: 4' in result.stderr:
                        raise ValueError('upload %s rejected: %s' % (name, result.stderr[:300]))
                    last = 'curl exit %d %s' % (result.returncode, result.stderr.decode('utf-8', 'replace')[:200])
                if attempt < settings['retries']:
                    self.sleep(min(2 ** attempt, 30))
            else:
                raise Unreachable('upload %s failed: %s' % (name, last))

    def submit(self, http, batch, segment):
        graph = json.loads(Path(segment['graph']).read_text())
        body = json.dumps({'prompt': graph, 'client_id': segment['client_id']}).encode()
        segment['submit_attempts'] = segment.get('submit_attempts', 0) + 1
        segment['state'] = 'submitting'
        self.save(batch)
        try:
            status, data = http.request('POST', '/prompt', body=body, headers={'Content-Type': 'application/json'}, retries=0)
        except Unreachable as error:
            # Outcome unknown: the server may have accepted it. Never resubmit blindly.
            segment['state'] = 'submit_unknown'
            segment['unknown_since'] = now()
            self.event(batch, 'submit_unknown', 'Submit result unknown (%s); will reconcile by client_id.' % error, segment['name'])
            return
        if status != 200:
            try:
                detail = json.loads(data)
            except ValueError:
                detail = {'raw': data[:500].decode('utf-8', 'replace')}
            segment['state'] = 'failed'
            segment['error'] = detail
            batch['halt'] = True
            self.event(batch, 'node_errors', 'Segment %s rejected by ComfyUI (HTTP %d); needs attention.' % (segment['name'], status), segment['name'], notify_user=True)
            return
        segment['prompt_id'] = json.loads(data)['prompt_id']
        segment['state'] = 'queued'
        segment['missing_since'] = None
        segment.setdefault('prompt_ids', []).append(segment['prompt_id'])
        self.event(batch, 'submitted', 'Submitted %s as %s' % (segment['name'], segment['prompt_id']), segment['name'])

    def reconcile(self, http, batch, segment):
        """Locate the segment's prompt by client_id; adopt it, or decide lost / resubmit."""
        prompt_id, where = self.find_client(http, segment['client_id'])
        if prompt_id:
            if segment.get('prompt_id') != prompt_id:
                self.event(batch, 'adopted', 'Adopted existing prompt %s for %s (no duplicate submit)' % (prompt_id, segment['name']), segment['name'])
                segment.setdefault('prompt_ids', []).append(prompt_id)
            segment['prompt_id'] = prompt_id
            segment['missing_since'] = None
            segment['state'] = 'history' if where == 'history' else 'queued'
            return
        if segment['state'] == 'submit_unknown':
            # Give the server a short grace window to register it before resubmitting.
            if now() - segment.get('unknown_since', 0) >= min(30, batch['settings']['lost_after_seconds']):
                segment['state'] = 'pending'
            return
        segment['missing_since'] = segment.get('missing_since') or now()
        if now() - segment['missing_since'] >= batch['settings']['lost_after_seconds']:
            if segment.get('resubmits', 0) >= batch['settings']['max_resubmits']:
                segment['state'] = 'failed'
                batch['halt'] = True
                self.event(batch, 'lost', 'Segment %s lost repeatedly; needs attention.' % segment['name'], segment['name'], notify_user=True)
                return
            segment['resubmits'] = segment.get('resubmits', 0) + 1
            segment['state'] = 'pending'
            segment['prompt_id'] = None
            self.event(batch, 'lost', 'Segment %s missing from queue and history; resubmitting the same graph.' % segment['name'], segment['name'], notify_user=True)

    def collect(self, http, batch, segment):
        """Read the finished record, record GPU timing, and start a background download."""
        record = http.json('/history/' + urllib.parse.quote(segment['prompt_id'])).get(segment['prompt_id'])
        if not record:
            segment['state'] = 'queued'
            return
        status = record.get('status', {})
        if status.get('status_str') == 'error':
            segment['state'] = 'failed'
            segment['error'] = status.get('messages', [])[-3:]
            batch['halt'] = True
            self.event(batch, 'execution_error', 'Segment %s failed in ComfyUI; needs attention.' % segment['name'], segment['name'], notify_user=True)
            return
        if not status.get('completed', True) and status:
            return
        # Prefer ComfyUI's own execution timestamps; fall back to what the runner observed.
        for message in status.get('messages', []) or []:
            if isinstance(message, list) and len(message) == 2 and isinstance(message[1], dict) and 'timestamp' in message[1]:
                if message[0] == 'execution_start':
                    segment['gpu_started_at'] = message[1]['timestamp'] / 1000
                elif message[0] in ('execution_success', 'execution_error', 'execution_interrupted'):
                    segment['gpu_finished_at'] = message[1]['timestamp'] / 1000
        segment['gpu_finished_at'] = segment.get('gpu_finished_at') or segment.get('seen_finished_at') or now()
        segment['gpu_started_at'] = segment.get('gpu_started_at') or segment.get('seen_running_at') or segment['gpu_finished_at']
        files = []
        for node_output in record.get('outputs', {}).values():
            for kind in ('images', 'gifs', 'videos', 'audio'):
                for item in node_output.get(kind, []) or []:
                    if isinstance(item, dict) and 'filename' in item and item.get('type', 'output') == 'output':
                        files.append(item)
        segment['state'] = 'downloading'
        segment['download_files'] = files
        self.start_download(http, batch, segment)

    def start_download(self, http, batch, segment):
        key = (batch['batch_id'], segment['client_id'])
        if key in self.downloads:
            return
        out_dir = Path(segment.get('output_dir') or batch['output_dir'])
        settings = dict(batch['settings'])
        files = list(segment.get('download_files') or [])

        def work():
            out_dir.mkdir(parents=True, exist_ok=True)
            return [self.download(http.endpoint, settings, item, out_dir) for item in files]
        self.downloads[key] = self.pool.submit(work)

    def finish_download(self, batch, segment):
        key = (batch['batch_id'], segment['client_id'])
        future = self.downloads.get(key)
        if future is None:
            # Runner restarted mid-download: start again from the recorded file list.
            self.start_download(Http(batch['endpoint'], batch['settings'], self.sleep), batch, segment)
            return
        if not future.done():
            return
        del self.downloads[key]
        try:
            segment['outputs'] = future.result()
        except Exception as error:  # download exhausted its retries
            segment['download_failures'] = segment.get('download_failures', 0) + 1
            self.event(batch, 'download_retry', 'Download for %s failed (%s); retrying.' % (segment['name'], error), segment['name'])
            if segment['download_failures'] >= 3:
                segment['state'] = 'failed'
                segment['error'] = str(error)
                batch['halt'] = True
                self.event(batch, 'needs_attention', 'Segment %s output could not be downloaded; needs attention.' % segment['name'], segment['name'], notify_user=True)
            return
        segment['state'] = 'completed'
        segment['completed_at'] = now()
        segment.pop('download_files', None)
        done = sum(1 for s in batch['segments'] if s['state'] == 'completed')
        metrics = gpu_metrics(batch)
        self.event(batch, 'segment_completed', 'Segment %s done (%d/%d), %d file(s) saved. GPU idle between segments so far: %.0fs.'
                   % (segment['name'], done, len(batch['segments']), len(segment['outputs']), metrics['idle_total_seconds']),
                   segment['name'], notify_user=True)

    def download(self, endpoint, settings, item, out_dir):
        """curl with a low-speed stall abort; write to .part, verify size+SHA256, then rename."""
        query = urllib.parse.urlencode({'filename': item['filename'], 'subfolder': item.get('subfolder', ''), 'type': item.get('type', 'output')})
        url = endpoint + '/view?' + query
        target = out_dir / item['filename']
        partial = target.with_name(target.name + '.part')
        headers_path = target.with_name(target.name + '.headers')
        last = None
        for attempt in range(settings['retries'] + 1):
            try:
                partial.unlink(missing_ok=True)
                command = ['curl', '-fsS', '--connect-timeout', '15',
                           '--speed-limit', str(int(settings['stall_bytes_per_second'])),
                           '--speed-time', str(max(1, int(settings['stall_seconds']))),
                           '--max-time', str(settings['download_timeout_seconds']),
                           '-D', str(headers_path), '-o', str(partial), url]
                result = subprocess.run(command, capture_output=True, timeout=settings['download_timeout_seconds'] + 60)
                if result.returncode != 0:
                    reason = 'stalled below %d B/s for %ds' % (settings['stall_bytes_per_second'], settings['stall_seconds']) if result.returncode == 28 else 'curl exit %d' % result.returncode
                    raise OSError('%s: %s' % (reason, result.stderr.decode('utf-8', 'replace')[:200]))
                expected = None
                for line in headers_path.read_text('latin-1').lower().splitlines():
                    if line.startswith('http/'):
                        expected = None  # keep only the final response block
                    elif line.startswith('content-length:'):
                        expected = int(line.split(':', 1)[1].strip())
                size = partial.stat().st_size
                if expected is not None and size != expected:
                    raise OSError('size mismatch %d != %d' % (size, expected))
                if size == 0:
                    raise OSError('empty download')
                digest = sha256(partial)
                os.replace(partial, target)
                if sha256(target) != digest:
                    raise OSError('sha256 changed after rename')
                headers_path.unlink(missing_ok=True)
                return {'filename': item['filename'], 'path': str(target), 'bytes': size, 'sha256': digest,
                        'size_verified_against_server': expected is not None, 'attempts': attempt + 1}
            except (OSError, subprocess.SubprocessError, ValueError) as error:
                last = error
                if attempt < settings['retries']:
                    self.sleep(min(2 ** attempt, 30))
        partial.unlink(missing_ok=True)
        headers_path.unlink(missing_ok=True)
        raise Unreachable('download %s failed: %s' % (item['filename'], last))

    # ---------- main loop ----------
    def step(self, batch):
        """Advance one batch. Keeps 1 running + pipeline_depth queued own segments, never ahead of foreign jobs.
        Returns True while the batch is still active."""
        if batch.get('cancel_requested'):
            batch['status'] = 'cancelled'
            self.event(batch, 'cancelled', 'Batch cancelled by request; already-queued prompts were not interrupted.')
            self.save(batch)
            return False
        batch['settings'] = {**DEFAULTS, **batch['settings']}  # batches saved by older runners
        http = Http(batch['endpoint'], batch['settings'], self.sleep)
        segments = batch['segments']
        waiting = False
        # Downloads run in the background and do not need the server to stay reachable.
        for segment in segments:
            if segment['state'] == 'downloading':
                self.finish_download(batch, segment)
        if not self.server_ok(http, batch):
            batch['status'] = 'waiting_for_server'
            batch['gpu'] = gpu_metrics(batch)
            self.save(batch)
            return True
        current = None
        try:
            queue = http.json('/queue')
            running_clients = {item[3].get('client_id') for item in queue.get('queue_running', []) if len(item) > 3 and isinstance(item[3], dict)}
            for segment in segments:
                current = segment
                if segment['state'] == 'submitting':
                    segment['state'] = 'submit_unknown'
                    segment['unknown_since'] = segment.get('unknown_since') or now()
                if segment['state'] in ('queued', 'submit_unknown'):
                    self.reconcile(http, batch, segment)
                if segment['state'] == 'queued' and segment['client_id'] in running_clients and not segment.get('seen_running_at'):
                    segment['seen_running_at'] = now()
                if segment['state'] == 'history':
                    segment['seen_finished_at'] = segment.get('seen_finished_at') or now()
                    self.collect(http, batch, segment)
            current = None
            in_flight = [s for s in segments if s['state'] in ('queued', 'submit_unknown')]
            depth = 1 + int(batch['settings']['pipeline_depth'])
            if not batch.get('halt') and len(in_flight) < depth and not any(s['state'] == 'submit_unknown' for s in in_flight):
                segment = next((s for s in segments if s['state'] == 'pending'), None)
                if segment is not None:
                    current = segment
                    prompt_id, where = self.find_client(http, segment['client_id'])
                    if prompt_id:
                        self.reconcile(http, batch, segment)
                    elif self.others_in_queue(http, {s['client_id'] for s in segments}):
                        waiting = True  # never jump ahead of other users' jobs
                    else:
                        self.upload(http, batch, segment)
                        self.submit(http, batch, segment)
        except Unreachable as error:
            batch['last_error'] = str(error)
            self.event(batch, 'transient_error', str(error), current['name'] if current else None)
        except (OSError, ValueError, KeyError) as error:
            if current is not None:
                current['state'] = 'failed'
                current['error'] = str(error)
            batch['halt'] = True
            self.event(batch, 'needs_attention', 'Segment %s: %s' % (current['name'] if current else '?', error),
                       current['name'] if current else None, notify_user=True)
        batch['gpu'] = gpu_metrics(batch)
        busy = [s for s in segments if s['state'] in ('queued', 'submit_unknown', 'submitting', 'history', 'downloading')]
        if all(s['state'] == 'completed' for s in segments):
            batch['status'] = 'completed'
            self.event(batch, 'batch_completed', 'Batch finished: %d segment(s) collected into %s. GPU idle between segments: %.0fs total.'
                       % (len(segments), batch['output_dir'], batch['gpu']['idle_total_seconds']), notify_user=True)
        elif batch.get('halt') and not busy:
            batch['status'] = 'needs_attention'
        elif batch.get('halt'):
            batch['status'] = 'finishing_before_attention'
        else:
            batch['status'] = 'waiting_for_queue' if waiting and not busy else 'running'
        self.save(batch)
        return batch['status'] not in TERMINAL + ('needs_attention',)

    def run(self, idle_exit_seconds=120):
        idle_since = None
        while True:
            batches = self.active_batches()
            if not batches:
                idle_since = idle_since or now()
                if now() - idle_since >= idle_exit_seconds:
                    return
                self.sleep(1)
                continue
            idle_since = None
            for batch in batches:
                # re-read so cancel requests from the bridge are seen
                path = self.dir / (batch['batch_id'] + '.json')
                try:
                    self.step(self.load(path))
                except Exception as error:  # keep the runner alive; record and retry next cycle
                    try:
                        crashed = self.load(path)
                        self.event(crashed, 'runner_error', 'Internal runner error: %r' % error)
                        self.save(crashed)
                    except (OSError, ValueError):
                        pass
            self.sleep(min(b['settings']['poll_seconds'] for b in batches))



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', default=os.environ.get('COMFYQUEUEBAR_AGENT_DIR', str(Path.home() / 'Library/Application Support/ComfyQueueBar/AgentBridge')))
    parser.add_argument('--idle-exit-seconds', type=float, default=120)
    args = parser.parse_args()
    root = Path(args.state_dir)
    (root / 'batches').mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = open(root / 'batches' / '.runner.lock', 'w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0  # another runner owns this state directory
    lock.write(str(os.getpid()))
    lock.flush()
    BatchRunner(root).run(args.idle_exit_seconds)
    return 0


if __name__ == '__main__':
    sys.exit(main())
