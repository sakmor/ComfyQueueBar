# Usage guide

## Reading the panel

Click the stack icon in the menu bar. A fresh queue response shows the sum of running and waiting entries. `0` means the selected queue is empty; `—` means disconnected, invalid data, or no fresh queue response for 30 seconds; `!` means sign-in is required; `…` means the initial check is in progress. The panel identifies the selected server and port, running/waiting jobs, completion history, and the last successful queue refresh time. GPU utilization is a separate metric and is not measured by this app.

Connection review, GPUtw login, status symbols, and Wake-on-LAN are included in v1.5.3. See the [multilingual remote setup tutorial](REMOTE_SETUP.md) for setup.

Use the refresh icon to update immediately. Queue requests run every four seconds while the app is running, including when the panel is closed. Progress requests run every second when a job is running and the server is connected. The app uses an eight-second network timeout and prevents overlapping requests of the same type.

The address is saved for the next launch. Only one server is monitored at a time. Switching addresses does not start or stop either ComfyUI server. History is held in memory while running; it is not saved to disk. Named server bookmarks are saved locally.

### Job labels

The app chooses a title in this order:

1. `extra_data.extra_pnginfo.workflow.name`.
2. A non-empty node `_meta.title`.
3. A node input named `filename_prefix` or `file_prefix`.
4. `ComfyUI workflow`.

There may be multiple node titles or prefixes; their dictionary iteration order is not a stable workflow naming contract. Set a workflow name in submitted metadata when consistent labels matter. Names come from the server and may be in any language; the app's own interface follows your preferred language.

`ID` shows the first eight characters of the prompt ID. `nodes` counts entries in the submitted prompt graph; it is not a count of completed nodes. Waiting numbers reflect the order returned by ComfyUI.

## Prioritizing a waiting job

1. Find the job under **Waiting queue**.
2. Click **Prioritize**.
3. Review the confirmation, then click **Prioritize and resubmit**.
4. Check the feedback and the updated queue.

The app fetches a fresh queue, verifies that the selected job is still pending, posts its prompt and metadata to `/prompt` with `front: true`, verifies whether the original has started, then deletes the original through `/queue` and checks again.

The replacement receives a new prompt ID. The seed and other values in the prompt graph are copied as returned; the frontend's submission-time behavior, such as incrementing or randomizing a seed, is not rerun. Server caching still applies. Original `client_id` information is not resubmitted as a top-level client ID, so browser-specific progress routing may differ.

The operation is not atomic. Another client can submit jobs or the server can start a waiting job between requests. The app attempts cleanup if the original has started or a request fails, but cannot guarantee rollback across a disconnected server or a job that has already started. Read the feedback, refresh, and inspect both IDs when requested. Do not repeatedly prioritize while the result is uncertain.

Use ComfyUI's browser interface to inspect full prompt IDs and resolve duplicates. This app does not offer pending-job deletion, queue clearing, or undo. If a duplicate is already running, deleting a waiting entry will not stop it.

## Stopping a running job

1. Find the job under **Running**.
2. Click **Stop**.
3. Confirm **Stop running job**.

The app checks that the prompt is still running, then posts `{"prompt_id": "…"}` to `/interrupt`. It checks the queue up to ten times at half-second intervals. Network request time can make the total wait longer than five seconds.

If ComfyUI has not yet removed the running entry, the app reports that a stop was requested but completion has not been confirmed. Some operations cannot interrupt immediately. Waiting jobs stay queued and can start automatically when processing continues. This is not a pause button.

Targeted interruption depends on the ComfyUI server honoring `prompt_id`. Older servers can treat `/interrupt` as global. The app cannot detect that semantic difference from the HTTP success response alone.

## Understanding progress

Install the bundled `ComfyQueueBarProgress` extension and restart the server to enable progress.

| Display | Meaning |
| --- | --- |
| Node title and percentage | The most recently observed node emitted fractional progress |
| Node is processing | A node was observed, but no useful fraction is available |
| No progress reported for this node yet | The bridge is reachable but has no snapshot matching the running prompt |
| Install the progress extension and restart ComfyUI | The progress route returned HTTP 404 |
| Unable to read live progress | A request, response, or decoding error occurred |

Progress is a single most-recent-node snapshot, not an aggregate of parallel branches, an ETA, or workflow completion. Cached nodes may emit little or no progress. The route can retain the last node snapshot after a workflow completes; the app hides it when the queue no longer contains that running prompt. Each new prompt resets the observer snapshot.

## Everyday workflow

Keep ComfyUI running, queue work through your existing browser or automation, and use the menu bar to check status. The app cannot submit new arbitrary workflows, launch ComfyUI, manage models, or maintain SSH tunnels.

Use **Quit** in the panel to close ComfyQueueBar. Quitting the app does not interrupt ComfyUI or cancel queued jobs.

## Interface language

The app supports English, Simplified Chinese, Traditional Chinese, and Japanese. It follows the first supported language in macOS preferred languages and falls back to English. You can select an app-specific language in **System Settings → General → Language & Region → Applications** (labels vary by macOS version). Restart ComfyQueueBar after changing the language. Workflow names, node names, and server-provided error details keep their original text. GitHub screenshots use English.

