#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/.env.vllm"

if [[ "${MODEL_ID}" == nvidia/* ]]; then
    COMPOSE_PROFILE="nvidia"
elif [[ "${MODEL_ID}" == unsloth/* ]]; then
    COMPOSE_PROFILE="unsloth"
else
    echo "Error: Unknown MODEL_ID prefix '${MODEL_ID}'." >&2
    exit 1
fi

docker compose \
    --project-directory "${SCRIPT_DIR}" \
    --profile "${COMPOSE_PROFILE}" \
    down --remove-orphans
