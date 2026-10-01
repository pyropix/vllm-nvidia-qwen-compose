#!/usr/bin/env bash
# One smoke test per vllm-serve command, run against stubs (see lib.sh).
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

test_help() {
    serve --help
    assert_status 0
    assert_out_contains "Usage: vllm-serve.sh"
}

test_unknown_command() {
    serve bogus
    assert_status 1
    assert_out_contains "Unknown command: bogus"
}

test_menu_quits_on_q() {
    serve_stdin "q"
    assert_status 0
    assert_out_contains "vLLM management"
}

test_status_no_container() {
    serve status
    assert_status 0
    assert_out_contains "nvidia/Qwen-A"
    assert_out_contains "none running"
}

test_status_running_and_ready() {
    echo "vllm-nv-qwen-A" >"${STUB_DOCKER_PS}"
    echo '{"data":[{"id":"nvidia/Qwen-A"}]}' >"${STUB_CURL_OUT}"
    serve status
    assert_status 0
    assert_out_contains "vllm-nv-qwen-A"
    assert_out_contains "yes (nvidia/Qwen-A)"
}

test_select_writes_env() {
    serve_stdin "2" select
    assert_status 0
    grep -q '^MODEL_ID=nvidia/Qwen-A$' "${SANDBOX}/.env.vllm" || fail "MODEL_ID not written"
    grep -q '^MODEL_VARIANT=fast$' "${SANDBOX}/.env.vllm" || fail "MODEL_VARIANT not written"
    grep -q '^DRAFT_MODEL_ID=z-lab/Draft-A$' "${SANDBOX}/.env.vllm" || fail "DRAFT_MODEL_ID not written"
}

test_download_fetches_model_and_draft() {
    serve download
    assert_status 0
    assert_log_contains "hf auth login"
    assert_log_contains "hf download nvidia/Qwen-A"
    assert_log_contains "hf download z-lab/Draft-A"
    assert_log_contains "hf auth logout"
}

test_start_refuses_incomplete_download() {
    serve start
    assert_status 1
    assert_out_contains "is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_refuses_missing_draft_model() {
    fake_download nvidia/Qwen-A
    serve start
    assert_status 1
    assert_out_contains "z-lab/Draft-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_brings_up_service() {
    fake_download nvidia/Qwen-A
    fake_download z-lab/Draft-A
    serve start
    assert_status 0
    assert_log_contains "--profile vllm-nv-qwen-A pull"
    assert_log_contains "--profile vllm-nv-qwen-A up --detach"
}

test_logs_follows_service() {
    serve logs
    assert_status 0
    assert_log_contains "logs vllm-nv-qwen-A --follow"
}

test_ready_when_vllm_answers() {
    echo '{"data":[{"id":"nvidia/Qwen-A"}]}' >"${STUB_CURL_OUT}"
    serve ready
    assert_status 0
    assert_out_contains "vLLM is ready"
}

test_ready_fails_when_unreachable() {
    export STUB_CURL_FAIL=1
    serve ready
    assert_status 1
    assert_out_contains "vLLM is not ready"
}

test_stop_removes_only_the_vllm_service() {
    serve stop
    assert_status 0
    assert_log_contains "--profile vllm-nv-qwen-A rm --stop --force vllm-nv-qwen-A"
    assert_log_lacks " down "
}

test_pi_launches_with_model() {
    serve pi
    assert_status 0
    assert_log_contains "pi --provider vllm-qwen --model nvidia/Qwen-A"
}

test_link_and_unlink() {
    serve link
    assert_status 0
    [[ -L "${HOME}/.local/bin/vllm-serve" ]] || fail "symlink not created"
    serve unlink
    assert_status 0
    [[ ! -e "${HOME}/.local/bin/vllm-serve" ]] || fail "symlink not removed"
}

run_tests
