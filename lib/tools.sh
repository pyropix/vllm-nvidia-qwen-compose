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

# The vllm-serve symlink path, shared by cmd_link and cmd_unlink. A function,
# not a constant, so it follows HOME at call time.
link_path() { echo "${HOME}/.local/bin/vllm-serve"; }

cmd_link() {
  local link bin_dir
  link="$(link_path)"
  bin_dir="$(dirname "${link}")"
  mkdir -p "${bin_dir}"
  ln -sf "${SCRIPT_DIR}/vllm-serve.sh" "${link}"
  echo "Linked ${link} -> ${SCRIPT_DIR}/vllm-serve.sh"
  case ":${PATH}:" in
    *":${bin_dir}:"*) echo "Run 'vllm-serve' from anywhere." ;;
    *) echo "Warning: ${bin_dir} is not on your PATH. Add it to your shell profile." ;;
  esac
}

cmd_unlink() {
  local link
  link="$(link_path)"
  if [[ -L "${link}" ]]; then
    rm -f "${link}"
    echo "Removed symlink ${link}"
  else
    echo "No symlink found at ${link}"
  fi
}
