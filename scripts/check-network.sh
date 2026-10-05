#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/network-check
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/ComfyQueueBar/main.swift').read_text()
models = source[source.index('enum L10n {'):source.index('enum QueueBrand {')]
# Exercise production request/action code, with preferences isolated from the app.
models = models.replace('UserDefaults.standard', 'validationDefaults')
Path('build/network-check/Models.swift').write_text(
    'import AppKit\nimport SwiftUI\nimport Foundation\nimport CryptoKit\nimport WebKit\n' + models
)
PY
swiftc -parse-as-library build/network-check/Models.swift \
  Sources/ComfyQueueBar/Features.swift Sources/ComfyQueueBar/WakeOnLAN.swift tests/check-network.swift \
  Sources/ComfyQueueBar/GPUTWConnection.swift Sources/ComfyQueueBar/GPUTWLogin.swift \
  Sources/ComfyQueueBar/ConnectionReview.swift \
  Sources/ComfyQueueBar/AgentBridge.swift Sources/ComfyQueueBar/AgentSetup.swift \
  Sources/ComfyQueueBar/ProgressExtensionInstaller.swift \
  -framework AVKit -o build/network-check/check
build/network-check/check
