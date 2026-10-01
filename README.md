<p align="center">
  <img src="assets/app-icon.png" width="112" alt="ComfyQueueBar app icon: stacked queue cards with a play symbol" />
</p>

<h1 align="center">ComfyQueueBar</h1>

<p align="center"><strong>Your ComfyUI queue, one click away in the macOS menu bar.</strong></p>
<p align="center">See what's running. Check node progress. Choose what runs next.</p>

<p align="center">
  <a href="#quick-start">Install</a> ·
  <a href="docs/USAGE.md">Usage guide</a> ·
  <a href="docs/REMOTE_SETUP.md">Remote setup</a> ·
  <a href="docs/TROUBLESHOOTING.md">Troubleshooting</a>
</p>

<table>
  <tr>
    <td align="center"><img src="docs/images/queue-light.png" width="340" alt="Light mode: one running job at 70 percent node progress, a Stop button, and a waiting job with a Prioritize button" /><br /><strong>Light appearance</strong></td>
    <td align="center"><img src="docs/images/queue-dark.png" width="340" alt="Dark mode: ComfyUI running and waiting queues with job controls" /><br /><strong>Dark appearance</strong></td>
  </tr>
</table>

*Screenshots of the actual SwiftUI interface with fixed demonstration data. Node progress is not whole-workflow progress.*

| Check progress | Choose the next job | Stop a running job |
| --- | --- | --- |
| See running / waiting counts and the current node's percentage. | **Prioritize** moves a waiting job to the front by resubmitting it. | **Stop** requests interruption while keeping waiting jobs queued. |

A native macOS utility built with SwiftUI. Connect to local ComfyUI or a remote server over SSH. No Electron or third-party Swift packages.

## Features

- Menu bar icon with the total number of running and waiting jobs.
- Separate running and waiting lists, refreshed every **4 seconds**.
- Workflow names, shortened prompt IDs, node counts, and waiting positions.
- **Prioritize** a waiting job with a confirmation dialog.
- **Stop** a running job with a confirmation dialog, keeping the waiting queue.
- Optional node name and percentage updates every **1 second**, using the included server extension.
- Saved ComfyUI address and a manual refresh button.
- Native macOS appearance, with no Dock window.
- Local or remote ComfyUI connections, including SSH port forwarding.

## Requirements

| Component | Requirement |
| --- | --- |
| Mac app | macOS 13 Ventura or later |
| Building from source | Swift 5.9 or later, provided by a suitable Xcode / Command Line Tools installation |
| ComfyUI | A reachable server exposing `/queue` and `/prompt`; targeted Stop requires `/interrupt` to honor `prompt_id` |
| Optional progress | ComfyUI with `comfy_execution.progress.ProgressHandler`, `add_progress_handler`, and `execution.reset_progress_state` |
| Server extension | Runs inside ComfyUI's own Python environment; uses its existing `aiohttp` dependency |

