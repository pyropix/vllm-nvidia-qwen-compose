#!/usr/bin/env bash
set -euxo pipefail

docker compose pull
docker compose up --detach --remove-orphans
