# Compose profiles and launch flags

Each `MODEL_ID` in `models.conf` has its own compose service/profile of the same name, prefixed `vllm-nv-` — e.g. `vllm-nv-qwen3.6-27B-NVFP4`, `vllm-nv-qwen3.6-35B-A3B-NVFP4`, `vllm-nv-qwen3.8-27B-NVFP4`. `./vllm-serve.sh` maps `MODEL_ID` to the matching service/profile automatically; manual `docker compose` requires `--profile <service-name>`.

## Shared settings

All services share `CUTE_DSL_ARCH=sm_121a`, `FLASHINFER_DISABLE_VERSION_CHECK=1`, and `VLLM_MARLIN_USE_ATOMIC_ADD=1` (set once in `docker-compose.yml`'s `x-defaults`), `--enable-chunked-prefill --enable-prefix-caching --load-format fastsafetensors`, a `--speculative-config` (MTP, 3 tokens, `moe_backend: triton`), and an `--override-generation-config` with the model's recommended sampling defaults (`temperature 0.6`, `top_p 0.95`, `top_k 20`, `min_p 0.0`).

The Qwen3.6 services additionally use the mounted custom chat template (`--chat-template`, see [Chat template fix](#chat-template-fix)) and `--default-chat-template-kwargs '{"enable_thinking": false, "enable_tool_call": true, "enable_tool_call_streaming": true}'`.

## Per-model differences

- **35B-A3B** uses `--kv-cache-dtype fp8 --attention-backend flashinfer --tool-call-parser qwen3_xml --moe-backend marlin --async-scheduling`.
- **27B** uses `--moe-backend marlin --kv-cache-dtype auto --tool-call-parser qwen3_coder --reasoning-parser qwen3`.
- **Qwen3.8-27B** (unsloth) uses `--tool-call-parser qwen3_coder --reasoning-parser qwen3`, DSpark speculative decoding (`--speculative-config` with the draft model `Doopeworld/Qwen3.8-27B-DSpark-vLLM`, 7 tokens, probabilistic draft sampling), and a 1M-token YaRN context extension (`--max-model-len 1048576` via `--hf-overrides`, `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1`).

## Chat template fix

`fix-qwen3.6-chat-template/chat_template.jinja` is a custom chat template mounted read-only into every vLLM container (`/root/chat_template.jinja`) and passed via `--chat-template` by the Qwen3.6 services, fixing an issue with the stock Qwen3.6 template in reasoning mode.

## Observability details

The `prometheus` and `grafana` services have no `profiles:`, so they always start alongside whichever vLLM variant profile is selected. Both use `network_mode: host` like the vLLM services, so no port mapping or `host.docker.internal` plumbing is needed.

- Prometheus scrapes `localhost:8000/metrics` (config: `monitoring/prometheus.yaml`).
- Grafana auto-provisions the Prometheus datasource plus three dashboards (all in the `vLLM` folder) from `monitoring/grafana/provisioning/` and `monitoring/grafana/dashboards/`:
  - `vllm.json` — the main dashboard from the [prometheus_grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana).
  - `performance_statistics.json` / `query_statistics.json` — latency/throughput and request/query statistics, from the [dashboards/grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/dashboards/grafana).
