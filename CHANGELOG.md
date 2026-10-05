# Changelog

## Unreleased

- Add GPUtw browser sign-in for private and password-protected ComfyUI services, with scoped authenticated queue/history/progress requests, media previews, and downloads.
- Review the service port, queue, and recent successful history before switching; preserve the current server when review is cancelled and retain custom GPUtw bookmark names.
- Distinguish a confirmed empty queue (`0`) from unavailable/stale data (`—`), required sign-in (`!`), and initial connection checks (`…`); reject malformed queue payloads and bypass local API caches.
- Add optional per-server Wake-on-LAN settings, manual UDP magic packets, and automatic waking for selected-server network failures with a two-minute retry limit.
- Add English, Traditional Chinese, Simplified Chinese, and Japanese remote setup tutorials covering GPUtw ports, status interpretation, login recovery, Wake-on-LAN, SSH, and remote progress installation.
- Extend isolated network, authentication, media, history/profile, and UDP regression checks. GPUtw connection review was also checked against a live instance; physical Mac wake compatibility remains environment-dependent.

## 1.5.2 — 2026-10-03

- Add absolute path copying for completed image and video outputs, with output-folder settings remembered per server endpoint.
- Support macOS/Linux, Windows drive, and UNC network paths; reject relative folders and output references containing parent traversal.
- Add English, Traditional Chinese, Simplified Chinese, and Japanese controls and output-path regression checks.

## 1.5.1 — 2026-10-03

- Add one-click installation of the bundled node progress extension for local ComfyUI installations, with restart guidance and multilingual settings.
- Stage extension files before installation and refuse existing destinations without deleting their contents when installation fails.
- Add detailed agent token-saving tutorials in English, Traditional Chinese, Simplified Chinese, and Japanese.

## 1.5.0 — 2026-10-02

- Add opt-in AI agent integration with a local stdio MCP adapter that recommends delegating monitoring to the app instead of repeated model queries.
- Persist exact-job subscriptions, output references, failure and batch events, and acknowledgments; recover subscribed jobs outside the UI history window.
- Add cancellable programmatic waits and experimental Claude channel delivery with an inbound verification probe. Standard desktop MCP clearly reports its lack of idle wakeup support.
- Add one-click Claude/Codex MCP registration with original-file backups, a stable adapter location, and independent success/failure feedback.
- Bundle adapter/setup instructions and add settings controls to copy MCP configuration. Add Swift/Python IPC and protocol regression tests.
- Install the shared Claude Code/Codex skill with backups; support connection checks, exact-job verification, and saved-subscription recovery.
- Add copy-ready skill usage examples and upgrade instructions to the English and translated README guides.

## 1.4.1 — 2026-10-02

- Replaced SwiftUI menu-bar scene ownership with a retained native NSStatusItem and transient SwiftUI popover.
- Bounded the menu-bar width and capped its visible count at 99+; the tooltip retains the exact total.
- Restore the item on wake and display reconfiguration. Reopening the running app restores its item and opens a normal queue window, usable when menu-bar space is exhausted.
- Explicitly link AVKit, fixing a native video-view superclass loading failure reproduced in the preview-window test.
- Output previews now open in a retained standalone window instead of a nested menu-bar popover; closing it stops playback and pending preview loads.
- Closing the fallback window keeps queue monitoring running. Status item placement remains controlled by macOS; notch/crowding cannot be forcibly bypassed.

## 1.4.0 — 2026-10-01

- Added opt-in native completion/batch, failure, and disconnection notifications with first-connection suppression and deduplication.
- Added image/video thumbnails, native media previews, output selection, and save-dialog downloads.
- Added searchable history with last-hour, last-day, today, and loaded-history filters over the newest 200 server records.
- Added named server bookmarks and quick switching from the panel header.
- Added observed runtime and median remaining-time estimates requiring three matching successful history records.
- Added failed/interrupted jobs and selectable server error details.
- Localized all new controls in English, Simplified Chinese, Traditional Chinese, and Japanese; refreshed English screenshots and usage guides.

## 1.3.0 — 2026-10-01

- Redesigned the panel with native materials, restrained list rows, compact typography, and settings in a gear popover.
- Added recently completed jobs with finish times and output filenames from ComfyUI history, refreshed every 15 seconds.
- Excluded failed/interrupted jobs; capped the list at 20 successful jobs from the newest 50 history records, with a 24-hour filter for dated entries.
- Updated English interface screenshots; retained the earlier desktop context capture with a version note.


## 1.2.0 — 2026-10-01

- Added Sparkle automatic update checks, downloads, installation, and a manual check button.
- Added multilingual update controls and required signed update feeds and archives.
- Added a Keychain-backed release packaging script and bundled Sparkle license.


## 1.1.0 — 2026-10-01

- Published a prebuilt Apple Silicon macOS app ZIP and SHA-256 checksum.

- Localized the macOS interface into Simplified Chinese, Traditional Chinese, and Japanese, including confirmations, recovery messages, accessibility labels, and update times. Documentation screenshots remain English.

- Added Simplified Chinese, Traditional Chinese, and Japanese README guides with language navigation and shared screenshots. The app interface remains English.

- Added a real macOS desktop context capture with a menu bar callout at the top of the README.

- Simplified the menu bar mark to three queue rows and a separate play triangle for small-size readability.

- Added a custom macOS app icon, matching panel branding, and a monochrome menu bar mark.
- Added native light/dark interface screenshots and a visual-first README.
- Added a reproducible screenshot capture build with isolated sample data and no server access.
- Kept the displayed update time in English across system locales.

## 1.0.0 — 2026-10-01

- Extracted the macOS queue helper into a standalone repository.
- Translated the interface, confirmation dialogs, errors, and installer into English.
- Added setup, usage, remote SSH, troubleshooting, API, and contributor documentation.
- Added an independent bundle identifier and `/comfyqueuebar/queue-progress` route.
- Reset the progress snapshot before registering each new prompt.
- Used a refresh symbol compatible with the declared macOS runtime target.
- Moved panel state into an observable object to avoid SwiftUI State macro/toolchain conflicts.
- Added isolated Python tests and macOS build verification through GitHub Actions.

This entry describes the source version. It does not imply a notarized binary release or a complete compatibility matrix.
