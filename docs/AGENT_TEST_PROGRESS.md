# AI agent integration — development and test progress

Last updated: 2026-10-02 (Asia/Taipei)

Development branch: `codex/dev`
Main baseline: `8f529e5` (`Remove obsolete screenshot callout description in Japanese`)
Status: development only; not ready to merge into `main`.

## Objective

Let Claude Code in Claude Desktop and Codex Desktop delegate ComfyUI video-job monitoring to ComfyQueueBar. Agents should subscribe to exact jobs instead of repeatedly invoking the model to check progress. The app should retain results and report meaningful events through the delivery mechanism actually supported by each host.

**The desired asynchronous desktop wakeup is not yet established.** Standard MCP provides tools and programmatic waiting; it does not by itself resume an idle agent conversation.

## Local environment

| Component | Observed state |
| --- | --- |
| Claude Desktop | Installed; version 2.9939.2 |
| Codex / ChatGPT desktop app | Installed; version 26.928.31416, build 12553 |
| Bundled Codex CLI | Version 0.159.2 |
| Python | Homebrew Python available; adapter requires Python 3.9+ |
| ComfyQueueBar | Development build includes MCP bridge and one-click registration; bundle still reports 1.4.1, not a new published release |
| ComfyUI | User confirmed this computer does not have ComfyUI; no live render-server validation was performed |

No production video jobs were submitted, stopped, reprioritized, or deleted during these tests. Private workflow data, server addresses, credentials and output media are intentionally omitted from this report.

## Implemented in this branch

- Opt-in agent integration with persistent exact-job subscriptions and results.
- Local stdio MCP tools with delegation instructions telling agents not to poll through repeated model calls.
- Early failure/interruption events, whole-batch terminal events, monitoring-state transitions and durable acknowledgments.
- Standard MCP programmatic waiting with cancellation and timeout handling.
- Experimental Claude channel mode, gated by an inbound nonce probe before claiming verified delivery.
- One-click Claude/Codex MCP registration, original-file backups and a stable adapter copy in Application Support.
- Recovery of subscribed jobs outside the UI's bounded history window through individual history queries.
- Setup/delivery documentation and regression checks.

## Verification results

| Check | Result | Scope and evidence |
| --- | --- | --- |
| Four UI languages | Passed | English, Traditional Chinese, Simplified Chinese and Japanese; 123 localized keys |
| Existing pure Swift history and notification checks | Passed | Success/error filtering, timestamps, output references, deduplication and batch state |
| Python regression suite | Passed | 19 tests in the final full `scripts/check.sh` run |
| Swift/Python subscription IPC | Passed in fixtures | Uses the production Swift bridge with temporary state directories |
| Subscription persistence and recovery | Passed in fixtures | Restart recovery, idempotent registration and durable result/event acknowledgment |
| Failure before batch completion | Passed in fixtures | Failure emitted early; batch completion requires every subscribed ID to have an explicit terminal result |
| Unknown/missing history and server changes | Passed in fixtures | Empty queue is not success; switched-server subscriptions pause; history candidates rotate |
| Tool cancellation and responsiveness | Passed in fixtures | Waiting tool does not block ping; cancellation preserves subscriptions |
| Claude channel event transport | Passed with a simulated host | Actual stdio probe, verification, completion notification, per-process routing and acknowledgment; this is not evidence of Claude Desktop receiving it |
| One-click registration preservation | Passed | Unrelated settings/MCP entries retained; byte-exact backups; invalid Claude files rejected; partial failures reported |
| Codex registration command | Passed | Actual installed Codex CLI used with isolated temporary `CODEX_HOME`; repeated setup did not duplicate the entry |
| Release App build and bundle checks | Passed | `bash scripts/check.sh` completed; bundled adapter/guide, plist, ad-hoc signature verification and AVKit linkage checked |
| Packaged MCP startup | Passed on this computer | Adapter initialized and advertised all seven standard-mode tools and delegation instructions |
| Real Codex conversation tool discovery | Passed | After the user restarted the desktop agents, this conversation exposed the seven `comfyqueuebar` tools |
| Real Codex `get_status` | Passed | Tool reported a live, enabled app bridge and standard MCP delivery |
| Real Codex subscription round trip | Passed | Created a disposable test-ID subscription; the app accepted and persisted it; no ComfyUI submission was made |
| Real Codex event retrieval | Passed | `wait_for_events` returned the app's `monitoring_changed` / `disconnected` event; `finished` remained false |
| Real Codex acknowledgment and cancellation | Passed | Event acknowledged, subscription cancelled and no unacknowledged events remained |
| Claude MCP registration | Confirmed in configuration | Registration exists after user setup/restart; Claude Code conversation discovery/calls have not been verified |
| Live ComfyUI completion/failure and media output | Not tested | This computer has no ComfyUI |
| Idle desktop conversation wakeup | Not verified | Current registered mode is standard MCP; `push_verified_in_this_session` and `idle_conversation_wakeup` are false |
| Native one-click button interaction | Partially verified | User performed setup and restarted agents; resulting registrations and live Codex tools confirmed. Automated UI interaction itself was unreliable |

