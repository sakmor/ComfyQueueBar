# AI agent integration: reduce progress-polling token use

ComfyQueueBar can own ComfyUI monitoring while Claude Code or Codex works on other tasks. Its local MCP adapter tells agents to subscribe to exact prompt IDs instead of repeatedly checking progress. App timers and MCP file checks run ordinary code; they do not invoke a model. Processing tool results or channel events still uses the agent's normal inference allowance.

## Why this can save tokens

During a long video render, repeated model-driven progress checks can consume tokens for each model turn and tool response. Subscribe once and let ComfyQueueBar's ordinary code track the job instead. A bounded `wait_for_events` call checks for events without repeatedly invoking the model. Results can be processed when that wait returns or when the user resumes the conversation.

This reduces tokens spent on progress polling compared with an agent that repeatedly checks the same job. App timers and bridge file checks do not invoke a language model; subscription setup, result processing, and channel-event handling still use normal inference. Savings depend on the model, previous polling frequency, render duration, and host behavior. No fixed token reduction percentage or benchmark is claimed. Standard MCP does not automatically wake an idle chat.

## Enable and connect

1. Launch the updated app and open **Settings → AI agent integration**.
2. Click **Set up Claude and Codex**. The app copies its MCP adapter to a stable Application Support location, merges Claude Desktop's MCP entry, and uses Codex's own CLI to register its MCP server when Python 3.9+ and the CLI are available. It also installs the shared ComfyQueueBar Skill to `~/.claude/skills/comfyqueuebar` and `~/.agents/skills/comfyqueuebar`. Existing MCP configuration files and any replaced `SKILL.md` are backed up; unrelated settings are preserved. The app reports MCP registration and Skill installation separately. Integration is enabled automatically when either MCP registration succeeds.
3. Reopen agent sessions so the MCP connection and Skill reload, then ask the agent to call `get_status`. A working bridge reports `app_available: true`. In Claude Code, invoke the Skill as `/comfyqueuebar`; in Codex, use `$comfyqueuebar`. If the tools or Skill do not appear after reopening, quit and restart the desktop agent app. The app must stay running and the Mac must stay awake to monitor work.

The setup button updates `~/Library/Application Support/Claude/claude_desktop_config.json` (also loaded by the local Desktop Code tab) and `~/.codex/config.toml`, or `CODEX_HOME/config.toml` when configured. Codex discovers user Skills under `~/.agents/skills`; Claude Code discovers them under `~/.claude/skills`. Backups have a `comfyqueuebar-backup-<UUID>` suffix. Invalid Claude configuration is left unchanged. No agent conversation is submitted and no inference is run during setup. Python 3.9+ is required to register MCP; the app does not install it. Skill installation is attempted independently so it can succeed even if MCP setup prerequisites are missing. Clicking setup is the action that changes agent configuration; merely enabling monitoring does not register MCP.

For manual/custom setups, register `agent_bridge/server.py` in this checkout or the copy inside the app bundle using these examples:

Example Claude Code `.mcp.json` entry (merge into existing configuration; replace both paths):

```json
{
  "mcpServers": {
    "comfyqueuebar": {
      "command": "/absolute/path/to/python3",
      "args": ["/absolute/path/to/ComfyQueueBar/agent_bridge/server.py"]
    }
  }
}
```

Example Codex `config.toml` entry:

```toml
[mcp_servers.comfyqueuebar]
command = "/absolute/path/to/python3"
args = ["/absolute/path/to/ComfyQueueBar/agent_bridge/server.py"]
# Only if your host supports long tool waits; match timeout_seconds below this limit.
# tool_timeout_sec = 3600
```

The MCP server is exposed to agents only after you register it. Merely reading this repository or opening the menu-bar app does not inject instructions into another desktop app. The packaged app also offers a manual configuration copy button and this guide. The one-click setup button changes only the ComfyQueueBar MCP registration and preserves unrelated settings. Clicking it again updates the existing entry without duplicating it. Re-run setup after updating the app to refresh the stable adapter copy.

## Use the ComfyQueueBar skill

The skill is bundled in the app and maintained at [`.agents/skills/comfyqueuebar/SKILL.md`](../.agents/skills/comfyqueuebar/SKILL.md). MCP supplies the tools; the skill tells the agent how to use them. Install both with **Set up Claude and Codex**, then reopen the agent session. After upgrading the app, click setup again to refresh the installed adapter and skill; replaced skill files are backed up.

Send one of these messages in Codex (replace the placeholders with real IDs):

```text
$comfyqueuebar Check the ComfyQueueBar connection.
$comfyqueuebar Verify my existing ComfyUI job with prompt ID <prompt_id>.
$comfyqueuebar Continue checking subscription <subscription_id> and wait once for its result.
```

