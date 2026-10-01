# shellcheck shell=bash
# Tools module: the pi command and the vllm-serve symlink commands.
# Sourced by vllm-serve.sh.
require_defined SCRIPT_DIR load_env || return 1

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
