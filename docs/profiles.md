# Compose profiles and launch flags

Each `id` in `models.json` names its compose service and profile in its `service` field, for example `vllm-nv-qwen3.6-27B-NVFP4`, `vllm-nv-qwen3.8-27B-NVFP4` or `vllm-us-qwen3.8-27B-NVFP4`. Names must start with `vllm-` and exist in `docker-compose.yml`.

An `id` can list `variants`. Each variant is an object `{"name": "...", "service": "..."}` with its own service name, for example `vllm-nv-qwen3.8-27B-NVFP4-instanttensor`. `select` stores the variant name as `MODEL_VARIANT` in `.env.vllm`. The script looks up service names in the registry and never derives them (ADR-0002).

`select` also stores two more registry fields in `.env.vllm`:

- An optional `draft` becomes `DRAFT_MODEL_ID`. The speculative-decoding services interpolate it into `--speculative-config`.
- `context` becomes `MAX_MODEL_LEN`. Every service interpolates it into `--max-model-len`.

`./vllm-serve.sh` maps `MODEL_ID` to the matching service and profile. A manual `docker compose` call needs `--profile <service-name>`.

Compose declares `MAX_MODEL_LEN` as required (`${MAX_MODEL_LEN:?...}`). If it is unset or empty, for example because `.env.vllm` is missing or stale, a manual `docker compose` call fails at once with "run ./vllm-serve.sh select". vLLM never receives an empty `--max-model-len`. Compose checks every service, including inactive profiles, so the check applies to every manual command (`ps`, `down` and others), not only `up`. `./vllm-serve.sh` supplies a placeholder for its non-serving commands `stop` and `status`. `start` and `download` have their own guard.

## Shared settings

`docker-compose.yml` sets these for all services in `x-defaults`:

- Environment variables `CUTE_DSL_ARCH=sm_121a`, `FLASHINFER_DISABLE_VERSION_CHECK=1` and `VLLM_MARLIN_USE_ATOMIC_ADD=1`.
- `--enable-chunked-prefill --enable-prefix-caching --load-format fastsafetensors`.
- A `--speculative-config` with MTP, 3 tokens and `moe_backend: triton`.
- An `--override-generation-config` with the model's recommended sampling defaults `temperature 0.6`, `top_p 0.95`, `top_k 20` and `min_p 0.0`.

The Qwen3.6 services also pass the mounted custom chat template with `--chat-template` (see [Chat template fix](#chat-template-fix)) and `--default-chat-template-kwargs '{"enable_thinking": false, "enable_tool_call": true, "enable_tool_call_streaming": true}'`.

## Per-model differences

- **35B-A3B** uses `--kv-cache-dtype fp8 --attention-backend flashinfer --tool-call-parser qwen3_xml --moe-backend marlin --async-scheduling`.
- **27B** uses `--moe-backend marlin --kv-cache-dtype auto --tool-call-parser qwen3_coder --reasoning-parser qwen3`.
- **Qwen3.8-27B** (nvidia) uses DFlash2 speculative decoding with `--kv-cache-dtype fp8 --async-scheduling --tool-call-parser qwen3_xml --reasoning-parser qwen3`. Its `--speculative-config` sets the draft model `z-lab/Qwen3.8-27B-DFlash2`, 8 tokens and draft TP 1. The context window comes from the registry. The configuration follows the `qwen3.8-27b-nvfp4-dflash2` recipe from spark-vllm-docker (solo, TP=1).
- **Qwen3.8-27B** (nvidia, `instanttensor` variant) has the same configuration with three changes. It runs on `eugr/spark-vllm:latest`, the spark-vllm-docker image, which ships `instanttensor` and a UMA memory-accounting patch. It uses `--load-format instanttensor`. Its command starts with `vllm serve` because that image has no `vllm serve` entrypoint. Select it with the `instanttensor` entry under `nvidia/Qwen3.8-27B-NVFP4` in `models.json`.
- **Qwen3.8-27B** (unsloth) uses `--tool-call-parser qwen3_coder --reasoning-parser qwen3` and DSpark speculative decoding. Its `--speculative-config` sets the draft model `Doopeworld/Qwen3.8-27B-DSpark-vLLM`, 7 tokens and probabilistic draft sampling. It extends the context with YaRN through `--hf-overrides`, the registry `context` as `--max-model-len` and `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1`.

## Chat template fix

`fix-qwen3.6-chat-template/chat_template.jinja` is a custom chat template. Compose mounts it read-only into every vLLM container at `/root/chat_template.jinja`, and the Qwen3.6 services pass it with `--chat-template`. It fixes a bug in the stock Qwen3.6 template in reasoning mode.

## Observability details

The `prometheus` and `grafana` services have no `profiles:`, so they start with every vLLM profile. Both use `network_mode: host` like the vLLM services, so they need no port mapping or `host.docker.internal`.

- Prometheus scrapes `localhost:8000/metrics`, configured in `monitoring/prometheus.yaml`. The target comes from `monitoring/targets/vllm.json` (`file_sd`, gitignored). `vllm-serve.sh start` rewrites this file for every Run with the labels `model_id`, `variant`, `run_start` and `run`. The `run` label has the form `<yyyymmdd-hhmm> <Model ID>[:<variant>]`, with the start time first so the newest Run sorts first. `stop` removes the file. Prometheus does not scrape a container started with plain `docker compose`, because that bypasses the script.
- Prometheus keeps history in the named volume `vllm-prometheus-data` (`/prometheus`) for 15 days or 2 GB, whichever comes first (`--storage.tsdb.retention.time=15d`, `--storage.tsdb.retention.size=2GB`). Grafana keeps annotations, snapshots and preferences in `vllm-grafana-data` (`/var/lib/grafana`). Only `./vllm-serve.sh reset-metrics` or `docker compose down -v` deletes them. `reset-metrics` refuses while vLLM runs and asks for confirmation unless you pass `--yes`.
- Grafana provisions the Prometheus datasource and three dashboards in the `vLLM` folder from `monitoring/grafana/provisioning/` and `monitoring/grafana/dashboards/`:
  - `vllm.json` is the main dashboard from the [prometheus_grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana).
  - `performance_statistics.json` shows latency and throughput, and `query_statistics.json` shows request and query statistics. Both come from the [dashboards/grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/dashboards/grafana).
- Each dashboard has a multi-select `Run` variable. Every query filters on `run=~"$run"` and keeps `run` in its aggregations, so selecting several Runs overlays them as separate series. Grafana does not save provisioned dashboards from the UI. Edit the JSON under `monitoring/grafana/dashboards/` instead.
