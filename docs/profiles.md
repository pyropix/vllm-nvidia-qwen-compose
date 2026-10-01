# Compose profiles and launch flags

Each `id` in `models.json` names its compose service/profile in its `service` field — e.g. `vllm-nv-qwen3.6-27B-NVFP4`, `vllm-nv-qwen3.8-27B-NVFP4`, `vllm-us-qwen3.8-27B-NVFP4`. Names must start with `vllm-` and exist in `docker-compose.yml`. An entry in an `id`'s `variants` list is an object `{"name": "...", "service": "..."}` with its own service name (e.g. `vllm-nv-qwen3.8-27B-NVFP4-instanttensor`); `select` stores the variant name as `MODEL_VARIANT` in `.env.vllm`. Service names are looked up in the registry, never derived (ADR-0002). An `id`'s optional `draft` is stored as `DRAFT_MODEL_ID`, which the speculative-decoding services interpolate into `--speculative-config`. An `id`'s `context` is stored as `MAX_MODEL_LEN`, which every service interpolates into `--max-model-len`. `./vllm-serve.sh` maps `MODEL_ID` to the matching service/profile automatically; manual `docker compose` requires `--profile <service-name>`.

## Shared settings

All services share `CUTE_DSL_ARCH=sm_121a`, `FLASHINFER_DISABLE_VERSION_CHECK=1`, and `VLLM_MARLIN_USE_ATOMIC_ADD=1` (set once in `docker-compose.yml`'s `x-defaults`), `--enable-chunked-prefill --enable-prefix-caching --load-format fastsafetensors`, a `--speculative-config` (MTP, 3 tokens, `moe_backend: triton`), and an `--override-generation-config` with the model's recommended sampling defaults (`temperature 0.6`, `top_p 0.95`, `top_k 20`, `min_p 0.0`).

The Qwen3.6 services additionally use the mounted custom chat template (`--chat-template`, see [Chat template fix](#chat-template-fix)) and `--default-chat-template-kwargs '{"enable_thinking": false, "enable_tool_call": true, "enable_tool_call_streaming": true}'`.

## Per-model differences

- **35B-A3B** uses `--kv-cache-dtype fp8 --attention-backend flashinfer --tool-call-parser qwen3_xml --moe-backend marlin --async-scheduling`.
- **27B** uses `--moe-backend marlin --kv-cache-dtype auto --tool-call-parser qwen3_coder --reasoning-parser qwen3`.
- **Qwen3.8-27B** (nvidia) uses DFlash2 speculative decoding (`--speculative-config` with the draft model `z-lab/Qwen3.8-27B-DFlash2`, 8 tokens, draft TP 1), `--kv-cache-dtype fp8 --async-scheduling --tool-call-parser qwen3_xml --reasoning-parser qwen3`, and a 262144-token context. Based on the `qwen3.8-27b-nvfp4-dflash2` recipe from spark-vllm-docker (solo, TP=1).
- **Qwen3.8-27B** (nvidia, `instanttensor` variant) is the same configuration as above but runs on `eugr/spark-vllm:latest` (the spark-vllm-docker image, which ships `instanttensor` and a UMA memory-accounting patch) with `--load-format instanttensor`, and its command starts with `vllm serve` because that image has no `vllm serve` entrypoint. Select it via the `instanttensor` entry under `nvidia/Qwen3.8-27B-NVFP4` in `models.json`.
- **Qwen3.8-27B** (unsloth) uses `--tool-call-parser qwen3_coder --reasoning-parser qwen3`, DSpark speculative decoding (`--speculative-config` with the draft model `Doopeworld/Qwen3.8-27B-DSpark-vLLM`, 7 tokens, probabilistic draft sampling), and a 1M-token YaRN context extension (`--max-model-len 1048576` via `--hf-overrides`, `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1`).

## Chat template fix

`fix-qwen3.6-chat-template/chat_template.jinja` is a custom chat template mounted read-only into every vLLM container (`/root/chat_template.jinja`) and passed via `--chat-template` by the Qwen3.6 services, fixing an issue with the stock Qwen3.6 template in reasoning mode.

## Observability details

The `prometheus` and `grafana` services have no `profiles:`, so they always start alongside whichever vLLM variant profile is selected. Both use `network_mode: host` like the vLLM services, so no port mapping or `host.docker.internal` plumbing is needed.

- Prometheus scrapes `localhost:8000/metrics` (config: `monitoring/prometheus.yaml`). The target comes from `monitoring/targets/vllm.json` (`file_sd`, gitignored), which `vllm-serve.sh start` rewrites for every Run with the labels `model_id`, `variant`, `run_start` and `run` (`<yyyymmdd-hhmm> <Model ID>[:<variant>]`, start time first so the newest Run sorts first). `stop` removes the file. A container started with plain `docker compose` bypasses the script and is therefore not scraped.
- History lives in the named volumes `vllm-prometheus-data` (`/prometheus`; `--storage.tsdb.retention.time=15d`, `--storage.tsdb.retention.size=2GB`, whichever is hit first) and `vllm-grafana-data` (`/var/lib/grafana`: annotations, snapshots, preferences). Only `./vllm-serve.sh reset-metrics` (or `docker compose down -v`) deletes them; `reset-metrics` refuses while vLLM runs and asks for confirmation unless given `--yes`.
- All three dashboards have a multi-select `Run` variable and every query filters on `run=~"$run"` and keeps `run` in its aggregations, so selecting several Runs overlays them as separate series. Provisioned dashboards are not saved from the UI: edit the JSON under `monitoring/grafana/dashboards/` instead.
- Grafana auto-provisions the Prometheus datasource plus three dashboards (all in the `vLLM` folder) from `monitoring/grafana/provisioning/` and `monitoring/grafana/dashboards/`:
  - `vllm.json` — the main dashboard from the [prometheus_grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana).
  - `performance_statistics.json` / `query_statistics.json` — latency/throughput and request/query statistics, from the [dashboards/grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/dashboards/grafana).
