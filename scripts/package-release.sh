#!/usr/bin/env bash
# Requires the owner's Sparkle signing key in macOS Keychain; never exports it.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
[[ "$(uname -m)" == "arm64" ]] || { echo "Release packaging requires an Apple Silicon Mac." >&2; exit 1; }
bash build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/ComfyQueueBar.app/Contents/Info.plist)
release_dir="build/releases/$version"
mkdir -p "$release_dir"
# Synced workspaces can reattach Finder metadata after build-app.sh signs the
# bundle. Archive a verified clean copy outside the provider directory.
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/ComfyQueueBar-release.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto build/ComfyQueueBar.app "$staging_dir/ComfyQueueBar.app"
xattr -cr "$staging_dir/ComfyQueueBar.app"
codesign --verify --deep --strict "$staging_dir/ComfyQueueBar.app"
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/ComfyQueueBar.app" "$release_dir/ComfyQueueBar-macOS-arm64.zip"
(cd "$release_dir" && shasum -a 256 ComfyQueueBar-macOS-arm64.zip > SHA256SUMS.txt)
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --account io.github.sakmor.comfyqueuebar \
  --maximum-deltas 0 \
  --download-url-prefix "https://github.com/sakmor/ComfyQueueBar/releases/download/v$version/" \
  --link https://github.com/sakmor/ComfyQueueBar \
  "$release_dir"
cp "$release_dir/appcast.xml" appcast.xml
printf 'Signed release files: %s\nUpload ZIP and checksum to v%s, then publish appcast.xml after assets are available.\n' "$release_dir" "$version"
