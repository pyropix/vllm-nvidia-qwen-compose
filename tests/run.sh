#!/usr/bin/env bash
# Run all vllm-serve tests: ./tests/run.sh [test_file.sh ...]
# Uses a fake HF cache and stub docker/hf/curl/pi; never touches the real ones.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required to run the tests (./setup-cli.sh jq-install)." >&2
  exit 1
fi

files=("$@")
if (( ${#files[@]} == 0 )); then
  files=("${TESTS_DIR}"/test_*.sh)
fi

failed=0
for file in "${files[@]}"; do
  basename "${file}"
  bash "${file}" || failed=1
done
exit "${failed}"
