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

run_tests
