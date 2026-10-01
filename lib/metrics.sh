# shellcheck shell=bash
# Metrics module: the scrape target of the current Run and the metrics history.
# Sourced by vllm-serve.sh.
require_defined TARGETS_FILE VLLM_ADDR load_env compose require_jq running_vllm_services || return 1

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
    --arg target "${VLLM_ADDR}" \
    '[{targets: [$target],
           labels: {model_id: $id, variant: $variant, run_start: $run_start, run: $run}}]' >"${tmp}"
  # Rename so Prometheus never reads a half-written file.
  mv "${tmp}" "${TARGETS_FILE}"
}

clear_run_target() {
  rm -f "${TARGETS_FILE}"
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
