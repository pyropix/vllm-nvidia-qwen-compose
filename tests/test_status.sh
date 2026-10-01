#!/usr/bin/env bash
# Readiness and status module: the /v1/models ready check and the vLLM URL.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Source the module from the sandbox copy.
use_status() {
  source_modules "${SANDBOX}"
}

# ADR 0003: every copy of the vLLM address matches VLLM_ADDR. Lists all that don't.
test_vllm_addr_copies_match() {
  local addr url port compose="${REPO_DIR}/docker-compose.yml"
  addr="$(vllm_addr)"
  url="http://${addr}/v1" port="${addr##*:}"
  local bad=() hits ts base ports p
  hits="$(grep -rlF "${addr}" "${REPO_DIR}/vllm-serve.sh" "${REPO_DIR}/lib")"
  [[ "${hits}" == "${REPO_DIR}/lib/status.sh" ]] || bad+=("shell literal in: ${hits}")
  ts="$(sed -nE 's/^const BASE_URL = "(.*)";$/\1/p' "${REPO_DIR}/.pi/extensions/pi-vllm-qwen/index.ts")"
  [[ "${ts}" == "${url}" ]] ||
    bad+=(".pi/extensions/pi-vllm-qwen/index.ts BASE_URL ${ts:-<missing>}")
  base="$(jq -r '.providers["vllm-qwen"].baseUrl' "${REPO_DIR}/settings/.pi/agent/models.json")"
  [[ "${base}" == "${url}" ]] || bad+=("settings/.pi/agent/models.json baseUrl ${base}")
  ports="$(grep -oE -- '--port [0-9]+' "${compose}" | cut -d' ' -f2)"
  [[ -n "${ports}" ]] || bad+=("docker-compose.yml has no --port")
  for p in ${ports}; do
    [[ "${p}" == "${port}" ]] || bad+=("docker-compose.yml --port ${p}")
  done
  ((${#bad[@]} == 0)) || fail "disagree with VLLM_ADDR=${addr}: ${bad[*]}"
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

test_cmd_ready_lists_models_when_ready() {
  use_status
  echo '{"data":[{"id":"nvidia/Qwen-A"},{"id":"other"}]}' >"${STUB_CURL_OUT}"
  local out status=0
  out="$(cmd_ready 2>&1)" || status=$?
  [[ "${status}" == 0 ]] || fail "exit ${status}"
  [[ "${out}" == $'vLLM is ready. Models:\n  nvidia/Qwen-A\n  other' ]] || fail "output: ${out}"
}

# Run cmd_ready with args $@, setting READY_OUT (stdout), READY_ERR (stderr)
# and READY_STATUS (exit code).
capture_ready() {
  local err="${SANDBOX}/ready-stderr"
  READY_STATUS=0
  READY_OUT="$(cmd_ready "$@" 2>"${err}")" || READY_STATUS=$?
  READY_ERR="$(cat "${err}")"
}

# Without --wait, a failed check returns 1; $1 is the curl exit code.
assert_cmd_ready_fails_with_curl_exit() {
  use_status
  STUB_CURL_FAIL=1 STUB_CURL_EXIT="$1"
  export STUB_CURL_FAIL STUB_CURL_EXIT
  capture_ready
  [[ "${READY_STATUS}" == 1 ]] || fail "exit ${READY_STATUS}"
  [[ -z "${READY_OUT}" ]] || fail "stdout: ${READY_OUT}"
  [[ "${READY_ERR}" == "vLLM is not ready (no answer from ${VLLM_MODELS_URL})." ]] ||
    fail "stderr: ${READY_ERR}"
}

# curl exits 22 when vLLM answers with an HTTP error (not ready yet).
test_cmd_ready_when_not_ready() { assert_cmd_ready_fails_with_curl_exit 22; }

# curl exits 7 when nothing listens on the port.
test_cmd_ready_when_unreachable() { assert_cmd_ready_fails_with_curl_exit 7; }

# --wait polls until vLLM answers: curl fails twice, then the third poll answers.
test_cmd_ready_wait_polls_until_ready() {
  use_status
  echo '{"data":[{"id":"nvidia/Qwen-A"}]}' >"${STUB_CURL_OUT}"
  STUB_CURL_FAIL_TIMES=2 STUB_CURL_EXIT=7
  export STUB_CURL_FAIL_TIMES STUB_CURL_EXIT
  capture_ready --wait
  [[ "${READY_STATUS}" == 0 ]] || fail "exit ${READY_STATUS}"
  [[ "$(grep -c '^curl ' "${STUB_LOG}")" == 3 ]] || fail "polls: $(stub_log)"
  [[ "$(grep '^sleep ' "${STUB_LOG}")" == $'sleep 5\nsleep 5' ]] || fail "sleeps: $(stub_log)"
  # Progress goes to stderr; stdout holds only the result.
  [[ "$(grep -c '^Waiting for vLLM' <<<"${READY_ERR}")" == 2 ]] || fail "stderr: ${READY_ERR}"
  [[ "${READY_OUT}" == $'vLLM is ready. Models:\n  nvidia/Qwen-A' ]] || fail "stdout: ${READY_OUT}"
}

# A malformed /v1/models response is an error, not a ready vLLM.
test_cmd_ready_fails_on_malformed_response() {
  use_status
  echo 'not json' >"${STUB_CURL_OUT}"
  local status=0
  cmd_ready >/dev/null 2>&1 || status=$?
  [[ "${status}" != 0 ]] || fail "exit 0 on malformed response"
}

# Status lists the Download state of every Model ID in the registry.
test_status_lists_download_state_of_every_model_id() {
  fake_complete_download
  fake_download unsloth/Qwen-B
  run_script status
  assert_status 0
  assert_out_contains "Downloads"
  assert_out_contains "nvidia/Qwen-A  complete"
  assert_out_contains "unsloth/Qwen-B  complete"
  assert_out_contains "unsloth/Qwen-C  incomplete (missing: unsloth/Qwen-C)"
}

test_status_lists_incomplete_downloads_with_selected_model_complete() {
  fake_complete_download
  run_script status
  assert_out_contains "nvidia/Qwen-A  complete"
  assert_out_contains "unsloth/Qwen-B  incomplete (missing: unsloth/Qwen-B)"
}

test_status_lists_downloads_without_selected_model() {
  sed -i -e 's|^MODEL_ID=.*|MODEL_ID=|' "${SANDBOX}/.env.vllm"
  fake_download unsloth/Qwen-B
  run_script status
  assert_status 0
  assert_out_contains "unsloth/Qwen-B  complete"
  assert_out_contains "nvidia/Qwen-A  incomplete"
}

test_status_lists_each_model_id_once_despite_variants() {
  run_script status
  local count
  count="$(grep -c '^  nvidia/Qwen-A ' <<<"${OUT}")"
  [[ "${count}" == 1 ]] || fail "expected one nvidia/Qwen-A line, got ${count}. Output: ${OUT}"
}

run_tests
