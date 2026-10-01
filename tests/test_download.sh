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
    serve status
    assert_status 0
    assert_out_contains "Download   complete"
}

test_status_download_nothing_fetched() {
    serve status
    assert_status 0
    assert_out_contains "incomplete (missing: nvidia/Qwen-A z-lab/Draft-A)"
}

test_status_download_missing_draft_model() {
    fake_download nvidia/Qwen-A
    serve status
    assert_status 0
    assert_out_contains "incomplete (missing: z-lab/Draft-A)"
}

test_status_download_incomplete_blob() {
    fake_complete_download
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/abc.incomplete"
    serve status
    assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_missing_shard() {
    fake_complete_download
    local snapshot
    snapshot="$(fake_repo_dir nvidia/Qwen-A)/snapshots/rev1"
    echo '{"weight_map":{"a":"model.safetensors","b":"model-2.safetensors"}}' \
        >"${snapshot}/model.safetensors.index.json"
    serve status
    assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_dangling_symlink() {
    fake_complete_download
    rm "$(fake_repo_dir z-lab/Draft-A)/blobs/w"
    serve status
    assert_out_contains "incomplete (missing: z-lab/Draft-A)"
}

test_status_download_without_draft_model() {
    select_model unsloth/Qwen-B
    fake_download unsloth/Qwen-B
    serve status
    assert_out_contains "Download   complete"
}

test_shared_draft_model_serves_both_model_ids() {
    fake_complete_download
    fake_download unsloth/Qwen-C
    select_model unsloth/Qwen-C z-lab/Draft-A
    serve status
    assert_out_contains "Download   complete"
}

test_download_skips_draft_model_already_fetched() {
    fake_download z-lab/Draft-A
    select_model unsloth/Qwen-C z-lab/Draft-A
    serve download
    assert_status 0
    assert_log_contains "hf download unsloth/Qwen-C"
    assert_log_lacks "hf download z-lab/Draft-A"
}

test_download_skips_complete_download() {
    fake_complete_download
    serve download
    assert_status 0
    assert_out_contains "already downloaded"
    assert_log_lacks "hf download"
}

test_start_refuses_incomplete_blob() {
    fake_complete_download
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/abc.incomplete"
    serve start
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
    serve start
    assert_status 1
    assert_out_contains "nvidia/Qwen-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_start_refuses_dangling_symlink() {
    fake_complete_download
    rm "$(fake_repo_dir nvidia/Qwen-A)/blobs/w"
    serve start
    assert_status 1
    assert_out_contains "nvidia/Qwen-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

test_download_fetches_repo_again_when_cache_broken() {
    fake_complete_download
    touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/abc.incomplete"
    serve download
    assert_status 0
    assert_log_contains "hf download nvidia/Qwen-A"
    assert_log_lacks "hf download z-lab/Draft-A"
}

test_download_fetches_repo_again_when_symlink_dangling() {
    fake_complete_download
    rm "$(fake_repo_dir z-lab/Draft-A)/blobs/w"
    serve download
    assert_status 0
    assert_log_contains "hf download z-lab/Draft-A"
    assert_log_lacks "hf download nvidia/Qwen-A"
}

test_shared_draft_model_complete_and_startable_for_both() {
    fake_complete_download
    fake_download unsloth/Qwen-C
    serve status
    assert_out_contains "Download   complete"
    serve start
    assert_status 0
    assert_log_contains "up --detach"
    : >"${STUB_LOG}"
    select_model unsloth/Qwen-C z-lab/Draft-A
    serve status
    assert_out_contains "Download   complete"
    serve start
    assert_status 0
    assert_log_contains "up --detach"
}

test_shared_draft_model_broken_blocks_both() {
    fake_complete_download
    fake_download unsloth/Qwen-C
    rm "$(fake_repo_dir z-lab/Draft-A)/blobs/w"
    serve start
    assert_status 1
    assert_out_contains "z-lab/Draft-A is not fully downloaded"
    select_model unsloth/Qwen-C z-lab/Draft-A
    serve start
    assert_status 1
    assert_out_contains "z-lab/Draft-A is not fully downloaded"
    assert_log_lacks "up --detach"
}

run_tests