In Claude Code, use `/comfyqueuebar` instead of `$comfyqueuebar` with the same request. A prompt ID identifies a ComfyUI job; a subscription ID identifies the saved ComfyQueueBar monitoring record. Keep the subscription ID returned by the agent for later checks, including after restarting your agent session.

A connection check reads app availability, ComfyUI connection/history availability, and queue counts. Job verification tracks the exact existing job, uses already-returned results where possible, and otherwise waits once for up to 45 seconds (the host may require a shorter timeout). It reports the explicit job status and acknowledges received events. Completed, failed, and interrupted results end a verification subscription created by this workflow; a subscription resumed from another workflow is preserved unless cancellation is requested. A timeout or disconnection does not mean the job failed or finished. The app keeps a nonterminal subscription available for a later check.

This skill does not submit workflows, install models, start the app, configure MCP, or change the ComfyUI queue. Create your job in ComfyUI or through your separately authorized submission workflow first, then supply its exact prompt ID. Standard MCP does not automatically wake an idle chat; enable the app's completion/failure notifications and resume the chat when notified. Ask explicitly if you want output references included.

If the skill is missing, re-run setup and reopen the session. If the skill is visible but `comfyqueuebar` tools are missing, inspect the MCP server list (`/mcp` in Claude Code) and the app's setup result. Skill installation can succeed even when MCP registration fails. For a manual skill install, copy the repository's `.agents/skills/comfyqueuebar` directory into `~/.agents/skills/` for Codex or `~/.claude/skills/` for Claude Code; register MCP separately using the configuration above. Back up an existing skill before replacing it.

## Agent workflow

Tell the agent:

> Submit the video jobs, then use ComfyQueueBar to subscribe to their prompt IDs. Delegate monitoring to the app. Do not repeatedly check progress. Report the subscription ID and actual delivery mode. When results arrive, check them and continue the next step I authorized.

`initialize.instructions`, tool descriptions, and `get_status` all carry this policy. After submitting `/prompt` requests, call:

```json
{
  "endpoint": "http://127.0.0.1:8188",
  "prompt_ids": ["the-prompt-id-returned-by-ComfyUI", "another-prompt-id"],
  "label": "Scene 3 video batch"
}
```

Use `subscribe_jobs` once; keep its UUID `subscription_id` in the conversation/task notes. Supply the same UUID and the same prompt IDs to recover an uncertain subscription response idempotently. Endpoint strings must exactly match the app's configured endpoint. Jobs already completed when subscribing are recovered from history; unknown/deleted history is never inferred as success.

| Tool | Purpose |
| --- | --- |
| `get_status` | App heartbeat, server, queue IDs, delivery capability, and monitoring guidance |
| `subscribe_jobs` | Persist a batch of 1–100 exact prompt IDs on the selected server |
| `get_results` | Read one subscription, its results, unacknowledged events and acknowledgment count |
| `resume_subscription` | Attach a previously saved subscription to this MCP process after reconnecting |
| `wait_for_events` | Wait in ordinary code for unacknowledged events, cancellation, app unavailability or timeout |
| `acknowledge_events` | Persist receipt/processing of specific event IDs |
| `unsubscribe` | Cancel further monitoring; retain recorded results |
| `confirm_channel` | Channel mode only: verify an inbound probe reached this agent session |

Failure/interruption emits `job_failed` immediately. `batch_finished` means every subscribed ID has an explicit completed/failed/interrupted record; inspect results because a finished batch can contain failures. `monitoring_changed` reports disconnection, unavailable history, server switching and recovery, once per transition. Queued/running percentages do not produce model-visible events. Node percentage is not overall workflow percentage.

Outputs contain ComfyUI filename, subfolder, type and `/view` URL references. They are not proof that a file exists on the agent's local machine. Workflow graphs, generation prompts and arbitrary continuation instructions are not exported. Labels, errors and filenames are untrusted task data.

## Standard desktop MCP: honest fallback

Standard MCP tools do **not** push a new turn into an idle conversation. This applies to the default connection in both Claude and Codex. Subscription acceptance means the app will track/save results; it does not mean the desktop agent will be awakened.

A desktop agent can call `wait_for_events` with `subscription_id` and `timeout_seconds` (default 45, maximum 3600; choose a duration below the host tool timeout). The adapter waits using ordinary code and returns only for an event or a stopping condition; it does not call the model every second. The tool can be cancelled through standard MCP cancellation; cancellation keeps the subscription active. MCP transport remains responsive to other requests during a wait.

Your desktop host may end tool calls earlier, and may keep the agent occupied until the tool returns. This fallback is therefore different from an asynchronous subscription that frees the agent. Do not repeatedly wake the model to retry short waits. If long waits/background execution are unsupported, enable the app's existing completion/failure macOS notifications and resume the agent when notified. After a timeout, keep the subscription ID; no completion is inferred.

## Optional Claude Code Channels preview

