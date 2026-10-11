#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/network-check
python3 - <<'PY'
from pathlib import Path
def body(name):
    lines = Path('Sources/ComfyQueueBar/' + name).read_text().split('\n')
    return '\n'.join(line for line in lines if not line.startswith('import ')) + '\n'
models = ''.join(body(name) for name in ('Localization.swift', 'QueueViewModel.swift', 'QueueModels.swift'))
# Exercise production request/action code, with preferences isolated from the app.
models = models.replace('UserDefaults.standard', 'validationDefaults')
Path('build/network-check/Models.swift').write_text(
    'import AppKit\nimport SwiftUI\nimport Foundation\nimport CryptoKit\nimport WebKit\n' + models
)
PY
swiftc -parse-as-library build/network-check/Models.swift \
  Sources/ComfyQueueBar/Features.swift Sources/ComfyQueueBar/WakeOnLAN.swift tests/check-network.swift tests/check-multi-server.swift \
  Sources/ComfyQueueBar/GPUTWConnection.swift Sources/ComfyQueueBar/GPUTWLogin.swift \
  Sources/ComfyQueueBar/ConnectionReview.swift \
  Sources/ComfyQueueBar/MultiServerMonitor.swift \
  Sources/ComfyQueueBar/LANDiscovery.swift Sources/ComfyQueueBar/LANDiscoveryView.swift \
  Sources/ComfyQueueBar/AgentBridge.swift Sources/ComfyQueueBar/AgentSetup.swift \
  Sources/ComfyQueueBar/ProgressExtensionInstaller.swift \
  -framework AVKit -o build/network-check/check
build/network-check/check
