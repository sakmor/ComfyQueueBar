#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/localization-check
cp tests/check-localization.swift build/localization-check/main.swift
swiftc -D DOCUMENTATION_SCREENSHOT Sources/ComfyQueueBar/Localization.swift build/localization-check/main.swift -o build/localization-check/check
for language in en zh-Hant zh-Hans ja; do
  COMFYQUEUEBAR_PREVIEW_LANGUAGE="$language" build/localization-check/check
done