## Actual desktop test sequence

After the user performed setup and restarted Claude and Codex:

1. Confirmed both clients' configuration contains the `comfyqueuebar` registration.
2. Confirmed the app integration heartbeat is fresh and enabled.
3. Called `get_status` through this real Codex conversation. The app was available, but ComfyUI was disconnected and history unavailable.
4. Called `subscribe_jobs` with one explicitly disposable test prompt ID. This did not submit a render job.
5. Called `wait_for_events` once. It returned a disconnection event; it did not infer task completion.
6. Called `acknowledge_events`, then `unsubscribe`. The test subscription is cancelled; its record remains as durable test history.

This establishes the real Codex → MCP → App subscription and event-read path. It does not establish asynchronous push, real rendering, or a Claude Code conversation's tool behavior.

## Desktop automation limitation encountered

The native computer-use tool had repeated long delays/timeouts when locating the accessory App and interacting with Finder. Further UI automation was stopped. The extra development App instance launched for that attempt was terminated; the user's existing installed instance was left running. MCP configuration was subsequently established by the user through the App's setup flow.

Do not use those unsuccessful UI attempts as evidence that either desktop client received a completion notification. Avoid repeating that unreliable route without resolving the tool issue.

## Remaining validation before merging main

- [ ] Verify the Claude Desktop Code tab can discover `comfyqueuebar`, call `get_status`, subscribe, receive a programmatic event result and acknowledge/cancel it.
- [ ] Test against a disposable ComfyUI installation on a computer/server that has it. Record macOS, host versions and the ComfyUI version/commit.
- [ ] Verify successful video generation returns the correct output references and one final batch event.
- [ ] Verify explicit errors/interruption, mixed-result batches, connection loss/recovery, history removal and App restart during work.
- [ ] Check real desktop host timeout/background-wait behavior for long-running video tasks; do not replace waits with repeated model polling.
- [ ] Determine whether Claude Desktop's Code tab can opt into channel delivery. A successful inbound probe and an actual event reaching the original conversation are required; fixture tests are insufficient.
- [ ] Establish an actual supported Codex desktop push/resume mechanism, or explicitly resolve the product limitation before calling the original asynchronous workflow complete.
- [ ] Verify native setup UX, backups, both-client partial failure feedback and adapter refresh after an App update.
- [ ] Review same-user data exposure, stale status handling, subscription retention/limits and documented cleanup behavior.
- [ ] Run the full checks after final changes and review the development diff before merging.

## Commands and references

```sh
bash scripts/check.sh
python3 -m unittest discover -s tests -p test_agent_bridge.py -v
python3 -m unittest discover -s tests -p test_agent_setup.py -v
```

- [Agent setup and delivery guide](AGENT_INTEGRATION.md)
- [Developer architecture and checks](DEVELOPMENT.md)
- [Claude channel delivery contract](https://code.claude.com/docs/en/channels-reference)
- [Claude Desktop MCP configuration](https://code.claude.com/docs/en/desktop)
- [Codex MCP support and configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=app)

Continue development on `codex/dev`. Do not merge, publish or release this feature as complete until the outstanding host/render validation and desktop delivery behavior are resolved.
