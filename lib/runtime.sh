# shellcheck shell=bash
# Runtime module: .env.vllm, the docker compose wrapper and the selected Service.
# Sourced by vllm-serve.sh.
require_defined SCRIPT_DIR ENV_FILE MODELS_FILE registry_draft registry_context registry_service || return 1

load_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Error: ${ENV_FILE} not found." >&2
    echo "Copy .env.vllm.example to .env.vllm and set your HF_TOKEN first." >&2
    exit 1
  fi
  # shellcheck source=.env.vllm
  source "${ENV_FILE}"
}

set_env_var() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    echo "${key}=${value}" >> "${ENV_FILE}"
  fi
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
