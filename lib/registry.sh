# shellcheck shell=bash
# Registry module: loading models.json, Model ID and Variant lookup and
# MODEL_ID[:variant] parsing. Sourced by vllm-serve.sh.
# Requires (from vllm-serve.sh or other modules; checked by tests/test_modules.sh):
# Requires: MODELS_FILE

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
    mapfile -t models < <(jq -r '.[] | .id, (.id + ":" + (.variants // [])[].name)' "${MODELS_FILE}")
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
