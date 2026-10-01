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
# shellcheck source=lib/runtime.sh
source "${SCRIPT_DIR}/lib/runtime.sh"
# shellcheck source=lib/download.sh
source "${SCRIPT_DIR}/lib/download.sh"
# shellcheck source=lib/metrics.sh
source "${SCRIPT_DIR}/lib/metrics.sh"
# shellcheck source=lib/serve.sh
source "${SCRIPT_DIR}/lib/serve.sh"
# shellcheck source=lib/tools.sh
source "${SCRIPT_DIR}/lib/tools.sh"
# shellcheck source=lib/ui.sh
source "${SCRIPT_DIR}/lib/ui.sh"

case "${1:-}" in
  status)         cmd_status ;;
  select)         cmd_select ;;
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
