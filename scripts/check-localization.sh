#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/localization-check
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/ComfyQueueBar/main.swift').read_text()
helper=s[s.index('enum L10n {'):s.index('\nenum PairedQueueStatus')]
Path('build/localization-check/main.swift').write_text('import Foundation\n'+helper+Path('tests/check-localization.swift').read_text())
PY
swiftc -D DOCUMENTATION_SCREENSHOT build/localization-check/main.swift -o build/localization-check/check
for language in en zh-Hant zh-Hans ja; do
  COMFYQUEUEBAR_PREVIEW_LANGUAGE="$language" build/localization-check/check
done
