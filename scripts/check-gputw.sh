#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/gputw-check
swiftc -parse-as-library Sources/ComfyQueueBar/Localization.swift \
  Sources/ComfyQueueBar/GPUTWConnection.swift tests/check-gputw.swift \
  -o build/gputw-check/check
build/gputw-check/check
