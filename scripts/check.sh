#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash -n build-app.sh install-comfyui-extension.sh scripts/check.sh scripts/capture-screenshots.sh scripts/package-release.sh scripts/check-history.sh scripts/check-localization.sh scripts/check-network.sh
bash scripts/check-localization.sh
bash scripts/check-history.sh
bash scripts/check-network.sh
python3 -m unittest discover -s tests -v
bash build-app.sh
plutil -lint build/ComfyQueueBar.app/Contents/Info.plist
test -s build/ComfyQueueBar.app/Contents/Resources/AppIcon.icns
test -s build/ComfyQueueBar.app/Contents/Resources/AppIconPreview.png
test -s build/ComfyQueueBar.app/Contents/Frameworks/Sparkle.framework/Sparkle
test -s build/ComfyQueueBar.app/Contents/Resources/Sparkle-LICENSE.txt
test -s build/ComfyQueueBar.app/Contents/Resources/AgentBridge/server.py
test -s build/ComfyQueueBar.app/Contents/Resources/AgentBridge/README.md
# The synced workspace may reattach Finder metadata after the signed bundle is
# copied back. Verify a clean copy of the exact built bundle instead.
verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/ComfyQueueBar-verify.XXXXXX")"
trap 'rm -rf "$verify_dir"' EXIT
ditto build/ComfyQueueBar.app "$verify_dir/ComfyQueueBar.app"
xattr -cr "$verify_dir/ComfyQueueBar.app"
codesign --verify --deep --strict "$verify_dir/ComfyQueueBar.app"

# The SwiftUI VideoPlayer overlay alone does not load its AppKit superclass.
otool -L build/ComfyQueueBar.app/Contents/MacOS/ComfyQueueBar | grep -q "/AVKit.framework/"
