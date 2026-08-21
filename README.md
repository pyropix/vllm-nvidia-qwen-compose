# vLLM NVidea Qwen3.6 Compose

Runs Qwen3.6 models as an OpenAI-compatible inference server using [vLLM](https://github.com/vllm-project/vllm) on DGX Spark. The selected model variant is downloaded from Hugging Face and served locally with GPU acceleration (NVIDIA, ARM64/aarch64).

## Prerequisites

- Docker with the NVIDIA Container Toolkit configured
- NVIDIA GPU, tested with GB10 DGX Spark platform
- A Hugging Face account with access to the model
- Hugging Face CLI (`hf`) installed and authenticated (see below)

## Setup

1. Copy `.env.vllm.example` to `.env.vllm` and set your `HF_TOKEN` for downloading model weights.
2. Install the Hugging Face CLI (and, optionally, the pi agent):

   ```bash
   ./setup-cli.sh                 # interactive menu
   ./setup-cli.sh hf-install      # one-shot: install the `hf` CLI
   ./setup-cli.sh pi-install      # one-shot: install the pi agent CLI
   ```

   Authentication happens later via `./vllm-serve.sh download` (runs `hf auth login`).

3. Pick a model variant and start the server:

   ```bash
   ./vllm-serve.sh           # interactive menu
   ./vllm-serve.sh download  # one-shot: download model weights
   ./vllm-serve.sh start     # one-shot: pull image and start the container
   ```

## setup-cli.sh — CLI installation

Run without arguments for an interactive menu, or pass a subcommand directly:

```bash
./setup-cli.sh [hf-install|hf-reinstall|hf-with-transformers|hf-check|hf-uninstall|pi-install|pi-check|pi-update|pi-uninstall]
```

| Subcommand             | What it does                                                        |
| ---------------------- | ------------------------------------------------------------------- |
| `hf-install`           | Installs the Hugging Face CLI (reuses an existing venv if present). |
| `hf-reinstall`         | Recreates the Hugging Face CLI virtual environment (`--force`).     |
| `hf-with-transformers` | Installs the Hugging Face CLI with the `transformers` extra.        |
| `hf-check`             | Shows whether the `hf` CLI is installed and its version.            |
| `hf-uninstall`         | Removes the `hf` CLI and its virtual environment.                   |
| `pi-install`           | Installs the pi agent CLI.                                          |
| `pi-check`             | Shows whether the pi agent CLI is installed and its version.        |
| `pi-update`            | Updates the pi agent CLI to the latest version.                     |
| `pi-uninstall`         | Removes the pi agent CLI (keeps `~/.pi` config/credentials).        |

## vllm-serve.sh — day-to-day management

Run without arguments for an interactive menu, or pass a subcommand directly:

```bash
./vllm-serve.sh [select|download|start|logs|stop|pi|link|unlink]
```

| Subcommand | What it does                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `select`   | Interactive menu to pick the model variant (from `models.conf`); writes `MODEL_ID` to `.env.vllm`.                                                       |
| `download` | Downloads the model weights (`hf download`) into the local Hugging Face cache.                                                                           |
| `start`    | Pulls the latest `vllm-openai` Docker image and starts the vLLM service in the background.                                                               |
| `logs`     | Tails/follows the logs of the running vLLM container.                                                                                                    |
| `stop`     | Stops and removes the vLLM service and any orphaned containers.                                                                                          |
| `pi`       | Launches the pi agent against the local vLLM server (provider configured in `.pi/agent/models.json`), using `--model ${MODEL_ID}`.                      |
| `link`     | Symlinks this script as `vllm-serve` in `~/.local/bin`, so it can be run directly as `vllm-serve` from anywhere.                                         |
| `unlink`   | Removes that symlink from `~/.local/bin`.                                                                                                                |

### Profiles

Each `MODEL_ID` in `models.conf` has its own compose service/profile of the same name, prefixed `vllm-nv-` or `vllm-uns-` — e.g. `vllm-nv-qwen3.6-27B-NVFP4`, `vllm-uns-qwen3.6-35B-A3B-NVFP4`, `vllm-uns-qwen3.6-35B-A3B-NVFP4-fast`. `./vllm-serve.sh` maps `MODEL_ID` to the matching service/profile automatically; manual `docker compose` requires `--profile <service-name>`.

All services share `--dtype auto --quantization modelopt` plus `CUTE_DSL_ARCH=sm_121a` and `FLASHINFER_DISABLE_VERSION_CHECK=1` (set once in `docker-compose.yml`'s `x-defaults`).

- **35B-A3B** variants (nvidia, unsloth, and unsloth `-Fast`) share `--kv-cache-dtype fp8 --attention-backend flashinfer --tool-call-parser qwen3_xml`. nvidia and plain unsloth use `--moe-backend marlin` (flashinfer_b12x doesn't work on these weights); unsloth `-Fast` swaps in `--moe-backend flashinfer_b12x` — unsloth's [recommended DGX Spark config](https://huggingface.co/unsloth/Qwen3.6-27B-NVFP4#dgx-spark) — which only works on the `-Fast` weights.
- **27B** variants use `--moe-backend flashinfer_b12x --linear-backend flashinfer_b12x` — the same recommended DGX Spark config — plus `--tool-call-parser qwen3_coder` and `--default-chat-template-kwargs '{"enable_thinking": true}'`.
- Within each size, `nvidia/*` variants use `--speculative-config` with `moe_backend: triton` and more speculative tokens (plus `--async-scheduling` on 35B); `unsloth/*` variants (incl. `-Fast`) use fewer speculative tokens and no `moe_backend` key.

## Configuration

The service configuration lives in `docker-compose.yml`. The container listens on port `8000` and exposes an OpenAI-compatible API.

## Usage examples

### Verify the server is running

```bash
curl http://localhost:8000/v1/models
```

### Chat with the model (OpenAI-compatible API)

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.6-35B-A3B-NVFP4",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 64
  }'
```

### Use the local server as your LLM backend

```bash
# Option 1: pi agent
./vllm-serve.sh pi

# Option 2: Run pi directly (provider is configured in .pi/agent/models.json)
pi --model unsloth/Qwen3.6-35B-A3B-NVFP4
```

## Observability (Prometheus + Grafana)

`docker-compose.yml` includes `prometheus` and `grafana` services (no `profiles:`, so they always start alongside whichever vLLM variant profile you select) based on vLLM's [Prometheus/Grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana). Both use `network_mode: host` like the vLLM services, so no port mapping or `host.docker.internal` plumbing is needed.

- Prometheus scrapes `localhost:8000/metrics` (config: `monitoring/prometheus.yaml`) — reachable at `http://localhost:9090`.
- Grafana (`http://localhost:3000`, default login `admin`/`admin`) auto-provisions the Prometheus datasource plus three dashboards (all in the `vLLM` folder) from `monitoring/grafana/provisioning/` and `monitoring/grafana/dashboards/` — no manual datasource/import steps required:
  - `vllm.json` — the main dashboard from the [prometheus_grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana).
  - `performance_statistics.json` / `query_statistics.json` — latency/throughput and request/query statistics, from the [dashboards/grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/dashboards/grafana).

```bash
curl http://localhost:8000/metrics   # raw vLLM metrics
```

## Models

The list of models offered by `./vllm-serve.sh select` is defined in [`models.conf`](models.conf) — one `MODEL_ID` per line. To add a new variant, add a line there (and, if it uses a new prefix, a matching profile in `docker-compose.yml`).

| Variant                 | Hugging Face                                                                                    | Notes                                                                                                                                                                                                                                            |
| ----------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **nvidia** (35B)        | [nvidia/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4)             | `moe_backend: triton` for speculative decoding, `--async-scheduling`                                                                                                                                                                             |
| **unsloth** (35B)       | [unsloth/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-NVFP4)           | Slightly more conservative speculative config, no `--async-scheduling`                                                                                                                                                                           |
| **unsloth** (35B, Fast) | [unsloth/Qwen3.6-35B-A3B-NVFP4-Fast](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-NVFP4-Fast) | Same as unsloth 35B above, but `flashinfer_b12x` MoE backend ([unsloth's recommended DGX Spark config](https://huggingface.co/unsloth/Qwen3.6-27B-NVFP4#dgx-spark)) instead of `marlin` — only works on these `-Fast` weights, not plain 35B-A3B |
| **nvidia** (27B)        | [nvidia/Qwen3.6-27B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-27B-NVFP4)                     | `flashinfer_b12x` MoE/linear backend ([unsloth's recommended DGX Spark config](https://huggingface.co/unsloth/Qwen3.6-27B-NVFP4#dgx-spark)), `qwen3_coder` tool parser, `moe_backend: triton` for speculative decoding                           |
| **unsloth** (27B)       | [unsloth/Qwen3.6-27B-NVFP4](https://huggingface.co/unsloth/Qwen3.6-27B-NVFP4)                   | Same 27B profile/flags as above, more conservative speculative config                                                                                                                                                                            |

All five are listed in [`models.conf`](models.conf) and selectable via `./vllm-serve.sh select`. Each has its own compose service/profile (see [Profiles](#profiles) above) — no shared-container naming gotcha.

## License

MIT License, Copyright (c) 2026 M. R. Hartmann
