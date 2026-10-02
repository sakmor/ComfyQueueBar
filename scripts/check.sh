#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash -n build-app.sh install-comfyui-extension.sh scripts/check.sh scripts/capture-screenshots.sh scripts/package-release.sh scripts/check-history.sh scripts/check-localization.sh
bash scripts/check-localization.sh
bash scripts/check-history.sh
python3 -m unittest discover -s tests -v
bash build-app.sh
plutil -lint build/ComfyQueueBar.app/Contents/Info.plist
test -s build/ComfyQueueBar.app/Contents/Resources/AppIcon.icns
test -s build/ComfyQueueBar.app/Contents/Resources/AppIconPreview.png
test -s build/ComfyQueueBar.app/Contents/Frameworks/Sparkle.framework/Sparkle
test -s build/ComfyQueueBar.app/Contents/Resources/Sparkle-LICENSE.txt
codesign --verify --deep --strict build/ComfyQueueBar.app

# The SwiftUI VideoPlayer overlay alone does not load its AppKit superclass.
otool -L build/ComfyQueueBar.app/Contents/MacOS/ComfyQueueBar | rg -q "/AVKit.framework/"
