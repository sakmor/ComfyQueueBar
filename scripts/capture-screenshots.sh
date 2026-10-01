#!/usr/bin/env bash
# Capture the real panel with compile-time-only fixtures; no server is contacted.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
capture_app="build/DocumentationCapture.app"
mkdir -p "$capture_app/Contents/MacOS" "$capture_app/Contents/Resources" docs/images
cp assets/app-icon.png "$capture_app/Contents/Resources/AppIconPreview.png"
swiftc -parse-as-library -O -D DOCUMENTATION_SCREENSHOT \
  Sources/ComfyQueueBar/main.swift -o "$capture_app/Contents/MacOS/DocumentationCapture"
TZ=UTC "$capture_app/Contents/MacOS/DocumentationCapture" docs/images/queue-light.png
TZ=UTC "$capture_app/Contents/MacOS/DocumentationCapture" docs/images/queue-dark.png --dark
printf 'Saved light and dark interface captures to docs/images/\n'
