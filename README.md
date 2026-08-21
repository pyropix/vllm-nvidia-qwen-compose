# vLLM NVidia Qwen3.x Compose

Runs Qwen3.x models as an OpenAI-compatible inference server using [vLLM](https://github.com/vllm-project/vllm) on DGX Spark. The selected model variant is downloaded from Hugging Face and served locally with GPU acceleration (NVIDIA, ARM64/aarch64).

## Prerequisites

- Docker with the NVIDIA Container Toolkit configured
- NVIDIA GPU, tested with GB10 DGX Spark platform
- A Hugging Face account with access to the model
- Hugging Face CLI (`hf`) installed and authenticated (see below)

## Setup

1. Copy `.env.vllm.example` to `.env.vllm` and set your `HF_TOKEN` for downloading model weights.
2. Install the Hugging Face CLI (one-shot; run without args for an interactive menu):

   ```bash
   ./setup-cli.sh hf-install
   ```

   Authentication happens later via `./vllm-serve.sh download` (runs `hf auth login`).
3. Pick a model variant and start the server (run `./vllm-serve.sh` without args for an interactive menu):

   ```bash
   ./vllm-serve.sh download  # download model weights
   ./vllm-serve.sh start     # pull image and start the container
   ```

## Configuration

The service configuration lives in `docker-compose.yml`. Each `MODEL_ID` in `models.conf` has its own compose service/profile prefixed `vllm-` (launch flags and per-model differences: [docs/profiles.md](docs/profiles.md)). The container listens on port `8000` and exposes an OpenAI-compatible API.

```bash
curl http://localhost:8000/v1/models
```

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/Qwen3.6-35B-A3B-NVFP4",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 64
  }'
```

`./vllm-serve.sh pi` launches the pi agent against the local server (or run `pi --model ${MODEL_ID}` directly).

## Models

The list of models offered by `./vllm-serve.sh select` is defined in [`models.conf`](models.conf) — one `MODEL_ID` per line. To add a new variant, add a line there (and, if it uses a new prefix, a matching profile in `docker-compose.yml`).

| Variant                      | Hugging Face                                                                          | Notes                                              |
| ---------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------- |
| **Qwen3.6** 35B-A3B (nvidia) | [nvidia/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4)   | triton speculative backend, `--async-scheduling`   |
| **Qwen3.6** 27B (nvidia)     | [nvidia/Qwen3.6-27B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-27B-NVFP4)           | `marlin` MoE backend, `qwen3_coder` tool parser    |
| **Qwen3.8** 27B (unsloth)    | [unsloth/Qwen3.8-27B-NVFP4](https://huggingface.co/unsloth/Qwen3.8-27B-NVFP4)         | DSpark speculative decoding, 1M-token YaRN context |

## Observability

`docker-compose.yml` starts `prometheus` and `grafana` alongside whichever vLLM profile is selected (based on vLLM's [Prometheus/Grafana example](https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana)):

- Prometheus: `http://localhost:9090` (scrapes `localhost:8000/metrics`).
- Grafana: `http://localhost:3000` (default login `admin`/`admin`), dashboards auto-provisioned from `monitoring/` — no manual setup.

## License

MIT License, Copyright (c) 2026 M. R. Hartmann
