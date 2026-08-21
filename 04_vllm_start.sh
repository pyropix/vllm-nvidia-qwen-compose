#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/.env.vllm"

if [[ -z "${MODEL_ID:-}" ]]; then
    echo "Error: MODEL_ID is not set in ${SCRIPT_DIR}/.env.vllm" >&2
    echo "Run 02_select_model.sh first." >&2
    exit 1
fi

if [[ "${MODEL_ID}" == unsloth/* ]]; then
    echo "WARNING: unsloth model selected. MTP speculative decoding in docker-compose.yml" >&2
    echo "may not be supported. Disable --speculative-config if vLLM fails to start." >&2
fi

docker compose \
    --project-directory "${SCRIPT_DIR}" \
    --env-file "${SCRIPT_DIR}/.env.vllm" \
    pull

docker compose \
    --project-directory "${SCRIPT_DIR}" \
    --env-file "${SCRIPT_DIR}/.env.vllm" \
    up --detach --remove-orphans
