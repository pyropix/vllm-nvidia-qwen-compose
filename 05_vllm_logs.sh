#!/usr/bin/env bash
set -euxo pipefail

docker compose logs vllm-qwen3.6-35B-A3B-NVFP4 --follow
