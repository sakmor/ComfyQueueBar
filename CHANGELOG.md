# Changelog

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
