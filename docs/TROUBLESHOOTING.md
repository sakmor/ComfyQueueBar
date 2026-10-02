# Troubleshooting and maintenance

## Build failures

**`swift: command not found`**: install Xcode Command Line Tools with `xcode-select --install`, then open a new terminal. Run `xcode-select -p` to inspect the active toolchain.

**Tools version 5.9 is unsupported**: update your Command Line Tools or Xcode. The package requires Swift 5.9 or later. macOS 13 support is the runtime target, not a promise that every compiler shipped with macOS 13 can build it.

**SDK or developer-directory errors**: verify that your selected Xcode or Command Line Tools installation is valid. Run `swift --version` and `swift build -c release` from the repository to obtain the compiler's full error.

The source uses AppKit, Foundation, SwiftUI, and the pinned Sparkle binary package. Swift Package Manager downloads Sparkle during the first build; network access to GitHub is required. No Homebrew libraries are needed.

## The app opens but there is no window

This is a menu bar app. Look for a stack icon and a number at the top of the screen; it does not open a regular window or show a Dock icon. A crowded menu bar, especially on Macs with a camera notch, can hide items. Quit an earlier instance before launching another copy.

The build is ad-hoc signed, not Developer ID signed or notarized. For a downloaded copy, follow macOS's normal Privacy & Security approval flow only after verifying the source. Building locally avoids relying on an unverified distributed executable.

## Disconnected or unable to read the queue

1. Open ComfyUI in your browser and verify it is running.
2. Check the exact base address and port. Include `http://` or `https://`.
3. Run `curl --fail YOUR_BASE_URL/queue`.
4. Check whether an SSH tunnel or reverse proxy is still working.
5. Check network permission, firewall, certificate, and proxy configuration.

A base address should not end in `/queue`, `/prompt`, or a browser page route. A reverse-proxy path prefix is allowed. Query strings and fragments are removed from requests. HTTP 401/403 often means the server requires authentication the app cannot supply. The app has an eight-second timeout.

The connection indicator reflects successful queue requests, not progress-extension availability. Losing the connection clears displayed jobs; it does not cancel server jobs.

## Queue works but progress does not

Run:

```sh
curl --fail http://127.0.0.1:8188/comfyqueuebar/queue-progress
```

Use your actual endpoint or tunnel port.

- **404**: install the extension in the correct ComfyUI instance and restart it. Check for an extra directory nesting level and reverse-proxy route exclusions.
- **Import error in ComfyUI logs**: the ComfyUI version may lack the internal progress APIs. Update to a compatible version or use queue monitoring without the extension.
- **Null fields**: no node has emitted a snapshot since startup or the last prompt reset. Queue a workflow that reports node progress.
- **Route works, but the app shows no progress**: the snapshot prompt ID must match the running queue entry. Some nodes do not emit progress; cached or very short nodes may finish between polls.

The standalone endpoint is `/comfyqueuebar/queue-progress`. The old project helper used `/aniclayfilm/queue-progress`. Installing only the old extension will not enable this edition. Avoid loading both editions or multiple copies of the same extension in one ComfyUI process; both wrap internal progress reset behavior.

## Prioritization reports an uncertain result

Do not immediately repeat the action. Refresh the queue and check the original and replacement prompt IDs mentioned in the feedback. Use the ComfyUI browser queue controls to remove an unintended waiting duplicate. An already-running job cannot be removed by deleting a waiting entry.

