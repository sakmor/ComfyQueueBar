#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/gputw-check
python3 - <<'PY'
from pathlib import Path
s = Path('Sources/ComfyQueueBar/main.swift').read_text()
helper = s[s.index('enum L10n {'):s.index('@MainActor\nfinal class QueueViewModel')]
Path('build/gputw-check/Localization.swift').write_text('import Foundation\n' + helper)
PY
swiftc -parse-as-library build/gputw-check/Localization.swift \
  Sources/ComfyQueueBar/GPUTWConnection.swift tests/check-gputw.swift \
  -o build/gputw-check/check
build/gputw-check/check
