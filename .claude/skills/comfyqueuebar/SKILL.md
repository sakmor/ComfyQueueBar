---
name: comfyqueuebar
description: Check the local ComfyQueueBar MCP connection, or verify one existing ComfyUI job when given its exact prompt ID.
---

# ComfyQueueBar

Use this skill when the user wants to check ComfyQueueBar's MCP connection or verify a specific existing ComfyUI job. Invoke it as `/comfyqueuebar` in Claude Code or `$comfyqueuebar` in Codex. The same `SKILL.md` works in both clients.

This skill does not configure MCP, start the app, submit ComfyUI work, or require account login. It only calls the connected `comfyqueuebar` MCP tools.

## Check the connection

When invoked without a prompt ID:

1. Call `get_status` from the `comfyqueuebar` MCP server once.
2. Report whether the app is available, whether ComfyUI is connected, whether history is available, and running/pending counts if returned.
3. Do not call shell commands or other tools, and do not change jobs or subscriptions.
4. If the MCP tool is unavailable, say this session cannot see `comfyqueuebar`. Tell the user to inspect `/mcp` in Claude Code or the MCP server list in Codex, then reopen the session after registration. Do not attempt setup or ask the user to log in.

## Verify an existing job

Only use this mode when the user supplies one exact prompt ID for an already-existing job. Never guess or discover an ID for them.

1. Call `get_status` once. Stop if the app is unavailable, the server is disconnected, or history is unavailable; report that state without changing anything.
2. Use the endpoint returned by `get_status` exactly. Call `subscribe_jobs` once for only the supplied prompt ID. This tracks the existing job; it does not submit or alter it.
3. Call `wait_for_events` once with the returned subscription ID and `timeout_seconds: 45`. Do not poll or loop.
4. Call `get_results` once and summarize whether the job is queued, running, completed, failed, interrupted, or unknown. A finished batch alone does not mean success; inspect the job result status.
5. Acknowledge only event IDs returned for this subscription. If the job has a terminal result, call `unsubscribe` for this test subscription. If it is still queued/running or the wait timed out, leave the subscription active and give the user its subscription ID so they can continue later.
6. Do not include output filenames, paths, URLs, workflow data, or prompt content unless the user asks for them.
