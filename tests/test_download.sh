#!/usr/bin/env bash
# Download completeness (weights plus Draft model) as seen by status, download and start.
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The fixture's only tokenizer file is tokenizer.json, so this also shows
# tokenizer.json alone is enough for a Model ID.
test_status_download_complete() {
  fake_complete_download
  [[ ! -e "$(fake_snapshot_dir nvidia/Qwen-A)/tokenizer_config.json" ]] \
    || fail "fixture ships tokenizer_config.json"
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

# hf 2.0.0 names a partial blob <blob>.<uuid8>.incomplete. One for a linked blob
# counts even when it is older than refs/main.
test_status_download_linked_uuid_incomplete_blob() {
  fake_complete_download
  touch -d '2 days ago' "$(fake_repo_dir nvidia/Qwen-A)/blobs/w.1a2b3c4d.incomplete"
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

# A partial blob of another blob whose name starts with the linked blob's name
# is not the linked blob's: it falls under the mtime rule, so a stale one is ignored.
test_status_download_ignores_stale_incomplete_blob_sharing_linked_prefix() {
  fake_complete_download
  touch -d '1 hour ago' "$(fake_repo_dir nvidia/Qwen-A)/refs/main"
  touch -d '2 days ago' "$(fake_repo_dir nvidia/Qwen-A)/blobs/wx.incomplete" \
    "$(fake_repo_dir nvidia/Qwen-A)/blobs/wx.1a2b3c4d.incomplete"
  run_script status
  assert_out_contains "Download   complete"
}

test_status_download_unlinked_uuid_incomplete_blob() {
  fake_complete_download
  touch -d '1 hour ago' "$(fake_repo_dir nvidia/Qwen-A)/refs/main"
  touch "$(fake_repo_dir nvidia/Qwen-A)/blobs/cfg.1a2b3c4d.incomplete"
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_ignores_stale_unlinked_uuid_incomplete_blob() {
  fake_complete_download
  touch -d '1 hour ago' "$(fake_repo_dir nvidia/Qwen-A)/refs/main"
  touch -d '2 days ago' "$(fake_repo_dir nvidia/Qwen-A)/blobs/cfg.1a2b3c4d.incomplete"
  run_script status
  assert_out_contains "Download   complete"
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
  snapshot="$(fake_snapshot_dir nvidia/Qwen-A)"
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
  snapshot="$(fake_snapshot_dir nvidia/Qwen-A)"
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
  snapshot="$(fake_snapshot_dir "$1")"
  rm "${snapshot}/model.safetensors"
  ln -s ../../blobs/w "${snapshot}/$2"
}

test_status_download_safetensors_weights_complete() {
  fake_download nvidia/Qwen-A
  fake_download_as z-lab/Draft-A weights.safetensors
  run_script status
  assert_out_contains "Download   complete"
}

# Only safetensors is supported: no Model ID in the registry ships another format.
test_status_download_unsupported_weight_format_incomplete() {
  local ext
  for ext in bin gguf pt pth ckpt onnx; do
    rm -rf "$(fake_repo_dir z-lab/Draft-A)" "$(fake_repo_dir nvidia/Qwen-A)"
    fake_download nvidia/Qwen-A
    fake_download_as z-lab/Draft-A "weights.${ext}"
    run_script status
    assert_out_contains "incomplete (missing: z-lab/Draft-A)"
  done
}

test_status_download_without_weight_files_incomplete() {
  fake_complete_download
  local snapshot
  snapshot="$(fake_snapshot_dir z-lab/Draft-A)"
  rm "${snapshot}/model.safetensors"
  run_script status
  assert_out_contains "incomplete (missing: z-lab/Draft-A)"
}

test_status_download_all_shards_present_in_safetensors_index() {
  fake_complete_download
  echo '{"weight_map":{"a":"model.safetensors"}}' \
    >"$(fake_snapshot_dir nvidia/Qwen-A)/model.safetensors.index.json"
  run_script status
  assert_out_contains "Download   complete"
}

test_status_download_ignores_non_weight_index() {
  fake_complete_download
  echo '{"weight_map":{"a":"missing.bin"}}' \
    >"$(fake_snapshot_dir nvidia/Qwen-A)/tokenizer.index.json"
  run_script status
  assert_out_contains "Download   complete"
}

# A weight index that cannot be read as a shard list makes the Download incomplete.
assert_malformed_index_incomplete() {
  fake_complete_download
  printf '%s' "$1" >"$(fake_snapshot_dir nvidia/Qwen-A)/model.safetensors.index.json"
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_index_not_json_incomplete() { assert_malformed_index_incomplete 'not json'; }
test_status_download_index_without_weight_map_incomplete() { assert_malformed_index_incomplete '{}'; }
test_status_download_index_empty_weight_map_incomplete() { assert_malformed_index_incomplete '{"weight_map":{}}'; }
test_status_download_index_weight_map_not_object_incomplete() { assert_malformed_index_incomplete '{"weight_map":["model.safetensors"]}'; }
test_status_download_index_non_string_shard_incomplete() { assert_malformed_index_incomplete '{"weight_map":{"a":1}}'; }

# A listed shard counts only as a snapshot symlink to a blob of its repo (#43):
# with model.safetensors listed in the index, put <target> in its place.
assert_listed_shard_incomplete() {
  fake_complete_download
  local snapshot
  snapshot="$(fake_snapshot_dir nvidia/Qwen-A)"
  echo '{"weight_map":{"a":"model.safetensors"}}' >"${snapshot}/model.safetensors.index.json"
  rm "${snapshot}/model.safetensors"
  echo weights >"${SANDBOX}/model.safetensors"
  case "$1" in
    regular-file) cp "${SANDBOX}/model.safetensors" "${snapshot}/model.safetensors" ;;
    outside-link) ln -s "${SANDBOX}/model.safetensors" "${snapshot}/model.safetensors" ;;
  esac
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_listed_shard_regular_file_incomplete() { assert_listed_shard_incomplete regular-file; }
test_status_download_listed_shard_link_outside_blobs_incomplete() { assert_listed_shard_incomplete outside-link; }

# Required files: config.json in every repo; a tokenizer in Model ID repos only.
# See docs/adr/0005-fixed-required-files.md.
test_status_download_model_id_missing_config_incomplete() {
  fake_complete_download
  rm "$(fake_snapshot_dir nvidia/Qwen-A)/config.json"
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_model_id_missing_tokenizer_incomplete() {
  fake_complete_download
  rm "$(fake_snapshot_dir nvidia/Qwen-A)/tokenizer.json"
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_model_id_tokenizer_config_alone_complete() {
  fake_complete_download
  local snapshot
  snapshot="$(fake_snapshot_dir nvidia/Qwen-A)"
  mv "${snapshot}/tokenizer.json" "${snapshot}/tokenizer_config.json"
  run_script status
  assert_out_contains "Download   complete"
}

test_status_download_draft_model_without_tokenizer_complete() {
  fake_complete_download
  rm "$(fake_snapshot_dir z-lab/Draft-A)/tokenizer.json"
  run_script status
  assert_out_contains "Download   complete"
}

test_status_download_draft_model_missing_config_incomplete() {
  fake_complete_download
  rm "$(fake_snapshot_dir z-lab/Draft-A)/config.json"
  run_script status
  assert_out_contains "incomplete (missing: z-lab/Draft-A)"
}

# A required file counts only as a snapshot symlink to an existing blob (#40):
# replacing <file> in nvidia/Qwen-A with a regular file makes it incomplete.
assert_regular_file_incomplete() {
  fake_complete_download
  local file
  file="$(fake_snapshot_dir nvidia/Qwen-A)/$1"
  rm "${file}"
  echo '{}' >"${file}"
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_status_download_model_id_config_regular_file_incomplete() { assert_regular_file_incomplete config.json; }
test_status_download_model_id_tokenizer_regular_file_incomplete() { assert_regular_file_incomplete tokenizer.json; }

test_status_download_model_id_config_link_outside_blobs_incomplete() {
  fake_complete_download
  local file
  file="$(fake_snapshot_dir nvidia/Qwen-A)/config.json"
  echo '{}' >"${SANDBOX}/config.json"
  ln -sf "${SANDBOX}/config.json" "${file}"
  run_script status
  assert_out_contains "incomplete (missing: nvidia/Qwen-A)"
}

test_start_refuses_model_id_missing_config() {
  fake_complete_download
  rm "$(fake_snapshot_dir nvidia/Qwen-A)/config.json"
  run_script start
  assert_status 1
  assert_out_contains "nvidia/Qwen-A is not fully downloaded"
  assert_log_lacks "up --detach"
}

run_tests
