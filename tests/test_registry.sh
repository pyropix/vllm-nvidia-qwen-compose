#!/usr/bin/env bash
# Registry module: loading, Model ID/Variant lookup and MODEL_ID[:variant] parsing.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Source the module from the sandbox copy, pointing it at the sandbox registry.
use_registry() {
  MODELS_FILE="${SANDBOX}/models.json"
  # shellcheck source=lib/require.sh
  source "${SANDBOX}/lib/require.sh"
  # shellcheck source=lib/registry.sh
  source "${SANDBOX}/lib/registry.sh"
}

test_load_lists_one_entry_per_service() {
  use_registry
  registry_load
  [[ "${models[*]}" == "nvidia/Qwen-A nvidia/Qwen-A:fast unsloth/Qwen-B unsloth/Qwen-C" ]] \
    || fail "models: ${models[*]}"
}

test_load_fails_on_empty_registry() {
  use_registry
  echo '[]' >"${MODELS_FILE}"
  if OUT="$(registry_load 2>&1)"; then fail "expected failure"; fi
  [[ "${OUT}" == *"no models defined"* ]] || fail "output: ${OUT}"
}

test_load_fails_on_missing_registry() {
  use_registry
  rm "${MODELS_FILE}"
  if OUT="$(registry_load 2>&1)"; then fail "expected failure"; fi
  [[ "${OUT}" == *"not found"* ]] || fail "output: ${OUT}"
}

test_ids_lists_each_model_id_once() {
  use_registry
  [[ "$(registry_ids)" == $'nvidia/Qwen-A\nunsloth/Qwen-B\nunsloth/Qwen-C' ]] \
    || fail "ids: $(registry_ids)"
}

test_lookup_draft_and_context() {
  use_registry
  [[ "$(registry_draft nvidia/Qwen-A)" == "z-lab/Draft-A" ]] || fail "draft A"
  [[ -z "$(registry_draft unsloth/Qwen-B)" ]] || fail "draft B should be empty"
  [[ "$(registry_context unsloth/Qwen-B)" == "1002" ]] || fail "context B"
  [[ -z "$(registry_context nope/Unknown)" ]] || fail "unknown context should be empty"
}

test_parse_entry_without_variant() {
  use_registry
  registry_parse_entry "unsloth/Qwen-B"
  [[ "${ENTRY_MODEL_ID}" == "unsloth/Qwen-B" && -z "${ENTRY_VARIANT}" ]] \
    || fail "id=${ENTRY_MODEL_ID} variant=${ENTRY_VARIANT}"
}

test_parse_entry_with_variant() {
  use_registry
  registry_parse_entry "nvidia/Qwen-A:fast"
  [[ "${ENTRY_MODEL_ID}" == "nvidia/Qwen-A" && "${ENTRY_VARIANT}" == "fast" ]] \
    || fail "id=${ENTRY_MODEL_ID} variant=${ENTRY_VARIANT}"
}

run_tests
