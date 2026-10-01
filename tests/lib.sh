# shellcheck shell=bash
# Shared helpers for the vllm-serve tests. Sourced by test files.
# Each test runs in a sandbox: a copy of the script next to a test registry,
# compose file and .env.vllm, with HOME pointing at a fake HF cache and
# stub docker/hf/curl/pi/sleep first on PATH. Stubs append their argv to $STUB_LOG.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUBS_DIR="${REPO_DIR}/tests/stubs"

# Compose service names of the sandbox models.json fixtures, as stored in the
# registry. They follow no naming convention on purpose. Tests refer to these,
# never to literals.
SVC_A="vllm-alpha"
SVC_A_FAST="vllm-alpha-turbo"
SVC_B="vllm-beta-service"
SVC_C="vllm-gamma"

ORIGINAL_PATH="${PATH}"
FAILURES=0
TESTS=0

# Create a fresh sandbox and export the variables the stubs and script rely on.
sandbox_new() {
  SANDBOX="$(mktemp -d)"
  export HOME="${SANDBOX}/home"
  export STUB_LOG="${SANDBOX}/stub.log"
  export STUB_DOCKER_PS="${SANDBOX}/docker-ps"
  export STUB_DOCKER_LOGS="${SANDBOX}/docker-logs"
  export STUB_CURL_OUT="${SANDBOX}/curl-out"
  export STUB_CURL_FAIL=""
  export STUB_CURL_FAIL_TIMES=""
  export STUB_CURL_CALLS="${SANDBOX}/curl-calls"
  export STUB_HF_FAIL=""
  mkdir -p "${HOME}/.local"
  : >"${STUB_LOG}"
  : >"${STUB_DOCKER_PS}"
  : >"${STUB_DOCKER_LOGS}"
  : >"${STUB_CURL_OUT}"
  cp "${REPO_DIR}/vllm-serve.sh" "${SANDBOX}/vllm-serve.sh"
  cp -r "${REPO_DIR}/lib" "${SANDBOX}/lib"
  cat >"${SANDBOX}/models.json" <<'JSON'
[
  {"id": "nvidia/Qwen-A", "service": "vllm-alpha", "context": 1001, "draft": "z-lab/Draft-A",
   "variants": [{"name": "fast", "service": "vllm-alpha-turbo"}]},
  {"id": "unsloth/Qwen-B", "service": "vllm-beta-service", "context": 1002},
  {"id": "unsloth/Qwen-C", "service": "vllm-gamma", "context": 1003, "draft": "z-lab/Draft-A"}
]
JSON
  {
    echo "services:"
    local svc
    for svc in "${SVC_A}" "${SVC_A_FAST}" "${SVC_B}" "${SVC_C}"; do
      printf '  %s:\n    profiles: [%s]\n' "${svc}" "${svc}"
    done
  } >"${SANDBOX}/docker-compose.yml"
  cat >"${SANDBOX}/.env.vllm" <<'ENV'
HF_TOKEN=test-token
MODEL_ID=nvidia/Qwen-A
MODEL_VARIANT=
DRAFT_MODEL_ID=z-lab/Draft-A
MAX_MODEL_LEN=
ENV
  select_model nvidia/Qwen-A
  export PATH="${STUBS_DIR}:${ORIGINAL_PATH}"
  # Never let a missing stub fall through to the real tool.
  local tool
  for tool in docker hf curl pi sleep; do
    [[ "$(command -v "${tool}")" == "${STUBS_DIR}/${tool}" ]] \
      || { echo "Error: ${tool} does not resolve to its stub." >&2; exit 1; }
  done
}

sandbox_free() {
  rm -rf "${SANDBOX}"
}

# Put a fully downloaded repo into the fake HF cache.
fake_download() {
  local repo_dir snapshot
  repo_dir="$(fake_repo_dir "$1")"
  snapshot="$(fake_snapshot_dir "$1")"
  mkdir -p "${repo_dir}/refs" "${snapshot}" "${repo_dir}/blobs"
  basename "${snapshot}" >"${repo_dir}/refs/main"
  echo weights >"${repo_dir}/blobs/w"
  echo '{}' >"${repo_dir}/blobs/config"
  echo '{}' >"${repo_dir}/blobs/tokenizer"
  ln -s ../../blobs/w "${snapshot}/model.safetensors"
  ln -s ../../blobs/config "${snapshot}/config.json"
  ln -s ../../blobs/tokenizer "${snapshot}/tokenizer.json"
}

# Fully download nvidia/Qwen-A and its Draft model.
fake_complete_download() {
  fake_download nvidia/Qwen-A
  fake_download z-lab/Draft-A
}

