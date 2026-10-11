#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/lan-check
swiftc -parse-as-library Sources/ComfyQueueBar/LANDiscovery.swift tests/check-lan.swift -o build/lan-check/check
build/lan-check/check
python3 tests/check-lan-http.py build/lan-check/check
