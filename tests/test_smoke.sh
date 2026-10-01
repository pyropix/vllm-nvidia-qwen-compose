#!/usr/bin/env bash
# One smoke test per vllm-serve command, run against stubs (see lib.sh).
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

test_help() {
    run_script --help
    assert_status 0
    assert_out_contains "Usage: vllm-serve.sh"
}

test_unknown_command() {
    run_script bogus
    assert_status 1
    assert_out_contains "Unknown command: bogus"
}

test_menu_quits_on_q() {
    run_script --stdin "q"
    assert_status 0
    assert_out_contains "vLLM management"
}

test_status_no_container() {
    run_script status
    assert_status 0
    assert_out_contains "nvidia/Qwen-A"
    assert_out_contains "none running"
}

test_status_running_and_ready() {
    echo "${SVC_A}" >"${STUB_DOCKER_PS}"
    echo '{"data":[{"id":"nvidia/Qwen-A"}]}' >"${STUB_CURL_OUT}"
    run_script status
    assert_status 0
    assert_out_contains "${SVC_A}"
    assert_out_contains "yes (nvidia/Qwen-A)"
}

test_select_writes_env() {
    run_script --stdin "2" select
    assert_status 0
    grep -q '^MODEL_ID=nvidia/Qwen-A$' "${SANDBOX}/.env.vllm" || fail "MODEL_ID not written"
    grep -q '^MODEL_VARIANT=fast$' "${SANDBOX}/.env.vllm" || fail "MODEL_VARIANT not written"
    grep -q '^DRAFT_MODEL_ID=z-lab/Draft-A$' "${SANDBOX}/.env.vllm" || fail "DRAFT_MODEL_ID not written"
}

test_select_without_variant_clears_variant_and_draft() {
    # Start from a variant with a Draft model so clearing is observable.
    sed -i -e 's|^MODEL_VARIANT=.*|MODEL_VARIANT=fast|' "${SANDBOX}/.env.vllm"
    serve_stdin "3" select
    assert_status 0
    grep -q '^MODEL_ID=unsloth/Qwen-B$' "${SANDBOX}/.env.vllm" || fail "MODEL_ID not written"
    grep -q '^MODEL_VARIANT=$' "${SANDBOX}/.env.vllm" || fail "MODEL_VARIANT not cleared"
    grep -q '^DRAFT_MODEL_ID=$' "${SANDBOX}/.env.vllm" || fail "DRAFT_MODEL_ID not cleared"
}

test_download_fetches_model_and_draft() {
    run_script download
    assert_status 0
    assert_log_contains "hf auth login"
    assert_log_contains "hf download nvidia/Qwen-A"
    assert_log_contains "hf download z-lab/Draft-A"
    assert_log_contains "hf auth logout"
}

test_start_refuses_incomplete_download() {
    run_script start
    assert_status 1
    assert_out_contains "is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_refuses_missing_draft_model() {
    fake_download nvidia/Qwen-A
    run_script start
    assert_status 1
    assert_out_contains "z-lab/Draft-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_brings_up_service() {
    fake_download nvidia/Qwen-A
    fake_download z-lab/Draft-A
    run_script start
    assert_status 0
    assert_log_contains "--profile ${SVC_A} pull"
    assert_log_contains "--profile ${SVC_A} up --detach"
}

test_logs_follows_service() {
    run_script logs
    assert_status 0
    assert_log_contains "logs ${SVC_A} --follow"
}

test_logs_passes_container_output_through() {
    printf 'engine started\nlistening on :8000\n' >"${STUB_DOCKER_LOGS}"
    serve logs
    assert_status 0
    assert_out_contains "engine started"
    assert_out_contains "listening on :8000"
}

test_ready_when_vllm_answers() {
    echo '{"data":[{"id":"nvidia/Qwen-A"}]}' >"${STUB_CURL_OUT}"
    run_script ready
    assert_status 0
    assert_out_contains "vLLM is ready"
}

test_ready_fails_when_unreachable() {
    export STUB_CURL_FAIL=1
    run_script ready
    assert_status 1
    assert_out_contains "vLLM is not ready"
}

test_stop_takes_service_down() {
    run_script stop
    assert_status 0
    assert_log_contains "--profile ${SVC_A} down --remove-orphans"
}

test_pi_launches_with_model() {
    run_script pi
    assert_status 0
    assert_log_contains "pi --provider vllm-qwen --model nvidia/Qwen-A"
}

test_link_and_unlink() {
    run_script link
    assert_status 0
    [[ -L "${HOME}/.local/bin/vllm-serve" ]] || fail "symlink not created"
    run_script unlink
    assert_status 0
    [[ ! -e "${HOME}/.local/bin/vllm-serve" ]] || fail "symlink not removed"
}

run_tests
