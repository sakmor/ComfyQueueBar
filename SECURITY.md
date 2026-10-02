# Security and privacy

ComfyQueueBar can read workflow metadata, resubmit jobs, delete selected waiting entries, and interrupt generation on its configured server. Use it only with servers you control or are authorized to operate.

The app has no analytics or telemetry. It stores the server address, named server bookmarks, notification settings, and Sparkle update preferences in macOS user defaults. Completion/error history stays in memory. Do not embed credentials in that address. No custom authentication-header UI is implemented.

The optional extension exposes node IDs, prompt IDs, and progress over the existing ComfyUI HTTP server. It adds no authentication or loopback-only enforcement. Its accessibility follows ComfyUI and reverse-proxy configuration. Use localhost, a trusted private network, or SSH forwarding; avoid exposing the queue and control APIs to the public internet.

Server error excerpts may be displayed in the app. Sanitize screenshots, logs, and issue reports before publishing them. Never include API keys, SSH keys, private prompts, or private server details in a public issue.

For vulnerabilities, use GitHub's **Report a vulnerability** option on the repository's Security tab when available. Do not publish exploitation details in public issues. No response-time guarantee is offered.

## Output media and notifications

Output previews and downloads use the configured ComfyUI `/view` route. The app uses native image decoding and AVKit playback, with no automatic playback or execution of downloaded files. Downloads go only to a destination selected through a native save dialog. Thumbnails may request media while the panel is visible. Outputs and workflow metadata are not uploaded elsewhere.

Notifications are disabled by default and require macOS permission. Enabled alerts can show workflow names, server names, and failure text on the desktop or lock screen according to your system settings.

## Update security

Sparkle 2.10.0 checks the HTTPS GitHub-hosted appcast. Feed signatures are required without an expiration fallback, and archive signatures are verified before extraction using the embedded Ed25519 public key. Automatic updates can be disabled in the panel. System profiling is disabled. GitHub can observe update requests (including ordinary network and updater headers). The app remains ad-hoc signed and is not Apple-notarized.

The private update key stays in the maintainer’s macOS Keychain under account `io.github.sakmor.comfyqueuebar`; it is never committed or embedded. Losing this key requires manual migration for these non-Developer-ID-signed builds.

## Optional agent integration

AI agent integration is disabled by default. Enabling it stores the selected endpoint, queue IDs, subscribed output references and error text in the current user's Application Support directory. Directories/files use 0700/0600 permissions. The app exports no workflow graphs or prompt text and opens no listening port. All programs running as the same macOS user can access this data; it is not an isolation boundary between same-user agents.

MCP clients submit validated, bounded JSON command files; only the app writes subscriptions and durable events. No callback URLs, shell commands or continuation instructions are executed by this bridge. Treat filenames, labels and ComfyUI errors as untrusted data. Standard MCP has no idle conversation wakeup. Optional Claude channel mode requires a verified inbound probe and explicit task-event acknowledgments; transport writes do not prove delivery. It does not relay permission approvals.

Disabling integration preserves state for recovery. To erase saved data, disable integration and remove `~/Library/Application Support/ComfyQueueBar/AgentBridge`. See [agent integration limitations](docs/AGENT_INTEGRATION.md).

The explicit **Set up Claude and Codex** button updates local agent MCP registration, first backing up existing configuration files. It preserves other settings, leaves invalid Claude JSON unchanged, and uses the installed Codex CLI for TOML edits. Registration copies the bundled adapter to a stable same-user Application Support path. Setup invokes Python version checks and the Codex registration command, with no model inference, prompt submission, or permission bypass.