The Mac app is macOS-only. A remote ComfyUI server may run on macOS, Linux, or Windows. The build script produces a binary for the Mac architecture on which it runs; it does not produce a universal binary. Older ComfyUI versions and third-party distributions can differ: see [compatibility](docs/DEVELOPMENT.md#comfyui-compatibility).

## Quick start

### 1. Check your build tools

```sh
xcode-select --install
```

If the tools are already installed, skip installation. Verify your compiler:

```sh
swift --version
```

The Swift version must be at least 5.9. If an older Command Line Tools installation provides an earlier Swift version, update the tools or select a suitable Xcode installation.

### 2. Clone and build

```sh
git clone https://github.com/sakmor/ComfyQueueBar.git
cd ComfyQueueBar
bash build-app.sh
open build/ComfyQueueBar.app
```

The build script compiles a release binary, creates an app bundle, and signs it locally with an ad-hoc signature. It rebuilds only this repository's `build/ComfyQueueBar.app`. It does not install or start ComfyUI.

### 3. Connect to ComfyUI

1. Start your existing ComfyUI installation.
2. Click the stacked icon in the macOS menu bar.
3. Enter your **ComfyUI address**, normally `http://127.0.0.1:8188`.
4. Click **Connect**.
5. Queue a workflow in ComfyUI. It should appear within the next refresh interval.

An empty connected queue displays zero jobs. A disconnected app also shows zero, so check the connection indicator in the panel. You can inspect the endpoint independently:

```sh
curl --fail http://127.0.0.1:8188/queue
```

### 4. Enable node progress (optional)

Queue monitoring works without this step. To show the current node and its percentage, install the included extension into the **ComfyUI installation actually serving your endpoint**:

```sh
bash install-comfyui-extension.sh /path/to/ComfyUI
```

For paths containing spaces, quote the path:

```sh
bash install-comfyui-extension.sh "$HOME/AI Tools/ComfyUI"
```

Wait for active generation to finish, then restart ComfyUI. Test the extension:

```sh
curl --fail http://127.0.0.1:8188/comfyqueuebar/queue-progress
```

A response containing null values is normal before any progress is reported. During a job, the app displays progress only if the returned prompt ID matches the running job.

**The percentage describes the current node, not the whole workflow.** It may restart for each node. Some nodes do not emit fractional progress.

For remote servers, install the extension on the server, not just on the Mac. See [remote setup](docs/REMOTE_SETUP.md) for SSH, file transfer, and Windows instructions.

## Install as a regular app

After building, copy `build/ComfyQueueBar.app` into your user's Applications folder:

```sh
mkdir -p "$HOME/Applications"
cp -R build/ComfyQueueBar.app "$HOME/Applications/"
open "$HOME/Applications/ComfyQueueBar.app"
```

Quit an existing instance before replacing it. To launch at login, add the copied app through macOS **System Settings → General → Login Items** (the exact label can vary by macOS version). The app does not register itself automatically.

## What queue actions do

**Prioritize** resubmits the selected workflow with `front: true`, then deletes the original waiting entry. Its prompt ID changes. It does not interrupt the running job. This is a multi-request operation, so race conditions and duplicate entries are possible if the server disconnects or the original starts while the action is in progress. The app attempts recovery and reports IDs when it cannot confirm the result. Review the queue before retrying.

**Stop** sends `/interrupt` with the selected running prompt ID after rechecking the queue. It does not clear waiting jobs. A compatible server interrupts that prompt, and the next waiting job can start. Older servers may ignore the ID and apply a global interrupt; use a compatible ComfyUI version before relying on targeted behavior.

Prioritization preserves the prompt graph and the `extra_data` available through `/queue`. It cannot preserve private server fields or submission options not returned by that API. Workflows with external side effects or paid API nodes deserve particular care when resubmitting. See the [full usage guide](docs/USAGE.md).

## Privacy and connectivity

The app sends requests only to the configured ComfyUI address. It contains no analytics, telemetry, cloud account, or update checker. The endpoint is stored in macOS user defaults. ComfyUI may include workflow metadata in queue responses.

The progress extension adds a read-only JSON route on the ComfyUI server and observes progress through ComfyUI's internal progress registry. It does not open a WebSocket or modify queue contents. It wraps an internal reset function to re-register the observer for each prompt.

The extension route inherits the server's network exposure; it is **not automatically restricted to localhost**. Keep ComfyUI on a trusted network or use SSH forwarding. The app has no custom API-key, bearer-token, or login UI. Query-string credentials are not supported because request URLs discard the query and fragment. See [security guidance](SECURITY.md).

## Documentation

- [Usage and action semantics](docs/USAGE.md)
- [Remote ComfyUI and SSH tunnels](docs/REMOTE_SETUP.md)
- [Troubleshooting, updates, and uninstalling](docs/TROUBLESHOOTING.md)
- [Architecture, API reference, tests, and compatibility](docs/DEVELOPMENT.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## License and acknowledgments

MIT licensed. See [LICENSE](LICENSE).

Originally extracted from a production helper in the AniClayFilm repository, used for [Clay Trouble](https://www.youtube.com/@ClayTrouble). This standalone edition has an English interface and documentation, its own app identifier, and its own progress endpoint. It does not include film assets, workflows, models, or credentials.

[ComfyUI](https://github.com/Comfy-Org/ComfyUI) is a separate project. ComfyQueueBar is an independent community tool and is not an official ComfyUI product. No ComfyUI source code is bundled.
