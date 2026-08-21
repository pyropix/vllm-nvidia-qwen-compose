#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker compose \
    --project-directory "${SCRIPT_DIR}" \
    logs vllm-qwen3.6-35B-A3B-NVFP4 --follow
