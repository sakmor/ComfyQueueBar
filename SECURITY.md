# Security and privacy

ComfyQueueBar can read workflow metadata, resubmit jobs, delete selected waiting entries, and interrupt generation on its configured server. Use it only with servers you control or are authorized to operate.

The app has no analytics or telemetry. It stores the server address, named server bookmarks, notification settings, and Sparkle update preferences in macOS user defaults. Completion/error history stays in memory. Do not embed credentials in that address. No custom authentication-header UI is implemented.

Optional Wake-on-LAN settings store a target network-interface MAC address, IPv4 destination, UDP port, and automatic-wake preference in the corresponding local server bookmark. Manual wake sends a UDP magic packet to that configured destination. Automatic wake is disabled by default; when enabled, qualifying network failures for the selected server can send a packet at most once every two minutes. It does not change remote power settings, firewall rules, router configuration, or GPUtw rental state. Packet transmission does not confirm that the target woke or that ComfyUI started.

The GPUtw sign-in window uses this app's persistent WebKit website data store. It can hold GPUtw account/instance cookies and identity-provider browsing data; it does not read Safari or Chrome's sessions. Cookies are not written to UserDefaults, server profiles, logs or agent bridge files. Saved GPUtw endpoints contain only the HTTPS instance origin, never handoff query tokens. Monitoring and media requests use an ephemeral URLSession with automatic cookie storage disabled; matching unexpired browser cookies are attached only to GPUtw service HTTPS requests. Redirects are refused to prevent replaying credentials or POST bodies to another destination. Cookie updates from a service may only update that service host, not account-wide cookies. Clearing GPUtw sign-in invalidates in-flight authenticated results and deletes the app's WebKit browsing data. It does not revoke other devices' sessions or stop the instance.

The optional extension exposes node IDs, prompt IDs, and progress over the existing ComfyUI HTTP server. It adds no authentication or loopback-only enforcement. Its accessibility follows ComfyUI and reverse-proxy configuration. Use localhost, a trusted private network, or SSH forwarding; avoid exposing the queue and control APIs to the public internet.

Server error excerpts may be displayed in the app. Sanitize screenshots, logs, and issue reports before publishing them. Never include API keys, SSH keys, private prompts, or private server details in a public issue.

For vulnerabilities, use GitHub's **Report a vulnerability** option on the repository's Security tab when available. Do not publish exploitation details in public issues. No response-time guarantee is offered.

## Output media and notifications

Output previews and downloads use the configured ComfyUI `/view` route. The app uses native image decoding and AVKit playback, with no automatic playback or execution of downloaded files. Downloads go only to a destination selected through a native save dialog. Thumbnails may request media while the panel is visible. Outputs and workflow metadata are not uploaded elsewhere.

For GPUtw video previews, the app downloads a temporary local copy through its authenticated transport before AVKit playback, keeping cookies out of the player's independent redirect handling. The temporary copy is deleted on preview change/close; an abnormal process exit may leave it in the system temporary directory. GPUtw video thumbnails use a placeholder rather than fetching entire videos. Image previews and explicit downloads use the same scoped transport.

Notifications are disabled by default and require macOS permission. Enabled alerts can show workflow names, server names, and failure text on the desktop or lock screen according to your system settings.

## Update security

Sparkle 2.10.0 checks the HTTPS GitHub-hosted appcast. Feed signatures are required without an expiration fallback, and archive signatures are verified before extraction using the embedded Ed25519 public key. Automatic updates can be disabled in the panel. System profiling is disabled. GitHub can observe update requests (including ordinary network and updater headers). The app remains ad-hoc signed and is not Apple-notarized.

The private update key stays in the maintainer’s macOS Keychain under account `io.github.sakmor.comfyqueuebar`; it is never committed or embedded. Losing this key requires manual migration for these non-Developer-ID-signed builds.

## Optional agent integration

AI agent integration is disabled by default. Enabling it stores the selected endpoint, queue IDs, subscribed output references and error text in the current user's Application Support directory. Directories/files use 0700/0600 permissions. The app exports no workflow graphs or prompt text and opens no listening port. All programs running as the same macOS user can access this data; it is not an isolation boundary between same-user agents.

MCP clients submit validated, bounded JSON command files; only the app writes subscriptions and durable events. No callback URLs, shell commands or continuation instructions are executed by this bridge. Treat filenames, labels and ComfyUI errors as untrusted data. Standard MCP has no idle conversation wakeup. Optional Claude channel mode requires a verified inbound probe and explicit task-event acknowledgments; transport writes do not prove delivery. It does not relay permission approvals.

Disabling integration preserves state for recovery. To erase saved data, disable integration and remove `~/Library/Application Support/ComfyQueueBar/AgentBridge`. See [agent integration limitations](docs/AGENT_INTEGRATION.md).

The explicit **Set up Claude and Codex** button updates local agent MCP registration, first backing up existing configuration files. It preserves other settings, leaves invalid Claude JSON unchanged, and uses the installed Codex CLI for TOML edits. Registration copies the bundled adapter to a stable same-user Application Support path. Setup invokes Python version checks and the Codex registration command, with no model inference, prompt submission, or permission bypass.
