#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/wake-check
cp tests/check-wake.swift build/wake-check/main.swift
swiftc Sources/ComfyQueueBar/WakeOnLAN.swift build/wake-check/main.swift -o build/wake-check/check
build/wake-check/check
