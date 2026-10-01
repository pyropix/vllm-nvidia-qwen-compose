#!/usr/bin/env bash
# Readiness and status module: the /v1/models ready check and the vLLM URL.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Source the module from the sandbox copy.
use_status() {
    # shellcheck source=lib/status.sh
    source "${SANDBOX}/lib/status.sh"
}

test_url_is_defined_once() {
    local hits
    hits="$(grep -rlE 'localhost:8000' "${REPO_DIR}/vllm-serve.sh" "${REPO_DIR}/lib")"
    [[ "${hits}" == "${REPO_DIR}/lib/status.sh" ]] || fail "URL defined in: ${hits}"
}

test_query_models_asks_the_models_url() {
    use_status
    echo '{"data":[]}' >"${STUB_CURL_OUT}"
    query_models >/dev/null
    assert_log_contains "${VLLM_MODELS_URL}"
}

test_ready_summary_lists_models_when_ready() {
    use_status
    echo '{"data":[{"id":"nvidia/Qwen-A"},{"id":"other"}]}' >"${STUB_CURL_OUT}"
    [[ "$(ready_summary)" == "yes (nvidia/Qwen-A, other)" ]] || fail "summary: $(ready_summary)"
}

# curl exits 22 when vLLM answers with an HTTP error (not ready yet).
test_ready_summary_when_not_ready() {
    use_status
    STUB_CURL_FAIL=1 STUB_CURL_EXIT=22
    export STUB_CURL_FAIL STUB_CURL_EXIT
    [[ "$(ready_summary)" == "no (still starting?)" ]] || fail "summary: $(ready_summary)"
}

# curl exits 7 when nothing listens on the port.
test_ready_summary_when_unreachable() {
    use_status
    STUB_CURL_FAIL=1 STUB_CURL_EXIT=7
    export STUB_CURL_FAIL STUB_CURL_EXIT
    [[ "$(ready_summary)" == "no (still starting?)" ]] || fail "summary: $(ready_summary)"
}

test_cmd_ready_lists_models_when_ready() {
    use_status
    echo '{"data":[{"id":"nvidia/Qwen-A"},{"id":"other"}]}' >"${STUB_CURL_OUT}"
    local out status=0
    out="$(cmd_ready 2>&1)" || status=$?
    [[ "${status}" == 0 ]] || fail "exit ${status}"
    [[ "${out}" == $'vLLM is ready. Models:\n  nvidia/Qwen-A\n  other' ]] || fail "output: ${out}"
}

# Without --wait, a failed check returns 1; $1 is the curl exit code.
assert_cmd_ready_fails_with_curl_exit() {
    use_status
    STUB_CURL_FAIL=1 STUB_CURL_EXIT="$1"
    export STUB_CURL_FAIL STUB_CURL_EXIT
    local out status=0
    out="$(cmd_ready 2>&1)" || status=$?
    [[ "${status}" == 1 ]] || fail "exit ${status}"
    [[ "${out}" == "vLLM is not ready (no answer from ${VLLM_MODELS_URL})." ]] || fail "output: ${out}"
}

# curl exits 22 when vLLM answers with an HTTP error (not ready yet).
test_cmd_ready_when_not_ready() { assert_cmd_ready_fails_with_curl_exit 22; }

# curl exits 7 when nothing listens on the port.
test_cmd_ready_when_unreachable() { assert_cmd_ready_fails_with_curl_exit 7; }

# --wait polls until vLLM answers. sleep is replaced: it logs and, on the
# second call, lets the stub curl succeed, so the third poll answers.
test_cmd_ready_wait_polls_until_ready() {
    use_status
    echo '{"data":[{"id":"nvidia/Qwen-A"}]}' >"${STUB_CURL_OUT}"
    STUB_CURL_FAIL=1 STUB_CURL_EXIT=7
    export STUB_CURL_FAIL STUB_CURL_EXIT
    local sleeps="${SANDBOX}/sleeps"
    : >"${sleeps}"
    # shellcheck disable=SC2317  # invoked by cmd_ready
    sleep() {
        echo "sleep $*" >>"${sleeps}"
        (( $(wc -l <"${sleeps}") < 2 )) || STUB_CURL_FAIL=""
    }
    local out status=0
    out="$(cmd_ready --wait 2>&1)" || status=$?
    [[ "${status}" == 0 ]] || fail "exit ${status}"
    [[ "$(grep -c '^curl ' "${STUB_LOG}")" == 3 ]] || fail "polls: $(stub_log)"
    [[ "$(cat "${sleeps}")" == $'sleep 5\nsleep 5' ]] || fail "sleeps: $(cat "${sleeps}")"
    [[ "$(grep -c '^Waiting for vLLM' <<<"${out}")" == 2 ]] || fail "output: ${out}"
    [[ "${out}" == *$'vLLM is ready. Models:\n  nvidia/Qwen-A' ]] || fail "output: ${out}"
}

run_tests
