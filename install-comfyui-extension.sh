#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/ComfyUI"
  exit 2
fi

comfy_root="${1%/}"
source_dir="$(cd "$(dirname "$0")/comfyui_extension/ComfyQueueBarProgress" && pwd)"
destination="${comfy_root}/custom_nodes/ComfyQueueBarProgress"

if [[ ! -d "${comfy_root}/custom_nodes" ]]; then
  echo "ComfyUI custom_nodes directory not found: ${comfy_root}/custom_nodes" >&2
  exit 1
fi

if [[ -e "${destination}" ]]; then
  echo "Extension already exists; refusing to overwrite: ${destination}" >&2
  exit 1
fi

mkdir -p "${destination}"
cp "${source_dir}/__init__.py" "${destination}/__init__.py"
echo "Installed ComfyQueueBarProgress: ${destination}"
echo "Wait for active generation to finish, then restart ComfyUI to load the extension."
