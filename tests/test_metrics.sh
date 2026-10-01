#!/usr/bin/env bash
# Metrics history: Run labels on the scrape target, stop keeping monitoring up,
# and the explicit reset. Run against stubs (see lib.sh).
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

targets_file() { echo "${SANDBOX}/monitoring/targets/vllm.json"; }

ready_to_start() {
    fake_download nvidia/Qwen-A
    fake_download z-lab/Draft-A
}

test_start_labels_scrape_target_with_run() {
    ready_to_start
    run_script start
    assert_status 0
    local file
    file="$(targets_file)"
    [[ -f "${file}" ]] || { fail "targets file not written"; return; }
    [[ "$(jq -r '.[0].targets[0]' "${file}")" == "localhost:8000" ]] || fail "wrong target"
    [[ "$(jq -r '.[0].labels.model_id' "${file}")" == "nvidia/Qwen-A" ]] || fail "model_id label"
    [[ "$(jq -r '.[0].labels.variant' "${file}")" == "" ]] || fail "variant label should be empty"
    [[ "$(jq -r '.[0].labels.run_start' "${file}")" =~ ^[0-9]{8}-[0-9]{4}$ ]] || fail "run_start label"
    [[ "$(jq -r '.[0].labels.run' "${file}")" =~ ^[0-9]{8}-[0-9]{4}\ nvidia/Qwen-A$ ]] || fail "run label: $(jq -r '.[0].labels.run' "${file}")"
}

test_start_labels_variant() {
    ready_to_start
    sed -i 's|^MODEL_VARIANT=.*|MODEL_VARIANT=fast|' "${SANDBOX}/.env.vllm"
    run_script start
    assert_status 0
    [[ "$(jq -r '.[0].labels.variant' "$(targets_file)")" == "fast" ]] || fail "variant label"
    [[ "$(jq -r '.[0].labels.run' "$(targets_file)")" == *" nvidia/Qwen-A:fast" ]] || fail "run label lacks variant"
}

test_start_refused_leaves_no_target() {
    run_script start
    assert_status 1
    [[ ! -e "$(targets_file)" ]] || fail "targets file written despite refused start"
}

test_stop_clears_target_but_keeps_monitoring() {
    ready_to_start
    run_script start
    run_script stop
    assert_status 0
    [[ ! -e "$(targets_file)" ]] || fail "targets file not removed"
    assert_log_lacks " down "
}

test_stop_all_takes_monitoring_down_without_deleting_volumes() {
    run_script stop --all
    assert_status 0
    assert_log_contains "--profile ${SVC_A} down --remove-orphans"
    assert_log_lacks "--volumes"
}

test_reset_refused_while_vllm_runs() {
    echo "${SVC_A}" >"${STUB_DOCKER_PS}"
    run_script reset-metrics --yes
    assert_status 1
    assert_out_contains "vLLM is running"
    assert_log_lacks "--volumes"
}

test_reset_aborts_without_confirmation() {
    run_script --stdin "n" reset-metrics
    assert_status 1
    assert_out_contains "Aborted"
    assert_log_lacks "--volumes"
}

test_reset_with_confirmation_deletes_volumes() {
    run_script --stdin "y" reset-metrics
    assert_status 0
    assert_log_contains "down --volumes --remove-orphans"
}

test_reset_yes_skips_prompt() {
    run_script reset-metrics --yes
    assert_status 0
    assert_log_contains "down --volumes --remove-orphans"
}

run_tests
