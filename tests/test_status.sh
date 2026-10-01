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

# status lists every Model ID's Download from the same completeness check as
# download/start: weights present but Draft model missing is incomplete, and a
# Draft model shared by two Model IDs completes both.
test_status_lists_mixed_downloads_of_every_model_id() {
    fake_download nvidia/Qwen-A
    fake_download unsloth/Qwen-B
    run_script status
    assert_status 0
    assert_out_contains "nvidia/Qwen-A  incomplete (missing: z-lab/Draft-A)"
    assert_out_contains "unsloth/Qwen-B  complete"
    assert_out_contains "unsloth/Qwen-C  incomplete (missing: unsloth/Qwen-C z-lab/Draft-A)"
}

test_status_shared_draft_completes_every_model_id_using_it() {
    fake_download nvidia/Qwen-A
    fake_download unsloth/Qwen-C
    fake_download z-lab/Draft-A
    run_script status
    assert_out_contains "nvidia/Qwen-A  complete"
    assert_out_contains "unsloth/Qwen-B  incomplete (missing: unsloth/Qwen-B)"
    assert_out_contains "unsloth/Qwen-C  complete"
}

# An interrupted download of one Model ID does not mark the others incomplete.
test_status_interrupted_download_only_affects_its_model_id() {
    fake_download nvidia/Qwen-A
    fake_download z-lab/Draft-A
    fake_download unsloth/Qwen-B
    touch "$(fake_repo_dir unsloth/Qwen-B)/blobs/w.incomplete"
    run_script status
    assert_out_contains "nvidia/Qwen-A  complete"
    assert_out_contains "unsloth/Qwen-B  incomplete (missing: unsloth/Qwen-B)"
}

run_tests
