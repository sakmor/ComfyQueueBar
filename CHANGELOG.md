# Changelog

## 1.3.0 — 2026-10-01

- Redesigned the panel with native materials, restrained list rows, compact typography, and settings in a gear popover.
- Added recently completed jobs with finish times and output filenames from ComfyUI history, refreshed every 15 seconds.
- Excluded failed/interrupted jobs; capped the list at 20 successful jobs from the newest 50 history records, with a 24-hour filter for dated entries.
- Updated English interface and desktop screenshots.


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
