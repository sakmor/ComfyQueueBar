#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash -n build-app.sh install-comfyui-extension.sh scripts/check.sh scripts/capture-screenshots.sh
bash scripts/check-localization.sh
python3 -m unittest discover -s tests -v
bash build-app.sh
plutil -lint build/ComfyQueueBar.app/Contents/Info.plist
test -s build/ComfyQueueBar.app/Contents/Resources/AppIcon.icns
test -s build/ComfyQueueBar.app/Contents/Resources/AppIconPreview.png
codesign --verify --deep --strict build/ComfyQueueBar.app
