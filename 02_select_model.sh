#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.vllm"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Error: ${ENV_FILE} not found." >&2
    echo "Copy .env.vllm.example to .env.vllm and set your HF_TOKEN first." >&2
    exit 1
fi

MODELS=(
    "nvidia/Qwen3.6-35B-A3B-NVFP4"
    "unsloth/Qwen3.6-35B-A3B-NVFP4"
)

echo ""
echo "Select the model to download and serve:"
echo ""

select MODEL_ID in "${MODELS[@]}"; do
    if [[ -n "${MODEL_ID}" ]]; then
        break
    fi
    echo "Invalid selection. Please enter a number between 1 and ${#MODELS[@]}."
done

if [[ -z "${MODEL_ID:-}" ]]; then
    echo "No model selected. Exiting." >&2
    exit 1
fi

echo ""
echo "Selected: ${MODEL_ID}"

if grep -q "^MODEL_ID=" "${ENV_FILE}"; then
    sed -i "s|^MODEL_ID=.*|MODEL_ID=${MODEL_ID}|" "${ENV_FILE}"
else
    echo "MODEL_ID=${MODEL_ID}" >> "${ENV_FILE}"
fi

echo "Updated ${ENV_FILE} with MODEL_ID=${MODEL_ID}"
echo ""
