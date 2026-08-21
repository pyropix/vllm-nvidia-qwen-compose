#!/usr/bin/env bash
set -euo pipefail

## Install / manage the Hugging Face CLI and Claude Code CLI

HF_CLI_BIN="${HOME}/.local/bin/hf"
HF_CLI_DIR="${HF_HOME:+${HF_HOME}/cli}"
HF_CLI_DIR="${HF_CLI_DIR:-${HOME}/.hf-cli}"

CLAUDE_BIN="${HOME}/.local/bin/claude"
CLAUDE_VERSIONS_DIR="${HOME}/.local/share/claude"

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

## Claude Code CLI
# Source: https://code.claude.com/docs

cmd_claude_install() {
    curl -fsSL https://claude.ai/install.sh | bash
}

cmd_claude_check() {
    if [[ -x "${CLAUDE_BIN}" ]]; then
        echo "Claude Code CLI found at ${CLAUDE_BIN}"
        "${CLAUDE_BIN}" --version
    else
        echo "Claude Code CLI not installed (expected at ${CLAUDE_BIN})."
        exit 1
    fi
}

cmd_claude_update() {
    "${CLAUDE_BIN}" update
}

cmd_claude_uninstall() {
    rm -f "${CLAUDE_BIN}"
    rm -rf "${CLAUDE_VERSIONS_DIR}"
    echo "Removed ${CLAUDE_BIN} and ${CLAUDE_VERSIONS_DIR}"
    echo "Note: ~/.claude (config, credentials, history) was left in place."
}

usage() {
    echo "Usage: $(basename "$0") [hf-install|hf-reinstall|hf-with-transformers|hf-check|hf-uninstall|claude-install|claude-check|claude-update|claude-uninstall]"
    echo ""
    echo "Hugging Face CLI:"
    echo "  hf-install           Install the hf CLI (reuses existing venv if present)"
    echo "  hf-reinstall         Recreate the hf CLI virtual environment (--force)"
    echo "  hf-with-transformers Install the hf CLI with the transformers extra"
    echo "  hf-check             Show whether the hf CLI is installed and its version"
    echo "  hf-uninstall         Remove the hf CLI and its virtual environment"
    echo ""
    echo "Claude Code CLI:"
    echo "  claude-install       Install the Claude Code CLI"
    echo "  claude-check         Show whether the Claude Code CLI is installed and its version"
    echo "  claude-update        Update the Claude Code CLI to the latest version"
    echo "  claude-uninstall     Remove the Claude Code CLI (keeps ~/.claude config)"
    echo ""
    echo "Run without arguments for an interactive menu."
}

menu() {
    local actions=(
        "install hf CLI" "reinstall hf CLI (force)" "install hf CLI with transformers"
        "check hf CLI" "uninstall hf CLI"
        "install Claude Code CLI" "check Claude Code CLI" "update Claude Code CLI" "uninstall Claude Code CLI"
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
                "install Claude Code CLI")          cmd_claude_install ;;
                "check Claude Code CLI")            cmd_claude_check ;;
                "update Claude Code CLI")            cmd_claude_update ;;
                "uninstall Claude Code CLI")        cmd_claude_uninstall ;;
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
    claude-install)       cmd_claude_install ;;
    claude-check)         cmd_claude_check ;;
    claude-update)        cmd_claude_update ;;
    claude-uninstall)     cmd_claude_uninstall ;;
    help|--help|-h)       usage ;;
    "")                   menu ;;
    *)                    echo "Unknown command: $1" >&2; usage >&2; exit 1 ;;
esac
