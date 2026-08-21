#!/usr/bin/env bash
set -euo pipefail

## Install / manage the Hugging Face CLI and pi agent CLI

HF_CLI_BIN="${HOME}/.local/bin/hf"
HF_CLI_DIR="${HF_HOME:+${HF_HOME}/cli}"
HF_CLI_DIR="${HF_CLI_DIR:-${HOME}/.hf-cli}"

PI_BIN="${HOME}/.local/bin/pi"
PI_VERSIONS_DIR="${HOME}/.local/share/pi"

## Hugging Face CLI
# Source: https://huggingface.co/docs/huggingface_hub/en/guides/cli

cmd_hf_install() {
    curl -LsSf https://hf.co/cli/install.sh | bash
}

cmd_hf_reinstall() {
    curl -LsSf https://hf.co/cli/install.sh | bash -s -- --force
}

cmd_hf_with_transformers() {
    curl -LsSf https://hf.co/cli/install.sh | bash -s -- --with-transformers
}

cmd_hf_check() {
    if [[ -x "${HF_CLI_BIN}" ]]; then
        echo "hf CLI found at ${HF_CLI_BIN}"
        "${HF_CLI_BIN}" version
    else
        echo "hf CLI not installed (expected at ${HF_CLI_BIN})."
        exit 1
    fi
}

cmd_hf_uninstall() {
    rm -f "${HF_CLI_BIN}"
    rm -rf "${HF_CLI_DIR}"
    echo "Removed ${HF_CLI_BIN} and ${HF_CLI_DIR}"
}

## pi agent CLI
# Source: https://pi.dev

cmd_pi_install() {
    curl -fsSL https://pi.dev/install.sh | sh
}

cmd_pi_check() {
    if [[ -x "${PI_BIN}" ]]; then
        echo "pi agent CLI found at ${PI_BIN}"
        "${PI_BIN}" --version
    else
        echo "pi agent CLI not installed (expected at ${PI_BIN})."
        exit 1
    fi
}

cmd_pi_update() {
    "${PI_BIN}" update
}

cmd_pi_uninstall() {
    rm -f "${PI_BIN}"
    rm -rf "${PI_VERSIONS_DIR}"
    echo "Removed ${PI_BIN} and ${PI_VERSIONS_DIR}"
    echo "Note: ~/.pi (config, credentials, history) was left in place."
}

usage() {
    echo "Usage: $(basename "$0") [hf-install|hf-reinstall|hf-with-transformers|hf-check|hf-uninstall|pi-install|pi-check|pi-update|pi-uninstall]"
    echo ""
    echo "Hugging Face CLI:"
    echo "  hf-install           Install the hf CLI (reuses existing venv if present)"
    echo "  hf-reinstall         Recreate the hf CLI virtual environment (--force)"
    echo "  hf-with-transformers Install the hf CLI with the transformers extra"
    echo "  hf-check             Show whether the hf CLI is installed and its version"
    echo "  hf-uninstall         Remove the hf CLI and its virtual environment"
    echo ""
    echo "pi agent CLI:"
    echo "  pi-install           Install the pi agent CLI"
    echo "  pi-check             Show whether the pi agent CLI is installed and its version"
    echo "  pi-update            Update the pi agent CLI to the latest version"
    echo "  pi-uninstall         Remove the pi agent CLI (keeps ~/.pi config)"
    echo ""
    echo "Run without arguments for an interactive menu."
}

menu() {
    local actions=(
        "install hf CLI" "reinstall hf CLI (force)" "install hf CLI with transformers"
        "check hf CLI" "uninstall hf CLI"
        "install pi agent CLI" "check pi agent CLI" "update pi agent CLI" "uninstall pi agent CLI"
        "quit"
    )
    while true; do
        echo ""
        echo "Install & manage CLIs — choose an action:"
        echo ""
        select action in "${actions[@]}"; do
            case "${action}" in
                "install hf CLI")                   cmd_hf_install ;;
                "reinstall hf CLI (force)")         cmd_hf_reinstall ;;
                "install hf CLI with transformers") cmd_hf_with_transformers ;;
                "check hf CLI")                     cmd_hf_check ;;
                "uninstall hf CLI")                 cmd_hf_uninstall ;;
                "install pi agent CLI")             cmd_pi_install ;;
                "check pi agent CLI")               cmd_pi_check ;;
                "update pi agent CLI")               cmd_pi_update ;;
                "uninstall pi agent CLI")            cmd_pi_uninstall ;;
                "quit")                              return ;;
                *)                                   echo "Invalid selection." ;;
            esac
            break
        done
    done
}

case "${1:-}" in
    hf-install)           cmd_hf_install ;;
    hf-reinstall)         cmd_hf_reinstall ;;
    hf-with-transformers) cmd_hf_with_transformers ;;
    hf-check)             cmd_hf_check ;;
    hf-uninstall)         cmd_hf_uninstall ;;
    pi-install)           cmd_pi_install ;;
    pi-check)             cmd_pi_check ;;
    pi-update)            cmd_pi_update ;;
    pi-uninstall)         cmd_pi_uninstall ;;
    help|--help|-h)       usage ;;
    "")                   menu ;;
    *)                    echo "Unknown command: $1" >&2; usage >&2; exit 1 ;;
esac
