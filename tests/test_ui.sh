#!/usr/bin/env bash
# UI: the select and main menus, driven through stdin.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Menu input must end in 'q': the menu re-prompts forever on end of input.

assert_env() {
    grep -qx "$1" "${SANDBOX}/.env.vllm" || fail ".env.vllm lacks '$1'. Env: $(cat "${SANDBOX}/.env.vllm")"
}

# Context window the sandbox registry gives Model ID $1.
fixture_context() {
    jq -r --arg id "$1" '.[] | select(.id == $id) | .context' "${SANDBOX}/models.json"
}

# Sandbox registry entries, in menu order: Qwen-A, Qwen-A:fast, Qwen-B, Qwen-C.
test_select_model_without_variant() {
    select_model nvidia/Qwen-A
    run_script --stdin $'3\n' select
    assert_status 0
    assert_env "MODEL_ID=unsloth/Qwen-B"
    assert_env "MODEL_VARIANT="
    assert_env "DRAFT_MODEL_ID="
    assert_env "MAX_MODEL_LEN=$(fixture_context unsloth/Qwen-B)"
}

test_select_model_with_variant() {
    select_model unsloth/Qwen-B
    run_script --stdin $'2\n' select
    assert_status 0
    assert_env "MODEL_ID=nvidia/Qwen-A"
    assert_env "MODEL_VARIANT=fast"
    assert_env "DRAFT_MODEL_ID=z-lab/Draft-A"
    assert_env "MAX_MODEL_LEN=$(fixture_context nvidia/Qwen-A)"
}

test_select_invalid_choice_reprompts() {
    run_script --stdin $'9\nx\n4\n' select
    assert_status 0
    assert_out_contains "Invalid selection. Enter a number between 1 and 4."
    [[ "$(grep -c 'Invalid selection' <<<"${OUT}")" == 2 ]] || fail "expected 2 invalid prompts. Output: ${OUT}"
    assert_env "MODEL_ID=unsloth/Qwen-C"
}

test_menu_quits_with_q() {
    run_script --stdin $'q\n'
    assert_status 0
    assert_out_contains "(type 'q' to quit)"
    assert_log_lacks "rm --stop"
}

test_menu_invalid_choice() {
    run_script --stdin $'99\nq\n'
    assert_status 0
    assert_out_contains "Invalid selection."
}

test_menu_stop_routes_to_cmd_stop() {
    run_script --stdin $'7\nq\n'
    assert_status 0
    assert_log_contains "--profile ${SVC_A} rm --stop --force ${SVC_A}"
    assert_log_lacks "down --remove-orphans"
}

test_menu_select_routes_to_cmd_select() {
    run_script --stdin $'2\n3\nq\n'
    assert_status 0
    assert_out_contains "Select the model to download and serve:"
    assert_env "MODEL_ID=unsloth/Qwen-B"
}

run_tests
