#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/.env.vllm"

if [[ -z "${MODEL_ID:-}" ]]; then
    echo "Error: MODEL_ID is not set in ${SCRIPT_DIR}/.env.vllm" >&2
    echo "Run 02_select_model.sh first." >&2
    exit 1
fi

if [[ "${MODEL_ID}" == nvidia/* ]]; then
    COMPOSE_PROFILE="nvidia"
elif [[ "${MODEL_ID}" == unsloth/* ]]; then
    COMPOSE_PROFILE="unsloth"
else
    echo "Error: Unknown MODEL_ID prefix '${MODEL_ID}'. Expected nvidia/* or unsloth/*." >&2
    exit 1
fi

echo "Using profile: ${COMPOSE_PROFILE}"

docker compose \
    --project-directory "${SCRIPT_DIR}" \
    --env-file "${SCRIPT_DIR}/.env.vllm" \
    --profile "${COMPOSE_PROFILE}" \
    pull

docker compose \
    --project-directory "${SCRIPT_DIR}" \
    --env-file "${SCRIPT_DIR}/.env.vllm" \
    --profile "${COMPOSE_PROFILE}" \
    up --detach --remove-orphans
