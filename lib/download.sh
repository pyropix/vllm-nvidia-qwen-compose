# shellcheck shell=bash
# Download module: the Download completeness check, what a Model ID needs and the download command.
# Sourced by vllm-serve.sh, which provides load_env, check_registry_env and the registry module.

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
