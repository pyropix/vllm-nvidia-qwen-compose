#!/usr/bin/env bash
set -euxo pipefail

# Download LLM via Hugging Face CLI
# MODEL_ID is read from .env.vllm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.env.vllm
source "${SCRIPT_DIR}/.env.vllm"

hf download "${MODEL_ID}"
