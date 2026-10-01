#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/history-check
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/ComfyQueueBar/main.swift').read_text()
helper=s[s.index('struct CompletedJob:'):s.index('struct QueueJob:')]
Path('build/history-check/main.swift').write_text('import Foundation\n'+helper+Path('tests/check-history.swift').read_text())
PY
swiftc build/history-check/main.swift -o build/history-check/check
build/history-check/check
