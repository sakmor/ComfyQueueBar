# Usage guide

## Reading the panel

Click the stack icon in the menu bar. Its number is the sum of running and waiting entries. The panel shows connection status, the server address, three count tiles, running jobs, waiting jobs, and the last successful queue refresh time.

Use the refresh icon to update immediately. Queue requests run every four seconds while the app is running, including when the panel is closed. Progress requests run every second when a job is running and the server is connected. The app uses an eight-second network timeout and prevents overlapping requests of the same type.

The address is saved for the next launch. Only one server is monitored at a time. Switching addresses does not start or stop either ComfyUI server. No job history is retained by the app.

### Job labels

The app chooses a title in this order:

1. `extra_data.extra_pnginfo.workflow.name`.
2. A non-empty node `_meta.title`.
3. A node input named `filename_prefix` or `file_prefix`.
4. `ComfyUI workflow`.

There may be multiple node titles or prefixes; their dictionary iteration order is not a stable workflow naming contract. Set a workflow name in submitted metadata when consistent labels matter. Names come from the server and may be in any language; the app's own interface is English.

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

Keep ComfyUI running, queue work through your existing browser or automation, and use the menu bar to check status. The app cannot submit new arbitrary workflows, launch ComfyUI, manage models, preview generated media, or maintain SSH tunnels.

Use **Quit** in the panel to close ComfyQueueBar. Quitting the app does not interrupt ComfyUI or cancel queued jobs.

## Interface language

The app supports English, Simplified Chinese, Traditional Chinese, and Japanese. It follows the first supported language in macOS preferred languages and falls back to English. You can select an app-specific language in **System Settings → General → Language & Region → Applications** (labels vary by macOS version). Restart ComfyQueueBar after changing the language. Workflow names, node names, and server-provided error details keep their original text. GitHub screenshots use English.

## Recently completed

The panel displays successful completed jobs, their finish time, and reported output filenames. It scans the newest 50 records from `/history?max_items=50` every 15 seconds and displays up to 20 successes, newest first. Manual refresh also refreshes history. Dated entries older than 24 hours are omitted. If a server does not report the completion timestamp, a successful record may still appear with “Completion time unavailable”; it cannot be assigned to the 24-hour window. Failed and interrupted jobs are excluded.

History belongs to ComfyUI, not the Mac app. Clearing history or restarting a server without persistent history removes those records. Only filenames reported by output nodes can be listed; this does not verify that a file still exists. Temporary previews are omitted. History failures leave the last successful snapshot visible with a warning and do not disconnect a working queue. Changing the endpoint clears the old history view.

Use the gear button in the footer for connection and update settings.
