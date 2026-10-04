# vLLM NVidia Qwen3.x Compose

Runs Qwen3.x models as an OpenAI-compatible inference server with [vLLM](https://github.com/vllm-project/vllm) on DGX Spark (NVIDIA GPU, ARM64/aarch64). `./vllm-serve.sh` downloads the selected model variant from Hugging Face and serves it on the local GPU.

## Prerequisites

- Docker with the NVIDIA Container Toolkit configured
- An NVIDIA GPU. The project is tested on the GB10 DGX Spark platform.
- A Hugging Face account with access to the model
- The Hugging Face CLI (`hf`), installed and authenticated (see below)

## Setup

1. Copy `.env.vllm.example` to `.env.vllm` and set your `HF_TOKEN` so the script can download model weights.
2. Install the Hugging Face CLI. Run `./setup-cli.sh` without arguments for an interactive menu.

   ```bash
   ./setup-cli.sh hf-install
   ```

   You log in later, when `./vllm-serve.sh download` runs `hf auth login`.
3. Pick a model variant and start the server. Run `./vllm-serve.sh` without arguments for an interactive menu.

   ```bash
   ./vllm-serve.sh download  # download model weights
   ./vllm-serve.sh start     # pull image and start the container
   ```

## Configuration

`docker-compose.yml` holds the service configuration. Each `MODEL_ID` in `models.json` has its own compose service and profile, prefixed `vllm-`. [docs/profiles.md](docs/profiles.md) lists the launch flags and per-model differences. The container listens on port `8000` and serves an OpenAI-compatible API.

```bash
curl http://localhost:8000/v1/models
```

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/Qwen3.8-27B-NVFP4",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 64
  }'
```

`./vllm-serve.sh pi` starts the pi agent against the local server. You can also run `pi --model ${MODEL_ID}` directly.

## Models

[`models.json`](models.json) defines the models that `./vllm-serve.sh select` offers, one entry per `id`. Each entry has:

- `service`, the compose service name.
- `context`, the context window in tokens.
- Optional `variants`, a list of `{"name", "service"}` objects. Each variant is a separate service for the same model.
- An optional `draft` model for speculative decoding.

`select` writes `MODEL_ID`, `MODEL_VARIANT`, `DRAFT_MODEL_ID` and `MAX_MODEL_LEN` to `.env.vllm`. Compose passes `MAX_MODEL_LEN` as `--max-model-len`, and the pi extension reads `context` for its `contextWindow`. `download` also fetches the draft model. The script needs `jq` to read `models.json`.

To add a model or variant, add an entry with its `service` and `context` to `models.json`, and add a matching service and profile to `docker-compose.yml`.

| Variant                      | Hugging Face                                                                          | Notes                                              |
| ---------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------- |
| **Qwen3.6** 35B-A3B (nvidia) | [nvidia/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4)   | triton speculative backend, `--async-scheduling`   |
| **Qwen3.6** 27B (nvidia)     | [nvidia/Qwen3.6-27B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-27B-NVFP4)           | `marlin` MoE backend, `qwen3_coder` tool parser    |
| **Qwen3.8** 27B (nvidia)     | [nvidia/Qwen3.8-27B-NVFP4](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4)           | DFlash2 speculative decoding                       |
| **Qwen3.8** 27B (nvidia, `:instanttensor`) | [nvidia/Qwen3.8-27B-NVFP4](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4) | same as above on `eugr/spark-vllm`, `instanttensor` loader |
| **Qwen3.8** 27B (unsloth)    | [unsloth/Qwen3.8-27B-NVFP4](https://huggingface.co/unsloth/Qwen3.8-27B-NVFP4)         | DSpark speculative decoding, YaRN context extension    |

## Observability

`docker-compose.yml` starts `prometheus` and `grafana` with every vLLM profile. The setup follows vLLM's [Prometheus/Grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana).

- Prometheus runs at `http://localhost:9090` and scrapes `localhost:8000/metrics`.
- Grafana runs at `http://localhost:3000` with the default login `admin`/`admin`. It loads its dashboards from `monitoring/`, so you don't need to set anything up.

The Docker volumes `vllm-prometheus-data` and `vllm-grafana-data` hold the metrics history. Prometheus keeps 15 days, up to 2 GB. The history survives `./vllm-serve.sh stop`, model switches and restarts. `stop` leaves Prometheus and Grafana running, so you can still browse a finished Run. `stop --all` stops them too.

Every `start` begins a new Run. Its `run` label holds the start time, Model ID and Variant. The dashboards have a Run selector, so you can overlay Runs to compare them. `./vllm-serve.sh reset-metrics` deletes all history.

## License

MIT License, Copyright (c) 2026 M. R. Hartmann
