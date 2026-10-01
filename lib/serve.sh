# shellcheck shell=bash
# Serve module: start, stop and logs of the vLLM container, plus the pi and symlink commands.
# Sourced by vllm-serve.sh.
# Requires (from vllm-serve.sh or other modules; checked by tests/test_modules.sh):
# Requires: SCRIPT_DIR load_env compose get_service check_registry_env check_downloaded
# Requires: write_run_target clear_run_target

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
