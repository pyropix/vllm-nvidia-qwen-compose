#!/usr/bin/env bash
# Readiness and status module: the /v1/models ready check and the vLLM URL.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Source the module from the sandbox copy.
use_status() {
    # shellcheck source=lib/status.sh
    source "${SANDBOX}/lib/status.sh"
}

# ADR 0003: every copy of the vLLM address matches VLLM_ADDR. Lists all that don't.
test_vllm_addr_copies_match() {
    # shellcheck source=lib/status.sh
    source "${REPO_DIR}/lib/status.sh"
    local url="http://${VLLM_ADDR}/v1" port="${VLLM_ADDR##*:}" compose="${REPO_DIR}/docker-compose.yml"
    local bad=() hits ports p
    hits="$(grep -rlF "${VLLM_ADDR}" "${REPO_DIR}/vllm-serve.sh" "${REPO_DIR}/lib")"
    [[ "${hits}" == "${REPO_DIR}/lib/status.sh" ]] || bad+=("shell literal in: ${hits}")
    grep -qxF "const BASE_URL = \"${url}\";" "${REPO_DIR}/.pi/extensions/pi-vllm-qwen/index.ts" ||
        bad+=("index.ts BASE_URL")
    [[ "$(jq -r '.providers["vllm-qwen"].baseUrl' "${REPO_DIR}/settings/.pi/agent/models.json")" == "${url}" ]] ||
        bad+=("settings/.pi/agent/models.json baseUrl")
    ports="$(grep -oE -- '--port [0-9]+' "${compose}" | cut -d' ' -f2)"
    [[ -n "${ports}" ]] || bad+=("docker-compose.yml has no --port")
    for p in ${ports}; do
        [[ "${p}" == "${port}" ]] || bad+=("docker-compose.yml --port ${p}")
    done
    ((${#bad[@]} == 0)) || fail "disagree with VLLM_ADDR=${VLLM_ADDR}: ${bad[*]}"
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
