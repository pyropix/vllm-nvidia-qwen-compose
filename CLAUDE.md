# Hardware

- **Machine:** Lenovo ThinkStation PGX — NVIDIA GB10 Grace Blackwell Superchip
- **CUDA Compute Capability:** 12.1 (sm_121a — same chip as NVIDIA DGX Spark)

## vLLM: Qwen3.6 variants — flags

Common to every service (`x-defaults` in `docker-compose.yml`):

- `--dtype auto --quantization modelopt`
- env: `CUTE_DSL_ARCH=sm_121a`, `FLASHINFER_DISABLE_VERSION_CHECK=1`, `VLLM_MARLIN_USE_ATOMIC_ADD=1` — applies to nvidia and unsloth alike (not unsloth-only)
- volumes: `~/.cache/vllm` is mounted alongside `~/.cache/huggingface` so JIT/autotune kernel caches (Marlin, flashinfer, CUTE-DSL) survive container restarts instead of recompiling on every `start`

## 35B-A3B variants (nvidia, unsloth, and unsloth `-Fast`)

- Common: `--kv-cache-dtype fp8 --attention-backend flashinfer --tool-call-parser qwen3_xml`
- nvidia, unsloth (plain), and unsloth `-Fast`: `--moe-backend marlin` — flashinfer_b12x does not work on these weights; flashinfer_cutlass incompatible with f8e4m3fn quant scheme; triton not valid for NvFP4; marlin is the working fallback across all three variants
- nvidia: `--async-scheduling`, `--speculative-config '{"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton"}'`
- unsloth (plain and `-Fast`): `--speculative-config '{"method":"mtp","num_speculative_tokens":2}'` (no `moe_backend` key, no `--async-scheduling`)

## 27B variants (nvidia & unsloth)

- `--moe-backend marlin` — flashinfer_b12x/linear-backend flashinfer_b12x (unsloth's [recommended DGX Spark config](https://huggingface.co/unsloth/Qwen3.6-27B-NVFP4#dgx-spark)) does not work on these weights; marlin is the working fallback
- `--tool-call-parser qwen3_coder`
- `--default-chat-template-kwargs '{"enable_thinking": true}'`
- nvidia: `--speculative-config '{"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton"}'`
- unsloth: `--speculative-config '{"method":"mtp","num_speculative_tokens":2}'`

## Project: vllm-nvidea-qwen3.6-compose

A Docker Compose setup that serves Qwen3.6-35B-A3B-NVFP4 as an
OpenAI-compatible API on `http://localhost:8000`.
Image: `vllm/vllm-openai:latest-aarch64`.

This directory is its own git repository, nested inside the parent
`2026_vllm/` project folder (which is not under git).

## Workflow

One-time setup (run once per machine — from this directory):

- `./setup-cli.sh` — install/manage the Hugging Face CLI and pi agent CLI (`hf-install|hf-reinstall|hf-with-transformers|hf-check|hf-uninstall|pi-install|pi-check|pi-update|pi-uninstall`, no args → interactive menu)

Day-to-day via `./vllm-serve.sh [select|download|start|logs|stop|pi|link|unlink]` (no args → interactive menu)

| Command                    | Description                                           |
| -------------------------- | ----------------------------------------------------- |
| `./vllm-serve.sh`          | Interactive menu                                      |
| `./vllm-serve.sh select`   | Pick model variant from `models.conf`                 |
| `./vllm-serve.sh download` | Login to HF and download model weights                |
| `./vllm-serve.sh start`    | Pull image and start vLLM container on :8000          |
| `./vllm-serve.sh logs`     | Tail container logs                                   |
| `./vllm-serve.sh stop`     | Stop and remove the container                         |
| `./vllm-serve.sh pi`       | Launch pi agent pointed at local vLLM server          |
| `./vllm-serve.sh link`     | Symlink this script as `vllm-serve` in `~/.local/bin` |
| `./vllm-serve.sh unlink`   | Remove that symlink                                   |

## Config

- Copy `.env.vllm.example` → `.env.vllm`, set `HF_TOKEN` and `MODEL_ID`
- `models.conf` lists the model IDs offered by `./vllm-serve.sh select`; currently includes 35B and 27B variants for both `nvidia/*` and `unsloth/*`, plus `unsloth/Qwen3.6-35B-A3B-NVFP4-Fast`. Add a line to make a new variant selectable
- Each `MODEL_ID` in `models.conf` has its own compose service/profile of the same name, prefixed `vllm-nv-` or `vllm-uns-` (e.g. `vllm-nv-qwen3.6-27B-NVFP4`, `vllm-uns-qwen3.6-35B-A3B-NVFP4-fast`); `vllm-serve.sh`'s `get_service` maps `MODEL_ID` → service by prefix match
- Profiles are selected automatically by `./vllm-serve.sh start`; manual `docker compose` requires `--profile <service-name>`
- Adding a model variant requires a matching service in `docker-compose.yml` **and** a case arm in `get_service()` in `vllm-serve.sh`, in addition to the `models.conf` line
- Served at `http://localhost:8000` as `qwen3.6-35B-A3B-NVFP4` (OpenAI-compatible)
- `--gpu-memory-utilization 0.4`, `--max-model-len 262144`, `--max-num-seqs 4`
- Tool use: `--enable-auto-tool-choice`; `--tool-call-parser qwen3_xml` (35B) or `qwen3_coder` (27B)
- Reasoning: `--reasoning-parser qwen3`

## Observability

`docker-compose.yml` also defines `prometheus` and `grafana` services (from vLLM's [prometheus_grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana)), both `network_mode: host`, no `profiles:` — they start on every `./vllm-serve.sh start` regardless of model profile. Config lives under `monitoring/`: `monitoring/prometheus.yaml` scrapes `localhost:8000`; `monitoring/grafana/provisioning/` auto-provisions the Prometheus datasource and every dashboard JSON in `monitoring/grafana/dashboards/` (`vllm.json` from the prometheus_grafana example, plus `performance_statistics.json`/`query_statistics.json` from vLLM's [dashboards/grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/dashboards/grafana)). Prometheus: `http://localhost:9090`, Grafana: `http://localhost:3000` (`admin`/`admin`).

## pi Agent Integration

Point the pi agent at the local vLLM server:

```bash
./vllm-serve.sh pi
```

The vLLM provider (base URL, API key, and the served model list) is configured in
`.pi/agent/models.json`; `cmd_pi` just runs `pi --model "${MODEL_ID}"`.

## Verify Server

```bash
curl http://localhost:8000/v1/models
```

## Parent-Level Files

- `AGENTS.md` (this repo, tracked in git) — one-line pointer (`@CLAUDE.md`) so agents auto-discover this file
- `../git-local-user-pyropix.sh` — Sets git identity to `pyropix` for this subproject

## Git

- Use semantic commit messages: `type(scope): description`
- Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`
- Example: `feat(vllm): add flashinfer backend for unsloth variant`
- Commit from this directory (has its own `.git`)
