#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.vllm"
MODELS_FILE="${SCRIPT_DIR}/models.json"

require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required to read ${MODELS_FILE}." >&2
        echo "Install it with: ./setup-cli.sh jq-install" >&2
        exit 1
    fi
}

# Fill the 'models' array with one "MODEL_ID[:variant]" entry per Service.
load_models() {
    if [[ ! -f "${MODELS_FILE}" ]]; then
        echo "Error: ${MODELS_FILE} not found." >&2
        exit 1
    fi
    require_jq
    models=()
    mapfile -t models < <(jq -r '.[] | .id, (.id + ":" + (.variants // [])[])' "${MODELS_FILE}")
    if [[ "${#models[@]}" -eq 0 ]]; then
        echo "Error: no models defined in ${MODELS_FILE}." >&2
        exit 1
    fi
}

# Print the Draft model of a Model ID (empty when it has none).
get_draft() {
    require_jq
    jq -r --arg id "$1" '.[] | select(.id == $id) | .draft // empty' "${MODELS_FILE}"
}

# Fail when the registry declares a Draft model that .env.vllm does not carry.
check_draft() {
    local expected
    expected="$(get_draft "${MODEL_ID}")"
    if [[ "${expected}" != "${DRAFT_MODEL_ID:-}" ]]; then
        echo "Error: DRAFT_MODEL_ID in ${ENV_FILE} (${DRAFT_MODEL_ID:-unset}) does not match ${MODELS_FILE} (${expected:-none})." >&2
        echo "Run $(basename "$0") select again." >&2
        exit 1
    fi
}

# Succeed when a repo is fully present in the local HF cache (offline check).
is_downloaded() {
    local repo_dir="${HOME}/.cache/huggingface/hub/models--${1//\//--}" rev snapshot shard
    [[ -f "${repo_dir}/refs/main" ]] || return 1
    rev="$(<"${repo_dir}/refs/main")"
    snapshot="${repo_dir}/snapshots/${rev}"
    [[ -d "${snapshot}" ]] || return 1
    # Interrupted downloads leave *.incomplete blobs behind.
    compgen -G "${repo_dir}/blobs/*.incomplete" >/dev/null && return 1
    # Every symlinked file must resolve to a blob.
    [[ -z "$(find -L "${snapshot}" -type l)" ]] || return 1
    # Every shard listed in the weight index must be present.
    if [[ -f "${snapshot}/model.safetensors.index.json" ]]; then
        while IFS= read -r shard; do
            [[ -f "${snapshot}/${shard}" ]] || return 1
        done < <(jq -r '.weight_map[]' "${snapshot}/model.safetensors.index.json" | sort -u)
    fi
    compgen -G "${snapshot}/*.safetensors" >/dev/null
}

# Fail when the Download of the selected Model ID (weights plus Draft model) is incomplete.
check_downloaded() {
    local repo
    for repo in "${MODEL_ID}" ${DRAFT_MODEL_ID:+"${DRAFT_MODEL_ID}"}; do
        if ! is_downloaded "${repo}"; then
            echo "Error: ${repo} is not fully downloaded." >&2
            echo "Run $(basename "$0") download first." >&2
            exit 1
        fi
    done
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

# Print the docker-compose service name for a Model ID and optional variant.
derive_service() {
    local model_id="$1" variant="${2:-}"
    # Derive the docker-compose service/profile name from the Hugging Face
    # MODEL_ID: map the org prefix (before the first '/') to a short tag
    # (nvidia -> nv, unsloth -> us), strip the org, lowercase the leading
    # character and prefix with 'vllm-<tag>-'.
    #   e.g. nvidia/Qwen3.6-27B-NVFP4  -> vllm-nv-qwen3.6-27B-NVFP4
    #        unsloth/Qwen3.8-27B-NVFP4 -> vllm-us-qwen3.8-27B-NVFP4
    # Any model listed in models.json must follow this convention.
    local org="${model_id%%/*}"
    local tag
    case "${org}" in
        nvidia)  tag="nv" ;;
        unsloth) tag="us" ;;
        *)
            echo "Error: unknown org '${org}' in MODEL_ID '${model_id}'." >&2
            echo "Add it to the org-to-tag mapping in get_service()." >&2
            exit 1
            ;;
    esac
    local name="${model_id#*/}"
    local first="${name:0:1}"
    first="${first,,}"
    local service="vllm-${tag}-${first}${name:1}"
    # An optional MODEL_VARIANT (a 'variants' entry in models.json)
    # selects a parallel service for the same model, e.g.
    #   nvidia/Qwen3.8-27B-NVFP4 + variant instanttensor
    #     -> vllm-nv-qwen3.8-27B-NVFP4-instanttensor
    [[ -n "${variant}" ]] && service="${service}-${variant}"
    echo "${service}"
}

