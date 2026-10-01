# shellcheck shell=bash
# Readiness and status module: the vLLM URL, the /v1/models ready check,
# running-service detection and status rendering. Sourced by vllm-serve.sh.
require_defined ENV_FILE MODELS_FILE load_env compose download_state || return 1
require_defined registry_load registry_draft registry_context registry_lookup_service || return 1

# host:port vLLM listens on; all variants share it. The shell scripts take it from here.
VLLM_ADDR="localhost:8000"
VLLM_MODELS_URL="http://${VLLM_ADDR}/v1/models"

# Print the GET /v1/models response; fails while vLLM does not answer.
query_models() {
  curl -fsS --max-time 5 "${VLLM_MODELS_URL}" 2>/dev/null
}

# Print the model ids of a /v1/models response on stdin, one per line.
served_model_ids() {
  jq -r '.data[].id'
}

# Print the Ready state: "yes (model ids)" or "no (still starting?)".
ready_summary() {
  local response ids
  if response="$(query_models)"; then
    ids="$(served_model_ids <<<"${response}")"
    echo "yes (${ids//$'\n'/, })"
  else
    echo "no (still starting?)"
  fi
}

# Print the running vLLM services (one per line).
running_vllm_services() {
  local svc
  while IFS= read -r svc; do
    [[ "${svc}" == vllm-* ]] && echo "${svc}"
  done < <(compose --profile '*' ps --status running --format '{{.Service}}')
  return 0
}

cmd_status() {
  load_env
  registry_load
  local fmt="  %-10s %s\n"
  echo ""
  echo "Selected (${ENV_FILE})"
  printf "${fmt}" "Model" "${MODEL_ID:--}"
  printf "${fmt}" "Variant" "${MODEL_VARIANT:--}"
  # Draft and Download both come from the registry, not from a possibly stale .env.vllm.
  local draft="" context="" download="-"
  if [[ -n "${MODEL_ID:-}" ]]; then
    draft="$(registry_draft "${MODEL_ID}")"
    context="$(registry_context "${MODEL_ID}")"
    download="$(download_state "${MODEL_ID}")"
  fi
  printf "${fmt}" "Draft" "${draft:--}"
  printf "${fmt}" "Context" "${context:--}"
  printf "${fmt}" "Download" "${download}"
  echo ""
  echo "Downloads (all Model IDs in ${MODELS_FILE})"
  local id
  while IFS= read -r id; do
    printf "  %s  %s\n" "${id}" "$(download_state "${id}")"
  done < <(jq -r '.[].id' "${MODELS_FILE}")
  echo ""
  echo "Running"
  local running=() svc model_id variant owner
  while IFS= read -r svc; do
    running+=("${svc}")
  done < <(running_vllm_services)
  if (( ${#running[@]} == 0 )); then
    printf "${fmt}" "Container" "none running"
    echo ""
    return
  fi
  for svc in "${running[@]}"; do
    owner="$(registry_lookup_service "${svc}")"
    if [[ -z "${owner}" ]]; then
      printf "${fmt}" "Container" "${svc} (not in models.json)"
      continue
    fi
    IFS=$'\t' read -r model_id variant <<<"${owner}"
    printf "${fmt}" "Container" "${svc}"
    printf "${fmt}" "Model" "${model_id}"
    printf "${fmt}" "Variant" "${variant:--}"
    printf "${fmt}" "Draft" "$(registry_draft "${model_id}")"
    [[ "${model_id}" == "${MODEL_ID:-}" && "${variant}" == "${MODEL_VARIANT:-}" ]] \
      && printf "${fmt}" "Selected" "yes" \
      || printf "${fmt}" "Selected" "no (differs from selection)"
  done
  # All variants share host port 8000, so one readiness line covers them.
  printf "${fmt}" "Ready" "$(ready_summary)"
  echo ""
}

# Check whether vLLM answers GET /v1/models; with --wait, poll until it does.
cmd_ready() {
  local wait="" response ids
  [[ "${1:-}" == "--wait" ]] && wait=1
  while true; do
    if response="$(query_models)"; then
      # Capture first: piping into sed would hide a jq failure.
      ids="$(served_model_ids <<<"${response}")" || return 1
      echo "vLLM is ready. Models:"
      sed 's/^/  /' <<<"${ids}"
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