# Select a Model ID in the sandbox .env.vllm; its Draft model comes from the
# sandbox registry so fixtures cannot drift from it.
select_model() {
  local draft context
  draft="$(jq -r --arg id "$1" '.[] | select(.id == $id) | .draft // empty' "${SANDBOX}/models.json")"
  context="$(jq -r --arg id "$1" '.[] | select(.id == $id) | .context // empty' "${SANDBOX}/models.json")"
  sed -i -e "s|^MODEL_ID=.*|MODEL_ID=$1|" -e "s|^DRAFT_MODEL_ID=.*|DRAFT_MODEL_ID=${draft}|" \
    -e "s|^MAX_MODEL_LEN=.*|MAX_MODEL_LEN=${context}|" "${SANDBOX}/.env.vllm"
}

# Path of a repo's directory in the fake HF cache.
fake_repo_dir() {
  echo "${HOME}/.cache/huggingface/hub/models--${1//\//--}"
}

# Path of a repo's snapshot directory (revision rev1) in the fake HF cache.
fake_snapshot_dir() {
  echo "$(fake_repo_dir "$1")/snapshots/rev1"
}

# Run vllm-serve.sh in the sandbox; sets OUT (stdout+stderr) and STATUS.
# run_script [--stdin INPUT] [--timeout SECS] ARGS...: run the sandbox script,
# setting OUT and STATUS. Stdin is exactly INPUT (no newline added; empty
# without --stdin), then end of input. --timeout kills the script after SECS,
# so an end-of-input loop fails the test instead of hanging the suite.
run_script() {
  local input="" secs=""
  while (( $# )); do
    case "$1" in
      --stdin) input="$2"; shift 2 ;;
      --timeout) secs="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  set +e
  if [[ -n "${secs}" ]]; then
    OUT="$(cd "${SANDBOX}" && printf '%s' "${input}" | timeout "${secs}" ./vllm-serve.sh "$@" 2>&1)"
  else
    OUT="$(cd "${SANDBOX}" && printf '%s' "${input}" | ./vllm-serve.sh "$@" 2>&1)"
  fi
  STATUS=$?
  set -e
  [[ -z "${secs}" || "${STATUS}" != 124 ]] || fail "timed out: loops on end of input. Output: ${OUT: -500}"
}

stub_log() { cat "${STUB_LOG}"; }

# Source every module of DIR (a repo or sandbox copy) the way vllm-serve.sh
# does: its variables (unless already set) pointing at the sandbox, then
# lib/require.sh and the modules in its order, so every guard passes.
source_modules() {
  local dir="$1" module
  SCRIPT_DIR="${SCRIPT_DIR:-${SANDBOX}}"
  ENV_FILE="${ENV_FILE:-${SANDBOX}/.env.vllm}"
  MODELS_FILE="${MODELS_FILE:-${SANDBOX}/models.json}"
  TARGETS_FILE="${TARGETS_FILE:-${SANDBOX}/monitoring/targets/vllm.json}"
  # shellcheck disable=SC2016  # matches the literal ${SCRIPT_DIR}
  while IFS= read -r module; do
    # shellcheck source=/dev/null
    source "${dir}/${module}"
  done < <(sed -n 's|^source "${SCRIPT_DIR}/\(lib/[a-z_]*\.sh\)"$|\1|p' "${dir}/vllm-serve.sh")
}

# Print VLLM_ADDR as the repo's lib/status.sh defines it (the single source,
# ADR 0003). Sources in a subshell, so the caller's shell stays unchanged.
vllm_addr() {
  (
    source_modules "${REPO_DIR}"
    echo "${VLLM_ADDR}"
  )
}

# Record a failure. Tests run in a subshell (see run_tests), so the flag is a file.
fail() {
  echo "    FAIL: $*" >&2
  touch "${SANDBOX}/.test-failed"
}

assert_status() {
  [[ "${STATUS}" == "$1" ]] || fail "exit status ${STATUS}, expected $1. Output: ${OUT}"
}

assert_out_contains() {
  [[ "${OUT}" == *"$1"* ]] || fail "output lacks '$1'. Output: ${OUT}"
}

assert_log_contains() {
  [[ "$(stub_log)" == *"$1"* ]] || fail "stub log lacks '$1'. Log: $(stub_log)"
}

assert_log_lacks() {
  [[ "$(stub_log)" != *"$1"* ]] || fail "stub log has unexpected '$1'. Log: $(stub_log)"
}

# Run every function whose name starts with test_ in its own sandbox.
run_tests() {
  local fn status
  for fn in $(declare -F | awk '{print $3}' | grep '^test_'); do
    TESTS=$((TESTS + 1))
    TEST_FAILED=0
    sandbox_new
    # Run in a subshell with errexit on, so a failing bare command fails the
    # test. Not in a ||/if context: that would silently disable errexit.
    set +e
    ( set -e; "${fn}" )
    status=$?
    (( status == 0 )) || TEST_FAILED=1
    set -e
    [[ ! -e "${SANDBOX}/.test-failed" ]] || TEST_FAILED=1
    sandbox_free
    if (( TEST_FAILED )); then
      FAILURES=$((FAILURES + 1))
      echo "  not ok - ${fn}"
    else
      echo "  ok - ${fn}"
    fi
  done
  (( FAILURES == 0 ))
}
