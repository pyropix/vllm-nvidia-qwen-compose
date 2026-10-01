# shellcheck shell=bash
# Shared helpers for the vllm-serve tests. Sourced by test files.
# Each test runs in a sandbox: a copy of the script next to a test registry,
# compose file and .env.vllm, with HOME pointing at a fake HF cache and
# stub docker/hf/curl/pi first on PATH. Stubs append their argv to $STUB_LOG.

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
    for tool in docker hf curl pi; do
        [[ "$(command -v "${tool}")" == "${STUBS_DIR}/${tool}" ]] \
            || { echo "Error: ${tool} does not resolve to its stub." >&2; exit 1; }
    done
}

sandbox_free() {
    rm -rf "${SANDBOX}"
}

# Put a fully downloaded repo into the fake HF cache.
fake_download() {
    local repo_dir="${HOME}/.cache/huggingface/hub/models--${1//\//--}"
    mkdir -p "${repo_dir}/refs" "${repo_dir}/snapshots/rev1" "${repo_dir}/blobs"
    echo rev1 >"${repo_dir}/refs/main"
    echo weights >"${repo_dir}/blobs/w"
    ln -s ../../blobs/w "${repo_dir}/snapshots/rev1/model.safetensors"
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

# Run vllm-serve.sh in the sandbox; sets OUT (stdout+stderr) and STATUS.
# Stdin is empty unless the first arguments are `--stdin TEXT`.
run_script() {
    local input=""
    if [[ "${1:-}" == "--stdin" ]]; then
        input="$2"
        shift 2
    fi
    set +e
    OUT="$(cd "${SANDBOX}" && ./vllm-serve.sh "$@" 2>&1 <<<"${input}")"
    STATUS=$?
    set -e
}

stub_log() { cat "${STUB_LOG}"; }

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
