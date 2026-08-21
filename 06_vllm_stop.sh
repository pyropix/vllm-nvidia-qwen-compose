#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker compose \
    --project-directory "${SCRIPT_DIR}" \
    down --remove-orphans
