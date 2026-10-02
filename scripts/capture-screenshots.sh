#!/usr/bin/env bash
# Capture the real panel with compile-time-only fixtures; no server is contacted.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
capture_app="build/DocumentationCapture.app"
mkdir -p "$capture_app/Contents/MacOS" "$capture_app/Contents/Resources" docs/images
cp assets/app-icon.png "$capture_app/Contents/Resources/AppIconPreview.png"
swiftc -parse-as-library -O -D DOCUMENTATION_SCREENSHOT \
  Sources/ComfyQueueBar/*.swift -framework AVKit -o "$capture_app/Contents/MacOS/DocumentationCapture"
if [[ "${1:-}" == "--desktop-demo" ]]; then
  cat > "$capture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DocumentationCapture</string>
<key>CFBundleIdentifier</key><string>io.github.sakmor.comfyqueuebar.documentation</string>
<key>CFBundleName</key><string>ComfyQueueBar Demo</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
  codesign --force --deep --sign - "$capture_app"
  printf 'Desktop demo: capture the display containing the panel, then Quit to close the demo.\n'
  TZ=UTC exec "$capture_app/Contents/MacOS/DocumentationCapture" --menu-bar --dark
fi
TZ=UTC "$capture_app/Contents/MacOS/DocumentationCapture" docs/images/queue-light.png
TZ=UTC "$capture_app/Contents/MacOS/DocumentationCapture" docs/images/queue-dark.png --dark
TZ=UTC "$capture_app/Contents/MacOS/DocumentationCapture" docs/images/settings.png --settings
printf 'Saved light and dark interface captures to docs/images/\n'