get_service() {
    local model_id="${MODEL_ID:-}"
    if [[ -z "${model_id}" ]]; then
        echo "Error: MODEL_ID is not set. Run '$(basename "$0") select' first." >&2
        exit 1
    fi
    local service
    service="$(derive_service "${model_id}" "${MODEL_VARIANT:-}")"
    # Guard against a derived name that has no matching compose service.
    local escaped="${service//./\\.}"
    if ! grep -Eq "^[[:space:]]+${escaped}:" "${SCRIPT_DIR}/docker-compose.yml"; then
        echo "Error: no docker-compose service '${service}' for MODEL_ID '${model_id}'." >&2
        echo "Add a matching service to docker-compose.yml or fix the naming convention." >&2
        exit 1
    fi
    echo "${service}"
}

get_profile() {
    get_service
}

set_env_var() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "${ENV_FILE}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
    else
        echo "${key}=${value}" >> "${ENV_FILE}"
    fi
}

cmd_select() {
    load_env
    load_models
    echo ""
    echo "Select the model to download and serve:"
    echo ""
    local entry model_id variant="" draft
    select entry in "${models[@]}"; do
        [[ -n "${entry}" ]] && break
        echo "Invalid selection. Enter a number between 1 and ${#models[@]}."
    done
    # Entries are 'MODEL_ID' or 'MODEL_ID:variant'.
    model_id="${entry%%:*}"
    [[ "${entry}" == *:* ]] && variant="${entry#*:}"
    draft="$(get_draft "${model_id}")"
    set_env_var MODEL_ID "${model_id}"
    set_env_var MODEL_VARIANT "${variant}"
    set_env_var DRAFT_MODEL_ID "${draft}"
    echo "Updated ${ENV_FILE} with MODEL_ID=${model_id} MODEL_VARIANT=${variant} DRAFT_MODEL_ID=${draft}"
}

VLLM_MODELS_URL="http://localhost:8000/v1/models"

# Print the GET /v1/models response; fails while vLLM does not answer.
query_models() {
    curl -fsS --max-time 5 "${VLLM_MODELS_URL}" 2>/dev/null
}