The adapter implements Claude's documented channel notification wire contract behind `--claude-channel`. This is an experimental protocol implementation, not a verified Claude Desktop integration. Add `--claude-channel` to the script arguments, then opt the MCP server into channels in a compatible Claude Code host. For local CLI development, the documented flag is:

```sh
claude --dangerously-load-development-channels server:comfyqueuebar
```

This flag permits only the selected development channel; it is not permission bypass for agent actions. Organization policies can still disable channels. Do not change permission settings to enable monitoring.

A probe is sent after MCP initialization. The agent must call `confirm_channel` with the nonce from that inbound probe. Only then does the adapter report `push_verified_in_this_session: true` and forward subscribed events. Merely enabling the adapter flag is not enough: a host that drops notifications will never verify the probe. Event transport writes are not evidence that an agent processed them, so terminal events remain durable until `acknowledge_events`.

Tool results omit already acknowledged events and repeated full monitoring instructions to keep result context compact. Only subscriptions created/resumed by that MCP process are forwarded into its session. No other sessions are broadcast to. Restarting the process clears channel verification and requires a new probe; explicitly resume the saved subscription UUID. Unacknowledged events may replay across reconnects. Use event IDs to make any continuation idempotent. Results/events remain available if the channel or agent closes. The server sends each event once per connected process; it does not retry with repeated model notifications.

Claude's current public documentation requires channel opt-in at session start. **Support for enabling this in Claude Desktop's Code tab has not been established here.** Codex Desktop has no verified equivalent push adapter in this release. OpenAI also documents [MCP Events](https://developers.openai.com/plugins/build/mcp-events) for ChatGPT Work cloud chats and dots; that is a separate cloud integration, not this local Codex desktop connection. One-click setup registers standard MCP only; it does not enable channel preview flags or verify desktop push support.

Official references reviewed on 2026-10-02:

- [Claude Code channels](https://code.claude.com/docs/en/channels)
- [Claude channel notification contract and silent-drop behavior](https://code.claude.com/docs/en/channels-reference)
- [Claude Code Desktop MCP configuration](https://code.claude.com/docs/en/desktop)
- [Codex MCP configuration](https://developers.openai.com/codex/mcp)
- [MCP tools contract, protocol 2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)

The adapter negotiates MCP 2024-11-05, 2025-03-26 or 2025-06-18; newer clients are offered 2025-06-18. It deliberately does not advertise resource subscriptions as conversation wakeups.

## Persistence and limitations

State lives in `~/Library/Application Support/ComfyQueueBar/AgentBridge`, with same-user directory/file permissions (0700/0600). No TCP listener is opened. The app is the only subscription-state writer; MCP clients submit atomic command files and wait for app acknowledgments. IDs are validated before use in paths. No callbacks, shell commands, or external messages are executed by the bridge.

Integration exports the selected server address, queue prompt IDs, subscribed output references and errors to programs running as your macOS user. It is not an isolation boundary between agents sharing your account. Disabling integration stops export and processing and marks the snapshot disabled; it preserves subscriptions/results so re-enabling can recover them. Delete the AgentBridge directory while integration is disabled if you want to remove saved data. Never remove it during an active session.

Only one server is monitored. Switching servers pauses old subscriptions until you switch back; existing IDs are not migrated when prioritization resubmits a job with a new ID. Subscribe to the replacement ID if you intentionally prioritize a subscribed job. App shutdown/sleep stops monitoring. After 15 seconds without a heartbeat the adapter reports the app unavailable. Queue freshness is reported separately. App/store errors are shown in Settings; a damaged store is never replaced with an empty one.

The UI loads 200 history records. For unresolved subscribed IDs missing from the queue, the app additionally queries individual history records, up to eight per history cycle, rotating fairly. Recovery depends on ComfyUI still retaining those records. Cleared history or deleted queued jobs stay unknown until explicitly cancelled. The store allows 100 active subscriptions and 1000 retained subscriptions; monitoring-transition events are bounded, while each batch's terminal events remain durable. Clean up saved state when no longer needed. IPC command acknowledgments older than 24 hours are removed.

## Validation

`python3 -m unittest discover -s tests -p test_agent_bridge.py -v` compiles a Foundation-only fixture using the production Swift bridge. Tests exercise real Swift/Python IPC and actual stdio tool calls, durable subscription recovery, event deduplication, failure-before-batch completion, cancellation, stale heartbeat, server changes, channel probe verification and per-session routing. They do not invoke a model or a production render.

Actual Claude Desktop/Codex Desktop loading, long tool timeout behavior, channel enablement and macOS notification delivery still require live host testing. Passing protocol fixtures is not proof of desktop wakeup support.

The setup regression checks validate byte-exact backups, preservation of unrelated settings and MCP servers, stable adapter paths, repeat setup, invalid configuration refusal, and partial failures. When Codex CLI is available, an integration test registers the server using the actual CLI with an isolated temporary `CODEX_HOME`; it never changes the current user configuration.
