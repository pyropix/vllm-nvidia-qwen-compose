# shellcheck shell=bash
# UI module: the select and main menus and the usage text.
# Sourced by vllm-serve.sh.
# Requires (from vllm-serve.sh or other modules; checked by tests/test_modules.sh):
# Requires: ENV_FILE load_env set_env_var
# Requires: registry_load registry_parse_entry registry_draft registry_context
# Requires: cmd_status cmd_download cmd_start cmd_logs cmd_ready cmd_stop
# Requires: cmd_reset_metrics cmd_pi cmd_link cmd_unlink

cmd_select() {
  load_env
  registry_load
  echo ""
  echo "Select the model to download and serve:"
  echo ""
  local entry model_id variant draft context
  # shellcheck disable=SC2154 # models is filled by registry_load
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
