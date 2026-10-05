#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/history-check
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/ComfyQueueBar/main.swift').read_text()
helper=s[s.index('struct CompletedJob:'):s.index('struct QueueJob:')]
f=Path('Sources/ComfyQueueBar/Features.swift').read_text()
models=f.split('// PURE_FEATURE_MODELS_BEGIN')[1].split('// PURE_FEATURE_MODELS_END')[0]
Path('build/history-check/main.swift').write_text('import Foundation\nimport CryptoKit\n'+models+helper+Path('tests/check-history.swift').read_text())
PY
swiftc Sources/ComfyQueueBar/WakeOnLAN.swift build/history-check/main.swift -o build/history-check/check
build/history-check/check
