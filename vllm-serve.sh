#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.vllm"
MODELS_FILE="${SCRIPT_DIR}/models.conf"

load_models() {
    if [[ ! -f "${MODELS_FILE}" ]]; then
        echo "Error: ${MODELS_FILE} not found." >&2
        exit 1
    fi
    models=()
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(echo -n "${line}" | xargs)"
        [[ -n "${line}" ]] && models+=("${line}")
    done < "${MODELS_FILE}"
    if [[ "${#models[@]}" -eq 0 ]]; then
        echo "Error: no models defined in ${MODELS_FILE}." >&2
        exit 1
    fi
}

load_env() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        echo "Error: ${ENV_FILE} not found." >&2
        echo "Copy .env.vllm.example to .env.vllm and set your HF_TOKEN first." >&2
        exit 1
    fi
    # shellcheck source=.env.vllm
    source "${ENV_FILE}"
}

get_profile() {
    case "${MODEL_ID:-}" in
        nvidia/*)  echo "nvidia" ;;
        unsloth/*) echo "unsloth" ;;
        *) echo "Error: Unknown MODEL_ID prefix '${MODEL_ID}'. Expected nvidia/* or unsloth/*." >&2; exit 1 ;;
    esac
}

get_service() {
    case "${MODEL_ID:-}" in
        nvidia/*)  echo "vllm-qwen3.6-35B-A3B-NVFP4" ;;
        unsloth/*) echo "vllm-qwen3.6-35B-A3B-NVFP4-unsloth" ;;
        *) echo "Error: Unknown MODEL_ID prefix '${MODEL_ID}'." >&2; exit 1 ;;
    esac
}

cmd_select() {
    load_env
    load_models
    echo ""
    echo "Select the model to download and serve:"
    echo ""
    local model_id
    select model_id in "${models[@]}"; do
        [[ -n "${model_id}" ]] && break
        echo "Invalid selection. Enter a number between 1 and ${#models[@]}."
    done
    if grep -q "^MODEL_ID=" "${ENV_FILE}"; then
        sed -i "s|^MODEL_ID=.*|MODEL_ID=${model_id}|" "${ENV_FILE}"
    else
        echo "MODEL_ID=${model_id}" >> "${ENV_FILE}"
    fi
    echo "Updated ${ENV_FILE} with MODEL_ID=${model_id}"
}

cmd_download() {
    load_env
    if [[ -z "${HF_TOKEN:-}" ]]; then
        echo "Error: HF_TOKEN not set in ${ENV_FILE}." >&2
        exit 1
    fi
    hf auth login --token "${HF_TOKEN}"
    hf download "${MODEL_ID}"
    unset HF_TOKEN
    hf auth logout
}

cmd_start() {
    load_env
    local profile service
    profile="$(get_profile)"
    service="$(get_service)"
    if docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        --profile "${profile}" \
        ps "${service}" --status running --format '{{.Service}}' | grep -q "^${service}$"; then
        echo "Error: ${service} is already running." >&2
        echo "Stop it first with $(basename "$0") stop." >&2
        return 1
    fi
    docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        --profile "${profile}" \
        pull
    docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        --profile "${profile}" \
        up --detach --remove-orphans
}

cmd_logs() {
    load_env
    local service
    service="$(get_service)"
    docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        logs "${service}" --follow
}

cmd_stop() {
    load_env
    local profile
    profile="$(get_profile)"
    docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        --profile "${profile}" \
        down --remove-orphans
}

cmd_claude() {
    load_env
    ANTHROPIC_BASE_URL=http://localhost:8000 \
    ANTHROPIC_API_KEY=vllm \
    ANTHROPIC_AUTH_TOKEN=vllm \
    claude --model "${MODEL_ID}"
}

cmd_link() {
    local bin_dir="${HOME}/.local/bin"
    local link_path="${bin_dir}/vllm-serve"
    mkdir -p "${bin_dir}"
    ln -sf "${SCRIPT_DIR}/vllm-serve.sh" "${link_path}"
    echo "Linked ${link_path} -> ${SCRIPT_DIR}/vllm-serve.sh"
    case ":${PATH}:" in
        *":${bin_dir}:"*) echo "Run 'vllm-serve' from anywhere." ;;
        *) echo "Warning: ${bin_dir} is not on your PATH. Add it to your shell profile." ;;
    esac
}

cmd_unlink() {
    local link_path="${HOME}/.local/bin/vllm-serve"
    if [[ -L "${link_path}" ]]; then
        rm -f "${link_path}"
        echo "Removed symlink ${link_path}"
    else
        echo "No symlink found at ${link_path}"
    fi
}

usage() {
    echo "Usage: $(basename "$0") [select|download|start|logs|stop|claude|link|unlink]"
    echo ""
    echo "  select    Pick model variant and write to .env.vllm"
    echo "  download  Login to HF and download model weights"
    echo "  start     Pull image and start the vLLM container"
    echo "  logs      Tail the running container logs"
    echo "  stop      Stop and remove the container"
    echo "  claude    Launch Claude Code pointed at the local vLLM server"
    echo "  link      Symlink this script as 'vllm-serve' in ~/.local/bin"
    echo "  unlink    Remove the 'vllm-serve' symlink from ~/.local/bin"
    echo ""
    echo "Run without arguments for an interactive menu."
}

menu() {
    local actions=("select model" "login & download model" "start vllm" "show logs" "stop vllm" "start claude code" "create 'vllm-serve' symlink" "remove 'vllm-serve' symlink" "quit")
    while true; do
        echo ""
        echo "vLLM management — choose an action:"
        echo "  (or type 'q' to quit)"
        select action in "${actions[@]}"; do
            if [[ "${REPLY}" == "q" ]]; then
                return
            fi
            case "${action}" in
                "select model")   cmd_select ;;
                "login & download model") cmd_download ;;
                "start vllm")     cmd_start || true ;;
                "show logs")      cmd_logs ;;
                "stop vllm")      cmd_stop ;;
                "start claude code") cmd_claude ;;
                "create 'vllm-serve' symlink") cmd_link ;;
                "remove 'vllm-serve' symlink") cmd_unlink ;;
                "quit")           return ;;
                *)                echo "Invalid selection." ;;
            esac
            break
        done
    done
}

case "${1:-}" in
    select)         cmd_select ;;
    download)       cmd_download ;;
    start)          cmd_start ;;
    logs)           cmd_logs ;;
    stop)           cmd_stop ;;
    claude)         cmd_claude ;;
    link)           cmd_link ;;
    unlink)         cmd_unlink ;;
    help|--help|-h) usage ;;
    "")             menu ;;
    *)              echo "Unknown command: $1" >&2; usage >&2; exit 1 ;;
esac