The queue action requires successful `/prompt` submission and `/queue` deletion. Custom server behavior, missing node types, validation errors, disappearing jobs, and connection loss can prevent completion. See [action semantics](USAGE.md#prioritizing-a-waiting-job).

## Stop does not take effect immediately

The server may be inside an operation that does not check for interruption frequently. A successful HTTP response confirms receipt, not completion. Refresh and inspect the ComfyUI server logs. Waiting jobs may start immediately after interruption.

On older servers, `/interrupt` may ignore the submitted prompt ID. Use a version with targeted interruption before relying on the selected-job behavior. The app cannot determine this from a 200 response alone.

## Updating the app

v1.2.0 and later automatically check for updates through Sparkle. Use **Check for updates…** in the panel to check now, or enable **Automatically update the app**. If updates cannot install, move the app out of the download archive/disk image into a writable Applications folder and reopen it. macOS may require approval for this non-notarized app. Check that GitHub and raw.githubusercontent.com are reachable. A signature failure must not be bypassed; report it to the maintainer.

v1.1.0 and earlier require a one-time manual download of the newer app. Automatic updates replace the Mac app only; server extensions remain a separate installation.

For a source build, quit the app, then run from your clone:

```sh
git pull --ff-only
bash build-app.sh
open build/ComfyQueueBar.app
```

If you installed a copy in Applications, replace that copy after quitting it. Keep the server extension matched to this repository version when updating progress functionality.

## Updating the extension

The installer refuses to overwrite an existing directory. After generation finishes, stop ComfyUI and move the old `ComfyQueueBarProgress` directory to a backup location **outside `custom_nodes`**. Re-run the installer and restart ComfyUI. Keep the backup until the route has been verified. A backup left inside `custom_nodes` can still be loaded.

## Uninstalling

1. Quit ComfyQueueBar.
2. Remove its app bundle and any Login Items entry you added.
3. Stop ComfyUI, remove only `custom_nodes/ComfyQueueBarProgress`, then restart ComfyUI.
4. Delete the source clone if no longer needed.

To remove the saved endpoint as well, while the app is closed:

```sh
defaults delete io.github.sakmor.comfyqueuebar
```

If macOS reports that the domain does not exist, there are no settings stored under that domain. Uninstalling the app does not delete ComfyUI models, outputs, or queues.

## Reporting a problem

Include macOS version, processor architecture, Swift version (for build problems), ComfyUI version or commit, whether the extension is installed, exact UI error, and reproduction steps. Include sanitized relevant server logs. Remove prompt contents, private addresses, credentials, and workflow metadata before sharing. A compatible live server is useful for reproducing API behavior; mock tests do not prove compatibility with every ComfyUI release.

## Notifications, media, and timing

- **No notification:** Enable a mode in the gear, allow ComfyQueueBar in macOS notification settings, check Focus mode, and keep the app running. The first history snapshot is deliberately silent. Cleared/missing history cannot produce notifications.
- **No thumbnail or preview:** Confirm the output still exists on the server and its `/view` route is reachable through the same endpoint. A video extension does not guarantee a supported codec; download it and use a suitable player. Large images may exceed preview limits.
- **No estimate:** At least three successful matching graph/settings records need valid start and finish timestamps in the loaded 200 records. Changed settings or absent timestamps can prevent a match. Observed time starts when the app first sees the job.
- **Missing older jobs:** Loaded history contains at most the newest 200 server records. Select Loaded history to include unknown timestamps; clear the search field and inspect ComfyUI for older records.
- **Cannot switch servers:** Wait for the active prioritize/stop action to finish. Switching while a mutation is in flight is disabled.

## Menu bar icon disappears / camera notch

First reopen ComfyQueueBar from Applications or Spotlight. Starting with v1.4.1, reopening a running app restores its status item and opens a normal queue window; quitting/restarting is not required. Closing that window keeps monitoring running.

macOS controls menu-bar item placement and may hide items when the menu bar is crowded, including on displays with a camera notch. The app uses a bounded 52-point item and shows 99+ for larger queues, with the full count in its tooltip. It retains its native status item and restores visibility after wake/display changes, but cannot guarantee space in a crowded menu bar. Command-drag the icon toward the right when visible, or reduce other menu-bar items. The app does not change system menu-bar preferences or disable third-party menu-bar managers.

If reopening launches a new process rather than opening the fallback window, the previous app may have exited. Include app/macOS version, whether the process was still running, display changes, sleep/wake, and any ComfyQueueBar crash report when filing an issue.
