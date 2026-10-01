#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.vllm"
MODELS_FILE="${SCRIPT_DIR}/models.json"
TARGETS_FILE="${SCRIPT_DIR}/monitoring/targets/vllm.json"

# shellcheck source=lib/registry.sh
source "${SCRIPT_DIR}/lib/registry.sh"
# shellcheck source=lib/status.sh
source "${SCRIPT_DIR}/lib/status.sh"

# Fail when .env.vllm disagrees with the registry on the Draft model or context window.
check_registry_env() {
    local expected
    expected="$(registry_draft "${MODEL_ID}")"
    if [[ "${expected}" != "${DRAFT_MODEL_ID:-}" ]]; then
        echo "Error: DRAFT_MODEL_ID in ${ENV_FILE} (${DRAFT_MODEL_ID:-unset}) does not match ${MODELS_FILE} (${expected:-none})." >&2
        echo "Run $(basename "$0") select again." >&2
        exit 1
    fi
    expected="$(registry_context "${MODEL_ID}")"
    if [[ -z "${expected}" ]]; then
        echo "Error: ${MODELS_FILE} has no context window for ${MODEL_ID}." >&2
        exit 1
    fi
    if [[ "${expected}" != "${MAX_MODEL_LEN:-}" ]]; then
        echo "Error: MAX_MODEL_LEN in ${ENV_FILE} (${MAX_MODEL_LEN:-unset}) does not match ${MODELS_FILE} (${expected:-none})." >&2
        echo "Run $(basename "$0") select again." >&2
        exit 1
    fi
}

