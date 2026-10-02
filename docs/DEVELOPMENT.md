# Development and API reference

## Repository layout

```text
Package.swift                              Swift executable package
Sources/ComfyQueueBar/main.swift            View model, API client, localization, panel
Sources/ComfyQueueBar/Features.swift        History models, notifications, native media UI
Sources/ComfyQueueBar/AgentBridge.swift     Durable same-user subscription IPC
Sources/ComfyQueueBar/AgentSetup.swift      User-triggered MCP registration, shared Skill installation, and backups
agent_bridge/server.py                    Local stdio MCP / optional Claude channel adapter
Sources/ComfyQueueBar/StatusBarController.swift Native status-item lifecycle and reopen window
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

The check script builds the app, validates its signature and bundle metadata, checks Bash syntax, checks all four localizations and pure Swift history/feature models, and runs Python standard-library unit tests. Tests stub ComfyUI and aiohttp imports, so they need no GPU, models, running ComfyUI server, or pip packages. They cover progress calculation, reset and registration, route response, and installer refusal to overwrite an existing installation.

These checks do not run an actual generation, prove compatibility with every server version, or exercise all UI and network race conditions. For integration testing, use a disposable ComfyUI instance with inexpensive workflows. Do not test stop or prioritize against valuable production jobs.

`bash scripts/check-network.sh` exercises the production queue view model and HTTP request construction with an intercepting `URLProtocol` and isolated temporary preferences. It checks base paths, bounded history requests, matching/missing progress, history failure isolation, prioritize submission and cleanup, the original job starting during resubmission, refused deletion, connection loss after submission, stale action targets, targeted stop, idle/disconnected states, and invalid endpoints. All requests are intercepted; these are simulated API regressions, not live ComfyUI generation tests. Like the history/localization checks, the harness extracts production declarations; only its preferences store is replaced.

GitHub Actions runs the same checks on macOS for pushes and pull requests. Its build is architecture-specific to the runner.

## Architecture

`QueueViewModel` runs on the main actor. Two timers schedule asynchronous HTTP refreshes. The app polls `/queue` every four seconds; when connected with a running job, it polls the progress bridge every second. A missing progress route is retried during the ordinary queue refresh. Separate guards prevent overlapping queue and progress refreshes. Action guards serialize queue mutations inside this app, but cannot serialize other clients.

`URLSession` sends JSON requests with an eight-second timeout. The endpoint must have an HTTP or HTTPS scheme and a host. API paths are appended to its base path; query and fragment components are discarded. Non-2xx responses produce an HTTP error with a short response-body excerpt. The app stores the endpoint, Codable server bookmarks, notification settings, and Sparkle update preferences in user defaults. Endpoint generations prevent late responses from contaminating a new server view.

Queue parsing expects ComfyUI's array entries: queue number, prompt ID, prompt graph, and extra data, with additional server fields ignored. Titles use workflow metadata, then node metadata, then output prefixes. The app shows a single current progress snapshot only when its prompt ID matches the first running job.

The extension uses a lock around its most recent snapshot. It wraps `execution.reset_progress_state`, resets its snapshot, invokes the original reset, and registers a `ProgressHandler` in the new registry. Start/update/finish callbacks record a node's state. It leaves ComfyUI's WebSocket delivery in place. This relies on internal APIs and may interact with other extensions wrapping the same reset function.

## HTTP API usage

| Method | Path | Purpose / body |
| --- | --- | --- |
| GET | `/queue` | Read `queue_running` and `queue_pending` |
| GET | `/history?max_items=200` | Bounded success/error history |
| GET | `/view?filename=…&subfolder=…&type=…` | Output media / native preview / download |
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

Automatic updates use Sparkle and the signed appcast described below. No Apple Developer ID certificate or notarization credentials are included.

## Branding and interface captures

The app bundle contains an `.icns` icon generated from `assets/app-icon.png`, plus the full-color panel icon. The menu bar uses a code-drawn template image so macOS can adapt it to the menu bar appearance. See [asset provenance](../assets/README.md).

Run `bash scripts/capture-screenshots.sh` in a graphical macOS session to regenerate the README images. A separate compile-time build uses the actual panel with fixed sample data and disables network access. Use `bash scripts/capture-screenshots.sh --desktop-demo` to show the same panel beneath a native status item for an operating-system context capture. Production builds contain neither that capture entry point nor its demonstration data. See [screenshot provenance](images/README.md).

## Localization

`L10n` in `Sources/ComfyQueueBar/main.swift` holds app-owned strings for English, `zh-Hans`, `zh-Hant`, and Japanese. The app bundle declares these languages. Preferred language resolution respects explicit Chinese scripts before regional fallbacks. Dynamic values use `%@` placeholders; workflow and node names remain server-owned text. `bash scripts/check-localization.sh` checks language selection, translation completeness, placeholder parity, formatting, and fallback behavior.

Documentation builds default to English regardless of the system language. For local visual checks only, set `COMFYQUEUEBAR_PREVIEW_LANGUAGE=ja`, `zh-Hant`, or `zh-Hans` when running the documentation capture executable with a temporary output path. Production builds ignore this environment variable.

## Publishing signed updates

Sparkle 2.10.0 is the app’s update dependency, pinned in `Package.resolved`. It is bundled with its license and helper services; the build preserves symlinks and adds the framework runtime search path. Screenshots compile without Sparkle and make no update requests.

1. Increase both bundle versions in `build-app.sh`, update the changelog, and run `bash scripts/check.sh`.
2. Run `bash scripts/package-release.sh` on the Apple Silicon signing Mac. It reads the existing Ed25519 key from macOS Keychain (account `io.github.sakmor.comfyqueuebar`) and signs both the ZIP and `appcast.xml`. Do not generate a replacement key.
3. Commit source changes and tag the exact build commit. Upload ZIP and SHA256SUMS.txt from `build/releases/VERSION` to the matching GitHub Release.
4. Publish the signed `appcast.xml` to main only after release assets exist. Never edit the generated signed feed; regenerate it.

A CI build needs no signing private key and does not publish updates. The appcast uses absolute version-specific release URLs. Private key backup/transfer should use Sparkle’s documented Keychain workflow, outside Git.

## History and feature models

`CompletionHistory` accepts only `completed: true` and `status_str: success`, rejecting error/interruption events. Finish time comes from an `execution_success` millisecond timestamp; start time uses `execution_start`. Production fetches 200 records and applies the selected time range client-side. Unknown timestamps appear only in Loaded history. Output references retain filename, subfolder, and type; temporary previews are excluded.

`HistoryDetails` parses errors/interruptions, builds query-encoded output URLs preserving a server base path, and computes graph fingerprints and median duration estimates. `NotificationTracker` suppresses the initial history baseline, deduplicates prompt IDs, and accumulates completion/failure counts for a drained queue. It also handles jobs that start and finish between queue polls. Seen IDs are bounded to avoid unbounded memory.

`bash scripts/check-history.sh` tests success/error filtering, millisecond timestamps, ordering, legacy parser limits, media metadata and URL encoding, time-range handling, profile Codable persistence, matching estimates with a three-sample minimum, and notification baseline/deduplication/batch behavior. Media uses AppKit and AVKit; notifications use UserNotifications. No extra runtime dependency is required.

A native localhost media smoke test during v1.4.0 validation exercised PNG decoding, AVPlayer readiness for a short H.264 MP4, video thumbnail extraction, byte-exact HTTP download, and missing-file error handling. This is a controlled fixture test, not a guarantee for every remote codec/server; native save-dialog interaction and actual macOS notification delivery require manual testing.

## Status-item lifecycle

The application delegate retains an NSStatusItem with a fixed 52-point width. Queue changes update its label asynchronously; the count caps at 99+ while the tooltip keeps the full value. Wake and display reconfiguration restore its visibility. An application-reopen event restores the item and shows the same queue model in an ordinary closable window. Closing that window orders it out without terminating the accessory app. macOS owns item placement, so this does not promise to defeat notch occlusion or menu-bar crowding. The documentation capture uses a separate demo wrapper; production uses the retained native item with a SwiftUI popover.

The v1.4.1 graphical regression check exercised opening/replacing/closing the standalone preview window, in addition to the localhost PNG/H.264 media smoke. It reproduced a missing AVKit AppKit superclass before explicit framework linkage; the build checks now verify that the shipping executable directly links AVKit. Reopening the installed application is checked separately to ensure the same process opens its fallback queue window.

## Agent bridge

The opt-in integration uses a single-writer subscription store and atomic same-user file IPC, not a TCP listener. A one-second main-actor timer processes commands and publishes a heartbeat independently of queue HTTP requests. Durable state writes occur only when subscription state changes. History ingestion records explicit terminal results and deduplicated events. Individual history lookups (up to eight concurrently per history cycle) recover unresolved subscribed IDs outside the UI history window. Endpoint-generation checks discard responses after server changes. Missing history never implies success.

The Python standard-library MCP adapter runs as each host's stdio subprocess. Tool requests run in a bounded thread pool so waits do not block cancellation or ping. Standard mode reports no idle wakeup; optional Claude channel mode requires a nonce-based inbound probe before events are forwarded. Explicit event acknowledgment persists in the app store. Only subscriptions created/resumed by that process are forwarded. See [Agent integration](AGENT_INTEGRATION.md) for configuration and actual host limitations.

`tests/test_agent_bridge.py` compiles `tests/check-agent-bridge.swift` with the production bridge, then tests real file IPC and stdio messages. The fixture uses temporary directories and never submits production jobs or invokes agents.

`AgentSetup` runs only from the setup button, off the main actor. It probes Python version, copies the adapter to a stable path, merges the Claude Desktop JSON configuration with a backup, and invokes `codex mcp add` to edit Codex TOML. The native CLI is used instead of a hand-written TOML parser. Each client's result is reported independently; commands have a ten-second timeout. Setup runs no model inference.

The current development verification record and pre-merge checklist are in [AI agent test progress](AGENT_TEST_PROGRESS.md). The feature remains on `codex/dev` until host/render validation and desktop delivery behavior are resolved.
