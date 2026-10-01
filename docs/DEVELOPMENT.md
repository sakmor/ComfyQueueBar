# Development and API reference

## Repository layout

```text
Package.swift                              Swift executable package
Sources/ComfyQueueBar/main.swift            View model, API client, and SwiftUI UI
assets/                                    App icon and artwork provenance
build-app.sh                               Release app bundle and icon builder
install-comfyui-extension.sh               Non-overwriting extension installer
comfyui_extension/ComfyQueueBarProgress/    ComfyUI-side Python observer
scripts/check.sh                          Local verification entry point
scripts/capture-screenshots.sh             Native documentation captures
tests/                                    Isolated extension and installer tests
docs/                                     User and developer guides
.github/workflows/ci.yml                   Automated build and test checks
```

Build outputs are ignored by Git. Do not commit credentials, workflow exports, generated media, or local server addresses.

## Build and validate

```sh
swift build -c release
bash build-app.sh
bash scripts/check.sh
```

The check script builds the app, validates its signature and bundle metadata, checks Bash syntax, and runs Python standard-library unit tests. Tests stub ComfyUI and aiohttp imports, so they need no GPU, models, running ComfyUI server, or pip packages. They cover progress calculation, reset and registration, route response, and installer refusal to overwrite an existing installation.

These checks do not run an actual generation, prove compatibility with every server version, or exercise all UI and network race conditions. For integration testing, use a disposable ComfyUI instance with inexpensive workflows. Do not test stop or prioritize against valuable production jobs.

GitHub Actions runs the same checks on macOS for pushes and pull requests. Its build is architecture-specific to the runner.

## Architecture

`QueueViewModel` runs on the main actor. Two timers schedule asynchronous HTTP refreshes. The app polls `/queue` every four seconds; when connected with a running job, it polls the progress bridge every second. A missing progress route is retried during the ordinary queue refresh. Separate guards prevent overlapping queue and progress refreshes. Action guards serialize queue mutations inside this app, but cannot serialize other clients.

`URLSession` sends JSON requests with an eight-second timeout. The endpoint must have an HTTP or HTTPS scheme and a host. API paths are appended to its base path; query and fragment components are discarded. Non-2xx responses produce an HTTP error with a short response-body excerpt. The app stores only the endpoint preference in user defaults.

Queue parsing expects ComfyUI's array entries: queue number, prompt ID, prompt graph, and extra data, with additional server fields ignored. Titles use workflow metadata, then node metadata, then output prefixes. The app shows a single current progress snapshot only when its prompt ID matches the first running job.

The extension uses a lock around its most recent snapshot. It wraps `execution.reset_progress_state`, resets its snapshot, invokes the original reset, and registers a `ProgressHandler` in the new registry. Start/update/finish callbacks record a node's state. It leaves ComfyUI's WebSocket delivery in place. This relies on internal APIs and may interact with other extensions wrapping the same reset function.

## HTTP API usage

| Method | Path | Purpose / body |
| --- | --- | --- |
| GET | `/queue` | Read `queue_running` and `queue_pending` |
| POST | `/prompt` | Resubmit with `prompt`, `extra_data`, and `front: true` |
| POST | `/queue` | Delete a pending entry with `{"delete": ["prompt-id"]}` |
| POST | `/interrupt` | Request interruption with `{"prompt_id": "prompt-id"}` |
| GET | `/comfyqueuebar/queue-progress` | Read optional node progress |

A populated progress response has this shape (illustrative values):

```json
{
  "prompt_id": "example-prompt-id",
  "node_id": "12",
  "value": 15.0,
  "max": 30.0,
  "percent": 50.0,
  "state": "running"
}
```

All fields may be null before a snapshot exists. Percent is clamped to 0–100 and rounded to one decimal place. A zero maximum or an initial 0/1 state produces no percentage; a completed 1/1 state can produce 100%. `state` follows ComfyUI's state value and is not interpreted as whole-workflow completion.

The original project route and bundle identifier are intentionally replaced in this edition. Install the bundled extension rather than relying on the older AniClayFilm helper.

## ComfyUI compatibility

There is no declared minimum ComfyUI release number because an exact oldest compatible release has not been established. Required capabilities are listed in the main README. The API assumptions were reviewed against upstream source on 2026-10-01:

- [ComfyUI server routes](https://github.com/Comfy-Org/ComfyUI/blob/master/server.py): queue reads, front submission, queue deletion, and interruption accepting `prompt_id`.
- [Progress registry and handler](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy_execution/progress.py).
- [Execution implementation](https://github.com/Comfy-Org/ComfyUI/blob/master/execution.py): progress-state reset used by the observer.

These are moving upstream links, not a promise of compatibility with every future revision. Queue-only mode may work where the progress extension does not. A successful interrupt response does not establish whether an older server honored the ID. Hosted services, login proxies, private API-node metadata, and custom distributions may need changes beyond this tool's current capabilities.

## Manual release checklist

1. Run `bash scripts/check.sh` on the target Mac.
2. Verify the English UI, disconnected state, idle queue, running and waiting jobs, missing extension, and node progress.
3. Test prioritize and stop on disposable jobs, including the original job starting during a prioritize action and connection loss.
4. State tested macOS, architecture, and ComfyUI version in release notes; distinguish automated checks from live integration tests.
5. Keep `.build/` and `build/` out of Git. If publishing an app archive, label its architecture and signing/notarization status accurately.

No automatic updater, packaging service, signing certificate, or notarization credentials are included.

## Branding and interface captures

The app bundle contains an `.icns` icon generated from `assets/app-icon.png`, plus the full-color panel icon. The menu bar uses a code-drawn template image so macOS can adapt it to the menu bar appearance. See [asset provenance](../assets/README.md).

Run `bash scripts/capture-screenshots.sh` in a graphical macOS session to regenerate the README images. A separate compile-time build uses the actual panel with fixed sample data and disables network access. Use `bash scripts/capture-screenshots.sh --desktop-demo` to show the same panel beneath a native status item for an operating-system context capture. Production builds contain neither that capture entry point nor its demonstration data. See [screenshot provenance](images/README.md).

## Localization

`L10n` in `Sources/ComfyQueueBar/main.swift` holds app-owned strings for English, `zh-Hans`, `zh-Hant`, and Japanese. The app bundle declares these languages. Preferred language resolution respects explicit Chinese scripts before regional fallbacks. Dynamic values use `%@` placeholders; workflow and node names remain server-owned text. `bash scripts/check-localization.sh` checks language selection, translation completeness, placeholder parity, formatting, and fallback behavior.

Documentation builds default to English regardless of the system language. For local visual checks only, set `COMFYQUEUEBAR_PREVIEW_LANGUAGE=ja`, `zh-Hant`, or `zh-Hans` when running the documentation capture executable with a temporary output path. Production builds ignore this environment variable.