# Succeed when a repo is fully present in the local HF cache (offline check).
is_downloaded() {
    local repo_dir="${HOME}/.cache/huggingface/hub/models--${1//\//--}" rev snapshot shard index link
    [[ -f "${repo_dir}/refs/main" ]] || return 1
    rev="$(<"${repo_dir}/refs/main")"
    snapshot="${repo_dir}/snapshots/${rev}"
    [[ -d "${snapshot}" ]] || return 1
    # Every symlinked file must resolve to a blob.
    [[ -z "$(find -L "${snapshot}" -type l)" ]] || return 1
    # An interrupted download leaves <blob>.incomplete behind. Only one for a blob
    # this revision links to counts; stale ones from other revisions are ignored.
    while IFS= read -r link; do
        [[ ! -e "${repo_dir}/blobs/$(basename "$(readlink "${link}")").incomplete" ]] || return 1
    done < <(find "${snapshot}" -type l)
    # A file with no snapshot symlink yet (config.json, tokenizer) leaves an
    # <blob>.incomplete no link points to. hf writes refs/main before it fetches
    # files, so one at least as new as refs/main belongs to this revision; an
    # older one is a stale leftover of another revision and is ignored.
    while IFS= read -r link; do
        [[ "${repo_dir}/refs/main" -nt "${link}" ]] || return 1
    done < <(find "${repo_dir}/blobs" -name '*.incomplete' 2>/dev/null)
    # Every shard listed in a safetensors weight index must be present. A malformed
    # index (not JSON, or no non-empty weight_map of shard names) is incomplete.
    for index in "${snapshot}"/*.safetensors.index.json; do
        [[ -f "${index}" ]] || continue
        jq -e '.weight_map | type == "object" and length > 0 and all(.[]; type == "string")' \
            "${index}" >/dev/null 2>&1 || return 1
        while IFS= read -r shard; do
            [[ -f "${snapshot}/${shard}" ]] || return 1
        done < <(jq -r '.weight_map[]' "${index}" | sort -u)
    done
    # At least one safetensors file. Every Model ID and Draft model in the registry
    # ships safetensors, so other weight formats are not supported.
    compgen -G "${snapshot}/*.safetensors" >/dev/null
}

# Download module: what a Model ID needs and whether it is all present.
# Print the repos a Model ID's Download needs: its weights, then its Draft model.
download_repos() {
    local draft
    echo "$1"
    draft="$(registry_draft "$1")"
    [[ -z "${draft}" ]] || echo "${draft}"
}

# Print the repos of a Model ID's Download that are not fully present (one per line).
download_missing() {
    local repo
    while IFS= read -r repo; do
        is_downloaded "${repo}" || echo "${repo}"
    done < <(download_repos "$1")
}

# Fail when the Download of the selected Model ID (weights plus Draft model) is incomplete.
check_downloaded() {
    local repo missing
    missing="$(download_missing "${MODEL_ID}")"
    [[ -z "${missing}" ]] && return 0
    while IFS= read -r repo; do
        echo "Error: ${repo} is not fully downloaded." >&2
    done <<<"${missing}"
    echo "Run $(basename "$0") download first." >&2
    exit 1
}

# Print the Download state of a Model ID: "complete" or "incomplete (missing: ...)".
download_state() {
    local missing
    missing="$(download_missing "$1")"
    if [[ -z "${missing}" ]]; then
        echo "complete"
    else
        echo "incomplete (missing: ${missing//$'\n'/ })"
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

# Print the docker-compose service name the registry stores for a Model ID and
# optional variant (empty when the registry has none).
registry_service() {
    require_jq
    jq -r --arg id "$1" --arg variant "${2:-}" '
        .[] | select(.id == $id)
        | if $variant == "" then .service
          else (.variants // [])[] | select(.name == $variant) | .service end
        // empty' "${MODELS_FILE}"
}

# Print "MODEL_ID<TAB>variant" for the registry entry that owns a service
# (empty when no entry does).
registry_lookup_service() {
    require_jq
    jq -r --arg svc "$1" '
        .[] | . as $m
        | ({id: $m.id, variant: "", service: $m.service},
           (($m.variants // [])[] | {id: $m.id, variant: .name, service: .service}))
        | select(.service == $svc) | [.id, .variant] | @tsv' "${MODELS_FILE}" | head -n 1
}

get_service() {
    local model_id="${MODEL_ID:-}"
    if [[ -z "${model_id}" ]]; then
        echo "Error: MODEL_ID is not set. Run '$(basename "$0") select' first." >&2
        exit 1
    fi
    local service
    service="$(registry_service "${model_id}" "${MODEL_VARIANT:-}")"
    if [[ -z "${service}" ]]; then
        echo "Error: ${MODELS_FILE} has no service for MODEL_ID '${model_id}'${MODEL_VARIANT:+ variant '${MODEL_VARIANT}'}." >&2
        exit 1
    fi
    # Guard against a registry service name that has no matching compose service.
    local escaped="${service//./\\.}"
    if ! grep -Eq "^[[:space:]]+${escaped}:" "${SCRIPT_DIR}/docker-compose.yml"; then
        echo "Error: no docker-compose service '${service}' for MODEL_ID '${model_id}'." >&2
        echo "Add a matching service to docker-compose.yml or fix the service name in ${MODELS_FILE}." >&2
        exit 1
    fi
    echo "${service}"
}

# Run docker compose against this checkout and its .env.vllm. Callers pass
# the rest (--profile, subcommand, ...).
compose() {
    # docker-compose.yml requires MAX_MODEL_LEN for every service (even inactive
    # profiles), so a stale .env.vllm would break stop/status/down. The commands
    # that serve guard it via check_registry_env; give the rest a placeholder.
    MAX_MODEL_LEN="${MAX_MODEL_LEN:-0}" docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${ENV_FILE}" \
        "$@"
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
    registry_load
    echo ""
    echo "Select the model to download and serve:"
    echo ""
    local entry model_id variant draft context
    select entry in "${models[@]}"; do
        [[ -n "${entry}" ]] && break
        echo "Invalid selection. Enter a number between 1 and ${#models[@]}."
    done
    registry_parse_entry "${entry}"
    model_id="${ENTRY_MODEL_ID}"
    variant="${ENTRY_VARIANT}"
    draft="$(registry_draft "${model_id}")"
    context="$(registry_context "${model_id}")"
    set_env_var MODEL_ID "${model_id}"
    set_env_var MODEL_VARIANT "${variant}"
    set_env_var DRAFT_MODEL_ID "${draft}"
    set_env_var MAX_MODEL_LEN "${context}"
    echo "Updated ${ENV_FILE} with MODEL_ID=${model_id} MODEL_VARIANT=${variant} DRAFT_MODEL_ID=${draft} MAX_MODEL_LEN=${context}"
}

cmd_download() {
    load_env
    if [[ -z "${HF_TOKEN:-}" ]]; then
        echo "Error: HF_TOKEN not set in ${ENV_FILE}." >&2
        exit 1
    fi
    check_registry_env
    local missing repo
    missing="$(download_missing "${MODEL_ID}")"
    if [[ -z "${missing}" ]]; then
        echo "${MODEL_ID} is already downloaded."
        return 0
    fi
    hf auth login --token "${HF_TOKEN}"
    local status=0
    while IFS= read -r repo; do
        hf download "${repo}" || { status=$?; break; }
    done <<<"${missing}"
    # Log out even when a download failed, so the token is not left behind.
    unset HF_TOKEN
    hf auth logout
    return "${status}"
}

# Metrics module: label vLLM's scrape target with the current Run.
# A Run is identified by its start time, Model ID and Variant; the label
# "run" combines them (e.g. "20261001-1430 nvidia/Qwen3.8-27B-NVFP4:instanttensor")
# with the start time first so the newest Run sorts first in Grafana.
write_run_target() {
    require_jq
    local run_start run tmp="${TARGETS_FILE}.tmp"
    run_start="$(date +%Y%m%d-%H%M)"
    run="${run_start} ${MODEL_ID}${MODEL_VARIANT:+:${MODEL_VARIANT}}"
    mkdir -p "$(dirname "${TARGETS_FILE}")"
    jq -n --arg id "${MODEL_ID}" --arg variant "${MODEL_VARIANT:-}" \
        --arg run_start "${run_start}" --arg run "${run}" \
        --arg target "${VLLM_HOST}" \
        '[{targets: [$target],
           labels: {model_id: $id, variant: $variant, run_start: $run_start, run: $run}}]' >"${tmp}"
    # Rename so Prometheus never reads a half-written file.
    mv "${tmp}" "${TARGETS_FILE}"
}

clear_run_target() {
    rm -f "${TARGETS_FILE}"
}

cmd_start() {
    load_env
    check_registry_env
    check_downloaded
    local service
    service="$(get_service)"
    if compose --profile "${service}" ps "${service}" --status running --format '{{.Service}}' | grep -q "^${service}$"; then
        echo "Error: ${service} is already running." >&2
        echo "Stop it first with $(basename "$0") stop." >&2
        return 1
    fi
    # All variants bind host port 8000, so only one can run at a time.
    local other others=()
    while IFS= read -r other; do
        [[ "${other}" == vllm-* && "${other}" != "${service}" ]] && others+=("${other}")
    done < <(compose --profile '*' ps --all --format '{{.Service}}')
    if (( ${#others[@]} > 0 )); then
        echo "Stopping other variants: ${others[*]}"
        compose --profile '*' rm --stop --force "${others[@]}"
    fi
    compose --profile "${service}" pull
    write_run_target
    compose --profile "${service}" up --detach --remove-orphans
}

cmd_logs() {
    load_env
    local service
    service="$(get_service)"
    compose logs "${service}" --follow
}

# Stop vLLM, keeping Prometheus and Grafana up so the finished Run stays
# browsable; --all takes monitoring down too (metrics history is kept).
cmd_stop() {
    load_env
    local service all=""
    [[ "${1:-}" == "--all" ]] && all=1
    service="$(get_service)"
    clear_run_target
    if [[ -n "${all}" ]]; then
        compose --profile "${service}" down --remove-orphans
    else
        compose --profile "${service}" rm --stop --force "${service}"
    fi
}

# Delete all recorded metrics history (Prometheus and Grafana volumes).
cmd_reset_metrics() {
    load_env
    local yes="" running answer
    [[ "${1:-}" == "--yes" ]] && yes=1
    running="$(running_vllm_services)"
    if [[ -n "${running}" ]]; then
        echo "Error: vLLM is running (${running//$'\n'/ }); its Run would lose its history." >&2
        echo "Stop it first with $(basename "$0") stop." >&2
        return 1
    fi
    if [[ -z "${yes}" ]]; then
        read -r -p "Delete ALL metrics history (Prometheus and Grafana data)? [y/N] " answer || answer=""
        if [[ "${answer}" != [yY] ]]; then
            echo "Aborted."
            return 1
        fi
    fi
    clear_run_target
    compose --profile '*' down --volumes --remove-orphans
    echo "Metrics history deleted. The next start begins with an empty history."
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
    echo "Usage: $(basename "$0") [status|select|download|start|logs|ready|stop|reset-metrics|pi|link|unlink]"
    echo ""
    echo "  status    Show selected model/variant/Draft, every Model ID's Download state and the running container"
    echo "  select    Pick model variant and write to .env.vllm"
    echo "  download  Login to HF and download model weights (and Draft model)"
    echo "  start     Pull image and start the vLLM container"
    echo "  logs      Tail the running container logs"
    echo "  ready     Check if vLLM answers GET /v1/models (--wait: poll until it does)"
    echo "  stop      Stop and remove the vLLM container; Prometheus and Grafana keep running"
    echo "            (--all: stop them too; metrics history is kept)"
    echo "  reset-metrics  Delete all metrics history (--yes: skip the prompt; refused while vLLM runs)"
    echo "  pi        Launch pi agent pointed at the local vLLM server"
    echo "  link      Symlink this script as 'vllm-serve' in ~/.local/bin"
    echo "  unlink    Remove the 'vllm-serve' symlink from ~/.local/bin"
    echo ""
    echo "Run without arguments for an interactive menu."
}

menu() {
    local actions=("show status" "select model" "login & download model" "start vllm" "show logs" "check if vllm is ready" "stop vllm" "stop vllm and monitoring" "reset metrics history" "start pi agent" "create 'vllm-serve' symlink" "remove 'vllm-serve' symlink")
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
                "stop vllm and monitoring") cmd_stop --all ;;
                "reset metrics history") cmd_reset_metrics || true ;;
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
    stop)           cmd_stop "${2:-}" ;;
    reset-metrics)  cmd_reset_metrics "${2:-}" ;;
    pi)             cmd_pi ;;
    link)           cmd_link ;;
    unlink)         cmd_unlink ;;
    help|--help|-h) usage ;;
    "")             menu ;;
    *)              echo "Unknown command: $1" >&2; usage >&2; exit 1 ;;
esac
