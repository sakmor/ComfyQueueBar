# Let the app monitor renders: an agent token-saving tutorial

[English](AGENT_TOKEN_GUIDE.md) · [简体中文](i18n/AGENT_TOKEN_GUIDE.zh-CN.md) · [繁體中文](i18n/AGENT_TOKEN_GUIDE.zh-TW.md) · [日本語](i18n/AGENT_TOKEN_GUIDE.ja.md)

Video generation can take minutes or longer. When an agent starts a new model turn every few seconds to check and interpret progress, waiting can consume tokens. ComfyQueueBar monitors the specified job in the app; the agent handles subscription setup and results when an event arrives or you resume the chat.

**Use this when you already have a ComfyUI video job and want to know when it finishes without repeated agent progress checks.** Image jobs work too.

## 1. Install the app, MCP, and skill

1. Download the latest Apple Silicon app from [GitHub Releases](https://github.com/sakmor/ComfyQueueBar/releases/latest). Requires macOS 13 or later; Intel users can [build from source](../README.md#build-from-source).
2. Open the app, enter your ComfyUI address in the gear settings, and connect. Remote servers can use [SSH forwarding](REMOTE_SETUP.md).
3. Enable **AI agent integration** and click **Set up Claude and Codex**. The MCP adapter needs Python 3.9+; automatic Codex registration needs an available Codex CLI.
4. Read the setup results. MCP registration and skill installation are reported separately: installing the skill does not prove MCP is connected.
5. Reopen your agent session. If tools remain missing, restart the agent desktop app.

Setup installs the adapter and shared skill and backs up replaced configuration/skill files. After upgrading ComfyQueueBar, run setup again and reopen your agent session.

Keep the app running and the Mac awake. Monitoring pauses during sleep, app shutdown, or disabled integration.

## 2. Check the connection first

Paste into Codex:

```text
$comfyqueuebar Check the connection and tell me whether the app, ComfyUI, and history are available.
```

For Claude Code:

```text
/comfyqueuebar Check the connection and tell me whether the app, ComfyUI, and history are available.
```

Expect app availability, ComfyUI connection/history availability, and running/pending counts. Zero jobs may simply mean an empty queue; use the connection state to distinguish it.

This reads status once, without submitting a job or creating a subscription.

## 3. Get the correct prompt ID

`prompt_id` is the full identifier ComfyUI assigns to one job submission. It is not a workflow name, filename, node ID, or generation prompt text.

- **Submitted by an agent or script:** use the full `prompt_id` in ComfyUI's `/prompt` response. If that submission ID is already in the conversation, ask the agent to use it.
- **Submitted through ComfyUI's interface:** find that submission's `/prompt` request in your browser developer tools' Network panel and read `prompt_id` in its JSON response. Check that the submission time matches your job.
- **Already running or queued:** in `/queue`, the second field of each job array in `queue_running` or `queue_pending` is its full ID. Identify the correct job first; do not assume the first entry is yours.

The app may display shortened IDs. Do not subscribe using a shortened ID. Replace `YOUR_PROMPT_ID` below with your real full ID.

## 4. Subscribe once and let the app monitor

Paste into Codex:

```text
$comfyqueuebar Verify my already-submitted ComfyUI video job with prompt ID YOUR_PROMPT_ID.
Subscribe only to this job and wait once; do not repeatedly check progress.
Report its actual status and subscription_id so I can resume later.
```

In Claude Code, replace `$comfyqueuebar` on the first line with `/comfyqueuebar`.

The agent checks the connection, subscribes using the endpoint returned by the app, and retains `subscription_id`. If a terminal result is already available, it handles it directly. Otherwise it normally waits once for up to 45 seconds; the host may require a shorter wait.

Ordinary code checks for events during this wait without calling a model every second. The agent still needs inference to interpret the returned tool result.

| Status | Meaning | Next step |
| --- | --- | --- |
| queued | Waiting in the queue | Save the subscription ID and check later |
| running | Executing | Let the app monitor and check later |
| completed | Explicitly completed | Request output references or inspect the video |
| failed / interrupted | Explicit failure or interruption | Read the error and decide what to do |
| unknown | Not yet confirmed | Check ID, history, and server; do not infer success |

Timeout, disconnection, or unavailable history describes waiting/monitoring conditions, not proof of success or failure. A subscription ID identifies the saved monitoring record; a prompt ID identifies the ComfyUI job.

## 5. Return after an app notification

Enable the desired completion/failure notifications in app settings and allow macOS notifications. Use them as a reminder to return to the chat. App notifications follow its queue and notification settings; still read the subscription result to confirm your specific job.

**Standard MCP does not automatically wake an idle Codex or Claude chat when a video finishes.** The app saves results for you to read later. Avoid asking the agent to repeat a wait every 45 seconds or scheduling a model wakeup every minute.

Later, paste into Codex:

```text
$comfyqueuebar Continue checking subscription YOUR_SUBSCRIPTION_ID.
Read saved results; if unfinished, wait only once without a polling loop.
```

You can supply the saved ID after reopening a session. The skill uses `resume_subscription` to attach the original subscription instead of creating another for the same check.

To read the current record without waiting:

```text
$comfyqueuebar Read saved results for subscription YOUR_SUBSCRIPTION_ID. Do not wait this time.
```

## 6. Get outputs or authorize the next step

The skill normally gives a short status summary. Request video output information explicitly:

```text
$comfyqueuebar Check subscription YOUR_SUBSCRIPTION_ID and list video output references if the job completed.
```

References contain ComfyUI filenames, subfolders, and `/view` URLs. They do not mean the video has been downloaded to the agent's local machine. You can also use **Preview & download…** in the app's completed history.

For further processing, give a concrete instruction such as “After confirming completion, download the video to this folder and check its duration.” Downloading, editing, or submitting another job needs suitable tools and a specified task; this skill checks existing jobs.

After completion, failure, or interruption, a verification subscription created by this workflow stops monitoring while records remain. A subscription resumed from another workflow is preserved unless cancellation is requested or its ownership as this verification subscription is established. Unsubscribing does not stop the ComfyUI job.

## Where are tokens saved?

| Stage | Repeated agent progress checks | ComfyQueueBar |
| --- | --- | --- |
| Setup | Agent decides how to check | Agent checks the connection and subscribes once |
| Rendering | Model turns may query, interpret progress, and decide to check again | App timers and programmatic MCP waiting monitor without language-model calls |
| Results | Agent interprets completion/errors | Agent interprets events or saved results when you resume |

For example, a 10-minute render checked in a new model turn every 10 seconds could involve about 60 checks. One subscription, one bounded wait, and a later result check can avoid those repeated progress turns. This is a workflow illustration, **not a token benchmark or fixed savings percentage**; an event may also end the wait early.

The reduction comes from repeated model work during waiting. Setup, tool results, failure handling, and later video processing still use tokens. If monitoring already runs entirely in ordinary code without repeated model involvement, additional token savings may be small.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| Skill missing | Run setup again, confirm installation, and reopen the session |
| Skill visible, MCP tools missing | Check registration results and the agent's MCP list; Claude Code provides `/mcp` |
| App unavailable | Confirm it is running, integration is enabled, and the Mac is awake; an expired heartbeat reports unavailability |
| Job remains unknown | Check the full ID, server, and history; deleted history is not evidence of completion |
| Updates stop after switching servers | Switch back; old subscriptions pause and do not migrate |
| Original job disappears after prioritization | Prioritize resubmits with a new prompt ID; confirm it before subscribing |
| Wait times out | Keep the subscription ID and resume after notification or later; avoid model polling loops |
| Want automatic continuation | Standard MCP has no idle wakeup; experimental Claude Channels requires verified inbound delivery, not just successful registration |

For manual setup, delivery modes, and persistence details, see [AI agent integration](AGENT_INTEGRATION.md). See the [skill source](../.agents/skills/comfyqueuebar/SKILL.md).
