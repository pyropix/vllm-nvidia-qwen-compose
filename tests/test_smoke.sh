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

test_status_maps_running_variant_service_via_registry() {
  echo "${SVC_A_FAST}" >"${STUB_DOCKER_PS}"
  run_script status
  assert_status 0
  assert_out_contains "${SVC_A_FAST}"
  assert_out_contains "no (differs from selection)"
}

test_status_unknown_running_service() {
  echo "vllm-unlisted" >"${STUB_DOCKER_PS}"
  run_script status
  assert_status 0
  assert_out_contains "vllm-unlisted (not in models.json)"
}

test_start_fails_when_registry_service_missing_from_compose() {
  sed -i "/^  ${SVC_A}:/,+1d" "${SANDBOX}/docker-compose.yml"
  fake_download nvidia/Qwen-A
  fake_download z-lab/Draft-A
  run_script start
  assert_status 1
  assert_out_contains "no docker-compose service '${SVC_A}'"
  assert_log_lacks "docker compose"
}

test_start_fails_when_registry_has_no_service() {
  fake_download nvidia/Qwen-A
  fake_download z-lab/Draft-A
  jq 'map(del(.service))' "${SANDBOX}/models.json" >"${SANDBOX}/m.json"
  mv "${SANDBOX}/m.json" "${SANDBOX}/models.json"
  run_script start
  assert_status 1
  assert_out_contains "has no service for MODEL_ID 'nvidia/Qwen-A'"
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
  run_script --stdin "3" select
  assert_status 0
  grep -q '^MODEL_ID=unsloth/Qwen-B$' "${SANDBOX}/.env.vllm" || fail "MODEL_ID not written"
  grep -q '^MODEL_VARIANT=$' "${SANDBOX}/.env.vllm" || fail "MODEL_VARIANT not cleared"
  grep -q '^DRAFT_MODEL_ID=$' "${SANDBOX}/.env.vllm" || fail "DRAFT_MODEL_ID not cleared"
}

test_select_writes_context_window() {
  run_script --stdin "3" select
  assert_status 0
  local expected
  expected="$(jq -r '.[] | select(.id == "unsloth/Qwen-B") | .context' "${SANDBOX}/models.json")"
  grep -qx "MAX_MODEL_LEN=${expected}" "${SANDBOX}/.env.vllm" || fail "MAX_MODEL_LEN not written"
}

test_start_refuses_stale_context_window() {
  sed -i '/^MAX_MODEL_LEN=/d' "${SANDBOX}/.env.vllm"
  fake_download nvidia/Qwen-A
  fake_download z-lab/Draft-A
  run_script start
  assert_status 1
  assert_out_contains "MAX_MODEL_LEN"
  assert_out_contains "select again"
  assert_log_lacks "docker compose"
}

test_start_refuses_registry_without_context_window() {
  jq 'map(del(.context))' "${SANDBOX}/models.json" >"${SANDBOX}/m.json"
  mv "${SANDBOX}/m.json" "${SANDBOX}/models.json"
  run_script start
  assert_status 1
  assert_out_contains "no context window for nvidia/Qwen-A"
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
  run_script logs
  assert_status 0
  assert_out_contains "engine started"
  assert_out_contains "listening on :8000"
}

# Every compose call gets the checkout and env file, then its own arguments.
compose_prefix() {
  echo "docker compose --project-directory ${SANDBOX} --env-file ${SANDBOX}/.env.vllm"
}

test_start_compose_args() {
  fake_download nvidia/Qwen-A
  fake_download z-lab/Draft-A
  run_script start
  assert_status 0
  local p
  p="$(compose_prefix)"
  assert_log_contains "${p} --profile ${SVC_A} ps ${SVC_A} --status running"
  assert_log_contains "${p} --profile * ps --all"
  assert_log_contains "${p} --profile ${SVC_A} pull"
  assert_log_contains "${p} --profile ${SVC_A} up --detach --remove-orphans"
}

test_start_removes_other_variants() {
  fake_download nvidia/Qwen-A
  fake_download z-lab/Draft-A
  echo "${SVC_B}" >"${STUB_DOCKER_PS}"
  run_script start
  assert_status 0
  assert_log_contains "$(compose_prefix) --profile * rm --stop --force ${SVC_B}"
}

test_stop_compose_args() {
  run_script stop
  assert_status 0
  assert_log_contains "$(compose_prefix) --profile ${SVC_A} rm --stop --force ${SVC_A}"
  assert_log_lacks " down "
}

test_logs_compose_args() {
  run_script logs
  assert_status 0
  assert_log_contains "$(compose_prefix) logs ${SVC_A} --follow"
}

test_status_compose_args() {
  run_script status
  assert_status 0
  assert_log_contains "$(compose_prefix) --profile * ps --status running --format {{.Service}}"
}

test_ready_when_vllm_answers() {
  echo '{"data":[{"id":"nvidia/Qwen-A"}]}' >"${STUB_CURL_OUT}"
  run_script ready
  assert_status 0
  assert_out_contains "vLLM is ready"
}

test_ready_fails_when_not_ready() {
  export STUB_CURL_FAIL=1
  run_script ready
  assert_status 1
  assert_out_contains "vLLM is not ready"
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

test_compose_requires_context_window() {
  local total required
  total="$(grep -c -- '--max-model-len' "${REPO_DIR}/docker-compose.yml")"
  # shellcheck disable=SC2016 # literal compose syntax, not a shell expansion
  required="$(grep -c -- '--max-model-len "${MAX_MODEL_LEN:?.*select' "${REPO_DIR}/docker-compose.yml")"
  [[ "${total}" -gt 0 && "${total}" == "${required}" ]] || fail "not every --max-model-len requires MAX_MODEL_LEN with a select hint (${required}/${total})"
}

test_stop_works_with_stale_context_window() {
  sed -i '/^MAX_MODEL_LEN=/d' "${SANDBOX}/.env.vllm"
  run_script stop
  assert_status 0
  assert_log_contains "docker-env MAX_MODEL_LEN=0"
}

run_tests
