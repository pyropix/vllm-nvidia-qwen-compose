#!/usr/bin/env bash
set -euo pipefail

## Install / manage the Hugging Face CLI
# Source: https://huggingface.co/docs/huggingface_hub/en/guides/cli

HF_CLI_BIN="${HOME}/.local/bin/hf"
HF_CLI_DIR="${HF_HOME:+${HF_HOME}/cli}"
HF_CLI_DIR="${HF_CLI_DIR:-${HOME}/.hf-cli}"

cmd_install() {
    curl -LsSf https://hf.co/cli/install.sh | bash
}

cmd_reinstall() {
    curl -LsSf https://hf.co/cli/install.sh | bash -s -- --force
}

cmd_with_transformers() {
    curl -LsSf https://hf.co/cli/install.sh | bash -s -- --with-transformers
}

cmd_check() {
    if [[ -x "${HF_CLI_BIN}" ]]; then
        echo "hf CLI found at ${HF_CLI_BIN}"
        "${HF_CLI_BIN}" version
    else
        echo "hf CLI not installed (expected at ${HF_CLI_BIN})."
        exit 1
    fi
}

cmd_uninstall() {
    rm -f "${HF_CLI_BIN}"
    rm -rf "${HF_CLI_DIR}"
    echo "Removed ${HF_CLI_BIN} and ${HF_CLI_DIR}"
}

usage() {
    echo "Usage: $(basename "$0") [install|reinstall|with-transformers|check|uninstall]"
    echo ""
    echo "  install           Install the Hugging Face CLI (reuses existing venv if present)"
    echo "  reinstall         Recreate the Hugging Face CLI virtual environment (--force)"
    echo "  with-transformers Install the CLI with the transformers extra"
    echo "  check             Show whether the CLI is installed and its version"
    echo "  uninstall         Remove the hf CLI and its virtual environment"
    echo ""
    echo "Run without arguments for an interactive menu."
}

menu() {
    local actions=("install" "reinstall (force)" "install with transformers" "check installation" "uninstall" "quit")
    while true; do
        echo ""
        echo "Hugging Face CLI — choose an action:"
        echo ""
        select action in "${actions[@]}"; do
            case "${action}" in
                "install")                   cmd_install ;;
                "reinstall (force)")         cmd_reinstall ;;
                "install with transformers") cmd_with_transformers ;;
                "check installation")        cmd_check ;;
                "uninstall")                 cmd_uninstall ;;
                "quit")                      return ;;
                *)                           echo "Invalid selection." ;;
            esac
            break
        done
    done
}

case "${1:-}" in
    install)           cmd_install ;;
    reinstall)          cmd_reinstall ;;
    with-transformers)  cmd_with_transformers ;;
    check)              cmd_check ;;
    uninstall)          cmd_uninstall ;;
    help|--help|-h)     usage ;;
    "")                 menu ;;
    *)                  echo "Unknown command: $1" >&2; usage >&2; exit 1 ;;
esac
