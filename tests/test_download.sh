#!/usr/bin/env bash
# Download completeness (weights plus Draft model) as seen by status, download and start.
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake_complete_download() {
    fake_download nvidia/Qwen-A
    fake_download z-lab/Draft-A
}

test_status_download_complete() {
    fake_complete_download
    run_script status
    assert_status 0
    assert_out_contains "Download   complete"
}

test_status_download_nothing_fetched() {
    run_script status
    assert_status 0
    assert_out_contains "incomplete (missing: nvidia/Qwen-A z-lab/Draft-A)"
}

test_status_download_missing_draft_model() {
    fake_download nvidia/Qwen-A
    run_script status
    assert_status 0
    assert_out_contains "incomplete (missing: z-lab/Draft-A)"
}

test_status_download_incomplete_blob() {
    fake_complete_download
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/w.incomplete"
    run_script status
    assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_ignores_stale_incomplete_blob() {
    fake_complete_download
    touch -d '2 days ago' "$(fake_repo_dir nvidia/Qwen-A)/blobs/stale.incomplete"
    run_script status
    assert_out_contains "Download   complete"
}

# A partial download of a file with no snapshot symlink yet (e.g. config.json).
test_status_download_unlinked_incomplete_blob() {
    fake_complete_download
    touch -d '1 hour ago' "$(fake_repo_dir nvidia/Qwen-A)/refs/main"
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/cfg.incomplete"
    run_script status
    assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_start_refuses_unlinked_incomplete_blob() {
    fake_complete_download
    touch -d '1 hour ago' "$(fake_repo_dir nvidia/Qwen-A)/refs/main"
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/cfg.incomplete"
    run_script start
    assert_status 1
    assert_out_contains "nvidia/Qwen-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_ignores_stale_unlinked_incomplete_blob() {
    fake_complete_download
    touch -d '1 hour ago' "$(fake_repo_dir nvidia/Qwen-A)/refs/main"
    touch -d '2 days ago' "$(fake_repo_dir nvidia/Qwen-A)/blobs/stale.incomplete"
    run_script start
    assert_status 0
    assert_log_contains "up --detach"
}

test_status_download_missing_shard() {
    fake_complete_download
    local snapshot
    snapshot="$(fake_repo_dir nvidia/Qwen-A)/snapshots/rev1"
    echo '{"weight_map":{"a":"model.safetensors","b":"model-2.safetensors"}}' \
        >"${snapshot}/model.safetensors.index.json"
    run_script status
    assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_dangling_symlink() {
    fake_complete_download
    rm "$(fake_repo_dir z-lab/Draft-A)/blobs/w"
    run_script status
    assert_out_contains "incomplete (missing: z-lab/Draft-A)"
}

test_status_download_without_draft_model() {
    select_model unsloth/Qwen-B
    fake_download unsloth/Qwen-B
    run_script status
    assert_out_contains "Download   complete"
}

test_shared_draft_model_serves_both_model_ids() {
    fake_complete_download
    fake_download unsloth/Qwen-C
    select_model unsloth/Qwen-C
    run_script status
    assert_out_contains "Download   complete"
}

test_status_draft_comes_from_registry_not_stale_env() {
    fake_complete_download
    select_model nvidia/Qwen-A z-lab/Stale-Draft
    run_script status
    assert_status 0
    assert_out_contains "Draft      z-lab/Draft-A"
    assert_out_contains "Download   complete"
    [[ "${OUT}" != *"Stale-Draft"* ]] || fail "status shows the stale Draft model. Output: ${OUT}"
}

test_status_draft_placeholder_without_draft_model() {
    select_model unsloth/Qwen-B z-lab/Stale-Draft
    run_script status
    assert_out_contains "Draft      -"
}

test_status_placeholders_without_selected_model() {
    sed -i -e 's|^MODEL_ID=.*|MODEL_ID=|' "${SANDBOX}/.env.vllm"
    run_script status
    assert_status 0
    assert_out_contains "Draft      -"
    assert_out_contains "Download   -"
}

test_download_skips_draft_model_already_fetched() {
    fake_download z-lab/Draft-A
    select_model unsloth/Qwen-C
    run_script download
    assert_status 0
    assert_log_contains "hf download unsloth/Qwen-C"
    assert_log_lacks "hf download z-lab/Draft-A"
}

test_download_skips_complete_download() {
    fake_complete_download
    run_script download
    assert_status 0
    assert_out_contains "already downloaded"
    assert_log_lacks "hf download"
}

test_download_logs_out_after_success() {
    run_script download
    assert_status 0
    assert_log_contains "hf auth logout"
}

test_failed_download_logs_out() {
    STUB_HF_FAIL="download z-lab/Draft-A"
    run_script download
    assert_status 1
    assert_log_contains "hf download z-lab/Draft-A"
    assert_log_contains "hf auth logout"
}

test_failed_download_does_not_log_out_when_login_failed() {
    STUB_HF_FAIL="auth login"
    run_script download
    assert_status 1
    assert_log_lacks "hf download"
}

test_start_refuses_incomplete_blob() {
    fake_complete_download
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/w.incomplete"
    run_script start
    assert_status 1
    assert_out_contains "nvidia/Qwen-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_refuses_missing_shard() {
    fake_complete_download
    local snapshot
    snapshot="$(fake_repo_dir nvidia/Qwen-A)/snapshots/rev1"
    echo '{"weight_map":{"a":"model.safetensors","b":"model-2.safetensors"}}' \
        >"${snapshot}/model.safetensors.index.json"
    run_script start
    assert_status 1
    assert_out_contains "nvidia/Qwen-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_refuses_dangling_symlink() {
    fake_complete_download
    rm "$(fake_repo_dir nvidia/Qwen-A)/blobs/w"
    run_script start
    assert_status 1
    assert_out_contains "nvidia/Qwen-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_download_fetches_repo_again_when_cache_broken() {
    fake_complete_download
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/w.incomplete"
    run_script download
    assert_status 0
    assert_log_contains "hf download nvidia/Qwen-A"
    assert_log_lacks "hf download z-lab/Draft-A"
}

test_download_fetches_repo_again_when_symlink_dangling() {
    fake_complete_download
    rm "$(fake_repo_dir z-lab/Draft-A)/blobs/w"
    run_script download
    assert_status 0
    assert_log_contains "hf download z-lab/Draft-A"
    assert_log_lacks "hf download nvidia/Qwen-A"
}

test_shared_draft_model_complete_and_startable_for_both() {
    fake_complete_download
    fake_download unsloth/Qwen-C
    run_script status
    assert_out_contains "Download   complete"
    run_script start
    assert_status 0
    assert_log_contains "up --detach"
    : >"${STUB_LOG}"
    select_model unsloth/Qwen-C
    run_script status
    assert_out_contains "Download   complete"
    run_script start
    assert_status 0
    assert_log_contains "up --detach"
}

test_shared_draft_model_broken_blocks_both() {
    fake_complete_download
    fake_download unsloth/Qwen-C
    rm "$(fake_repo_dir z-lab/Draft-A)/blobs/w"
    run_script start
    assert_status 1
    assert_out_contains "z-lab/Draft-A is not fully downloaded"
    select_model unsloth/Qwen-C
    run_script start
    assert_status 1
    assert_out_contains "z-lab/Draft-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

# Put a repo into the fake cache whose only weights file has the given name.
fake_download_as() {
    local snapshot
    fake_download "$1"
    snapshot="$(fake_repo_dir "$1")/snapshots/rev1"
    rm "${snapshot}/model.safetensors"
    ln -s ../../blobs/w "${snapshot}/$2"
}

test_status_download_bin_weights_complete() {
    fake_download nvidia/Qwen-A
    fake_download_as z-lab/Draft-A weights.bin
    run_script status
    assert_out_contains "Download   complete"
}

test_status_download_gguf_weights_complete() {
    fake_download nvidia/Qwen-A
    fake_download_as z-lab/Draft-A weights.gguf
    run_script status
    assert_out_contains "Download   complete"
}

test_status_download_without_weight_files_incomplete() {
    fake_complete_download
    local snapshot
    snapshot="$(fake_repo_dir z-lab/Draft-A)/snapshots/rev1"
    rm "${snapshot}/model.safetensors"
    echo '{}' >"${snapshot}/config.json"
    run_script status
    assert_out_contains "incomplete (missing: z-lab/Draft-A)"
}

test_status_download_missing_shard_in_bin_index() {
    fake_complete_download
    echo '{"weight_map":{"a":"model.safetensors","b":"pytorch_model-2.bin"}}' \
        >"$(fake_repo_dir nvidia/Qwen-A)/snapshots/rev1/pytorch_model.bin.index.json"
    run_script status
    assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_all_shards_present_in_bin_index() {
    fake_complete_download
    local snapshot
    snapshot="$(fake_repo_dir nvidia/Qwen-A)/snapshots/rev1"
    ln -s ../../blobs/w "${snapshot}/pytorch_model-1.bin"
    echo '{"weight_map":{"a":"pytorch_model-1.bin"}}' >"${snapshot}/pytorch_model.bin.index.json"
    run_script status
    assert_out_contains "Download   complete"
}

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
