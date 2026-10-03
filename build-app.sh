#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ComfyQueueBar"
APP_DIR="$SCRIPT_DIR/build/$APP_NAME.app"

swift build --package-path "$SCRIPT_DIR" --configuration release --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$SCRIPT_DIR/.build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

sparkle_dir="$SCRIPT_DIR/.build/artifacts/sparkle/Sparkle"
ditto "$sparkle_dir/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_dir/LICENSE" "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_DIR/Contents/MacOS/$APP_NAME"

iconset_dir="$SCRIPT_DIR/build/AppIcon.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SCRIPT_DIR/assets/app-icon.png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$SCRIPT_DIR/assets/app-icon.png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$SCRIPT_DIR/assets/app-icon.png" "$APP_DIR/Contents/Resources/AppIconPreview.png"
mkdir -p "$APP_DIR/Contents/Resources/AgentBridge"
cp "$SCRIPT_DIR/agent_bridge/server.py" "$APP_DIR/Contents/Resources/AgentBridge/server.py"
cp "$SCRIPT_DIR/docs/AGENT_INTEGRATION.md" "$APP_DIR/Contents/Resources/AgentBridge/README.md"
mkdir -p "$APP_DIR/Contents/Resources/AgentBridge/skills/comfyqueuebar"
cp "$SCRIPT_DIR/.agents/skills/comfyqueuebar/SKILL.md" "$APP_DIR/Contents/Resources/AgentBridge/skills/comfyqueuebar/SKILL.md"
mkdir -p "$APP_DIR/Contents/Resources/ComfyQueueBarProgress"
cp "$SCRIPT_DIR/comfyui_extension/ComfyQueueBarProgress/__init__.py" "$APP_DIR/Contents/Resources/ComfyQueueBarProgress/__init__.py"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ComfyQueueBar</string>
  <key>CFBundleIdentifier</key><string>io.github.sakmor.comfyqueuebar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>ComfyUI Queue</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.5.0</string>
  <key>CFBundleVersion</key><string>1.5.0</string>
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/sakmor/ComfyQueueBar/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>xIDXTXpij8/7ugU8GpxCgk27FI9+oLthBJ4XEKr4VGs=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAllowsAutomaticUpdates</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUEnableSystemProfiling</key><false/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SURequireSignedFeed</key><true/>
  <key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string><string>ja</string></array>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

# File Provider metadata can be reattached while a bundle is assembled in a
# synced checkout. Sign a temporary copy outside the provider's directory.
SIGNING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ComfyQueueBar.XXXXXX")"
trap 'rm -rf "$SIGNING_DIR"' EXIT
SIGNED_APP="$SIGNING_DIR/$APP_NAME.app"
ditto "$APP_DIR" "$SIGNED_APP"
xattr -cr "$SIGNED_APP"
codesign --force --deep --sign - "$SIGNED_APP"
codesign --verify --deep --strict "$SIGNED_APP"
rm -rf "$APP_DIR"
ditto "$SIGNED_APP" "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
