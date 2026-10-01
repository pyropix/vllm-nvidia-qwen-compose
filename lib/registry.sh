# shellcheck shell=bash
# Registry module: loading models.json, Model ID and Variant lookup and
# MODEL_ID[:variant] parsing. Sourced by vllm-serve.sh, which sets MODELS_FILE.

require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required to read ${MODELS_FILE}." >&2
        echo "Install it with: ./setup-cli.sh jq-install" >&2
        exit 1
    fi
}

# Fill the 'models' array with one "MODEL_ID[:variant]" entry per Service.
registry_load() {
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

# Split a "MODEL_ID[:variant]" entry into ENTRY_MODEL_ID and ENTRY_VARIANT (empty without one).
# shellcheck disable=SC2034  # results are read by the caller
registry_parse_entry() {
    ENTRY_MODEL_ID="${1%%:*}"
    ENTRY_VARIANT=""
    [[ "$1" == *:* ]] && ENTRY_VARIANT="${1#*:}"
    return 0
}

# Print the Draft model of a Model ID (empty when it has none).
registry_draft() {
    require_jq
    jq -r --arg id "$1" '.[] | select(.id == $id) | .draft // empty' "${MODELS_FILE}"
}

# Print the context window of a Model ID (empty when the registry lacks one).
registry_context() {
    require_jq
    jq -r --arg id "$1" '.[] | select(.id == $id) | .context // empty' "${MODELS_FILE}"
}