cmd_status() {
    load_env
    load_models
    local fmt="  %-10s %s\n"
    echo ""
    echo "Selected (${ENV_FILE})"
    printf "${fmt}" "Model" "${MODEL_ID:--}"
    printf "${fmt}" "Variant" "${MODEL_VARIANT:--}"
    printf "${fmt}" "Draft" "${DRAFT_MODEL_ID:--}"
    echo ""
    echo "Running"
    local running=() svc entry model_id variant found
    while IFS= read -r svc; do
        [[ "${svc}" == vllm-* ]] && running+=("${svc}")
    done < <(docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        --profile '*' \
        ps --status running --format '{{.Service}}')
    if (( ${#running[@]} == 0 )); then
        printf "${fmt}" "Container" "none running"
        echo ""
        return
    fi
    for svc in "${running[@]}"; do
        found=""
        for entry in "${models[@]}"; do
            model_id="${entry%%:*}"
            variant=""
            [[ "${entry}" == *:* ]] && variant="${entry#*:}"
            if [[ "$(derive_service "${model_id}" "${variant}")" == "${svc}" ]]; then
                found=1
                printf "${fmt}" "Container" "${svc}"
                printf "${fmt}" "Model" "${model_id}"
                printf "${fmt}" "Variant" "${variant:--}"
                printf "${fmt}" "Draft" "$(get_draft "${model_id}")"
                [[ "${model_id}" == "${MODEL_ID:-}" && "${variant}" == "${MODEL_VARIANT:-}" ]] \
                    && printf "${fmt}" "Selected" "yes" \
                    || printf "${fmt}" "Selected" "no (differs from selection)"
                break
            fi
        done
        [[ -n "${found}" ]] || printf "${fmt}" "Container" "${svc} (not in models.json)"
    done
    # All variants share host port 8000, so one readiness line covers them.
    local response
    if response="$(query_models)"; then
        printf "${fmt}" "Ready" "yes ($(jq -r '[.data[].id] | join(", ")' <<<"${response}"))"
    else
        printf "${fmt}" "Ready" "no (still starting?)"
    fi
    echo ""
}

# Check whether vLLM answers GET /v1/models; with --wait, poll until it does.
cmd_ready() {
    local wait="" response
    [[ "${1:-}" == "--wait" ]] && wait=1
    while true; do
        if response="$(query_models)"; then
            echo "vLLM is ready. Models:"
            jq -r '.data[].id | "  " + .' <<<"${response}"
            return 0
        fi
        if [[ -z "${wait}" ]]; then
            echo "vLLM is not ready (no answer from ${VLLM_MODELS_URL})." >&2
            return 1
        fi
        echo "Waiting for vLLM... (Ctrl+C to abort)"
        sleep 5
    done
}

cmd_download() {
    load_env
    if [[ -z "${HF_TOKEN:-}" ]]; then
        echo "Error: HF_TOKEN not set in ${ENV_FILE}." >&2
        exit 1
    fi
    check_draft
    hf auth login --token "${HF_TOKEN}"
    hf download "${MODEL_ID}"
    if [[ -n "${DRAFT_MODEL_ID:-}" ]]; then
        hf download "${DRAFT_MODEL_ID}"
    fi
    unset HF_TOKEN
    hf auth logout
}

cmd_start() {
    load_env
    check_draft
    check_downloaded
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
    # All variants bind host port 8000, so only one can run at a time.
    local other others=()
    while IFS= read -r other; do
        [[ "${other}" == vllm-* && "${other}" != "${service}" ]] && others+=("${other}")
    done < <(docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        --profile '*' \
        ps --all --format '{{.Service}}')
    if (( ${#others[@]} > 0 )); then
        echo "Stopping other variants: ${others[*]}"
        docker compose \
            --project-directory "${SCRIPT_DIR}" \
            --env-file "${ENV_FILE}" \
            --profile '*' \
            rm --stop --force "${others[@]}"
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

cmd_pi() {
    load_env
    # The Model ID contains '/', so name the provider explicitly or pi reads
    # the org (nvidia/unsloth) as the provider.
    pi --provider vllm-qwen --model "${MODEL_ID}"
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
    echo "Usage: $(basename "$0") [status|select|download|start|logs|ready|stop|pi|link|unlink]"
    echo ""
    echo "  status    Show selected model/variant/Draft and the running container"
    echo "  select    Pick model variant and write to .env.vllm"
    echo "  download  Login to HF and download model weights (and Draft model)"
    echo "  start     Pull image and start the vLLM container"
    echo "  logs      Tail the running container logs"
    echo "  ready     Check if vLLM answers GET /v1/models (--wait: poll until it does)"
    echo "  stop      Stop and remove the container"
    echo "  pi        Launch pi agent pointed at the local vLLM server"
    echo "  link      Symlink this script as 'vllm-serve' in ~/.local/bin"
    echo "  unlink    Remove the 'vllm-serve' symlink from ~/.local/bin"
    echo ""
    echo "Run without arguments for an interactive menu."
}

menu() {
    local actions=("show status" "select model" "login & download model" "start vllm" "show logs" "check if vllm is ready" "stop vllm" "start pi agent" "create 'vllm-serve' symlink" "remove 'vllm-serve' symlink")
    cmd_status
    while true; do
        echo ""
        echo "vLLM management — choose an action:"
        echo "  (type 'q' to quit)"
        select action in "${actions[@]}"; do
            if [[ "${REPLY}" == "q" ]]; then
                return
            fi
            case "${action}" in
                "show status")    cmd_status ;;
                "select model")   cmd_select ;;
                "login & download model") cmd_download ;;
                "start vllm")     cmd_start || true ;;
                "show logs")      cmd_logs ;;
                "check if vllm is ready") cmd_ready || true ;;
                "stop vllm")      cmd_stop ;;
                "start pi agent") cmd_pi ;;
                "create 'vllm-serve' symlink") cmd_link ;;
                "remove 'vllm-serve' symlink") cmd_unlink ;;
                *)                echo "Invalid selection." ;;
            esac
            break
        done
    done
}

case "${1:-}" in
    status)         cmd_status ;;
    select)        cmd_select ;;
    download)       cmd_download ;;
    start)          cmd_start ;;
    logs)           cmd_logs ;;
    ready)          cmd_ready "${2:-}" ;;
    stop)           cmd_stop ;;
    pi)             cmd_pi ;;
    link)           cmd_link ;;
    unlink)         cmd_unlink ;;
    help|--help|-h) usage ;;
    "")             menu ;;
    *)              echo "Unknown command: $1" >&2; usage >&2; exit 1 ;;
esac