## Recently completed

The app reads `/history?max_items=200` every 15 seconds; manual refresh also refreshes history. **Recently completed** contains successful jobs, finish times, and output filenames. Choose **Last hour**, **Last 24 hours**, **Today** (your Mac's calendar), or **Loaded history**. Search matches workflow titles and output paths. Loaded history means only the newest 200 records returned by the server, not its entire archive. Records without timestamps appear only in Loaded history.

History belongs to ComfyUI. Clearing history or restarting a server without persistent history removes the records. Temporary previews are omitted. If a history request fails, the last successful snapshot remains visible with a warning. Switching servers clears the old view, and late responses from the previous connection are ignored.

### Previewing and downloading outputs

Click a thumbnail or **Preview & download…** to open a standalone preview window. Select an output in the picker when several files were reported. Images are decoded natively; MP4, MOV, and M4V use AVKit with native playback controls and no autoplay. The container extension alone does not guarantee that macOS supports the codec. Other file types can be downloaded without an inline preview.

**Copy absolute path** copies the selected output's full path. First use **Set output folder…** in the preview window to enter that server's actual output directory (for example `/Volumes/Media/ComfyUI/output` or `D:\ComfyUI\output`). The folder is remembered separately for each endpoint; leave it empty to clear the setting. Remote paths refer to the server's filesystem, unless you enter a corresponding Mac mount path. Paths are constructed from the configured folder and reported output reference; file existence is not verified. Input files do not use the output-folder mapping.

**Download…** opens a macOS save dialog. Choose a location and confirm any replacement. The app downloads the original bytes from the configured server's `/view` route. It does not convert or compress outputs. Failed transfers report an error and preserve an existing destination. Image preview decoding is capped at 32 MB; thumbnails at 8 MB. The app does not verify that a reported file still exists until you request it. Remote preview/download traffic follows your configured endpoint, including SSH forwarding.

## Failures and interruptions

Expand **Failures & interruptions** below history. Each entry shows its workflow title, timestamp when supplied, shortened ID, and server-reported reason. The same time range applies, and search matches titles or reasons. Interrupted jobs are labeled separately and do not produce failure notifications. Reasons are selectable and limited to 2,000 characters; inspect ComfyUI's logs for complete tracebacks. Viewing errors does not retry or change a job.

## Saved servers

1. Open the gear and enter a ComfyUI address.
2. Enter a **Server name**, then click **Save address**.
3. Click the saved name, or choose it from the current server name in the panel header. Review the port, running/waiting counts, and three most recent successful jobs from up to 20 history records, then click **Monitor this server**. **Cancel** leaves your current connection unchanged. A failed queue check prevents switching; unavailable history is labeled unknown.

Only one server is monitored at a time. Switching does not launch or stop a server and is disabled during queue actions. Saving the same address updates its name. The minus button removes the bookmark while leaving the current connection active. Addresses must use HTTP or HTTPS; bookmarks do not accept embedded usernames/passwords. The app does not manage SSH tunnels or credentials.

For GPUtw, use **Sign in to GPUtw…** and open the correct service port in the app's browser before reviewing it. For a sleeping Mac, save the address first and expand **Wake Mac** to configure manual or optional automatic Wake-on-LAN. A sleeping candidate does not need to pass a connection review before you can send a manual wake packet. See the [remote setup tutorial](REMOTE_SETUP.md).

## Notifications

Open the gear and choose **Completion notifications**:

| Mode | Behavior |
| --- | --- |
| Off | No completion notifications (default) |
| Every job | One notification for each newly discovered successful job |
| Whole batch | A summary of new successes/failures when the monitored queue is empty |

**Notify failures and disconnections** is a separate switch, also off by default. Enabling either option requests macOS notification permission. Manage permission, banners, and sounds under System Settings → Notifications → ComfyQueueBar. Focus modes can suppress presentation. Notification contents may include workflow and server names; failure alerts also include server error text.

The first history snapshot after connecting establishes a baseline and produces no old-job alerts. New prompt IDs are deduplicated during the connection. Notifications rely on polling and bounded server history; jobs removed from history before discovery cannot be reported. A connection-loss alert is sent only after a previously working queue connection fails, avoiding repeated alerts during an outage. The app must be running; these are local macOS notifications, not remote push messages.

## Running time and estimates

**Observed** time starts when this app first sees the running prompt. Connecting midway through a job yields a lower bound, not its actual total runtime. It resets after reconnecting to another endpoint or restarting the app.

Estimated remaining time uses the median duration of up to ten recent successful jobs with the same graph/settings fingerprint and valid start/finish timestamps. At least three matches are required. The fingerprint retains graph topology and execution settings, while ignoring seed, prompt text, labels, and output prefixes. This is a practical approximation: cache hits, different prompt complexity, server load, and hardware changes can affect timing. An estimate that has elapsed is explicitly labeled; node percentage remains separate from whole-workflow timing.

Use the gear button in the footer for connection, bookmark, notification, and update settings.
