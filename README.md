# vLLM NVidea Qwen3.6 Compose

Runs the Qwen3.6-35B-A3B-NVFP4 model as an OpenAI-compatible inference server using [vLLM](https://github.com/vllm-project/vllm) on DGX Spark. The model is downloaded from Hugging Face and served locally with GPU acceleration (NVIDIA, ARM64/aarch64).

## Prerequisites

- Docker with the NVIDIA Container Toolkit configured
- NVIDIA GPU, tested with GB10 DGX Spark platform
- A Hugging Face account with access to the model
- Hugging Face CLI (`hf`) installed and authenticated (see below)

## Setup

1. Copy `.env.vllm.example` to `.env.vllm` and set your `HF_TOKEN` for downloading model weights.
2. Install the Hugging Face CLI (and, optionally, Claude Code):

   ```bash
   ./setup-cli.sh              # interactive menu
   ./setup-cli.sh hf-install      # one-shot: install the `hf` CLI
   ./setup-cli.sh claude-install  # one-shot: install the Claude Code CLI
   ```

   Authentication happens later via `./vllm-serve.sh download` (runs `hf auth login`).

3. Pick a model variant and start the server:

   ```bash
   ./vllm-serve.sh      # interactive menu
   ./vllm-serve.sh download  # one-shot: download model weights
   ./vllm-serve.sh start     # one-shot: pull image and start the container
   ```

## setup-cli.sh — CLI installation

Run without arguments for an interactive menu, or pass a subcommand directly:

```bash
./setup-cli.sh [hf-install|hf-reinstall|hf-with-transformers|hf-check|hf-uninstall|claude-install|claude-check|claude-update|claude-uninstall]
```

| Subcommand             | What it does                                                        |
| ----------------------- | -------------------------------------------------------------------- |
| `hf-install`            | Installs the Hugging Face CLI (reuses an existing venv if present).  |
| `hf-reinstall`          | Recreates the Hugging Face CLI virtual environment (`--force`).      |
| `hf-with-transformers`  | Installs the Hugging Face CLI with the `transformers` extra.         |
| `hf-check`              | Shows whether the `hf` CLI is installed and its version.             |
| `hf-uninstall`          | Removes the `hf` CLI and its virtual environment.                    |
| `claude-install`        | Installs the Claude Code CLI.                                        |
| `claude-check`          | Shows whether the Claude Code CLI is installed and its version.      |
| `claude-update`         | Updates the Claude Code CLI to the latest version.                   |
| `claude-uninstall`      | Removes the Claude Code CLI (keeps `~/.claude` config/credentials).  |

## vllm-serve.sh — day-to-day management

Run without arguments for an interactive menu, or pass a subcommand directly:

```bash
./vllm-serve.sh [select|download|start|logs|stop|claude|link]
```

| Subcommand   | What it does                                                                                              |
| ------------ | --------------------------------------------------------------------------------------------------------- |
| `select`     | Interactive menu to pick the model variant (from `models.conf`); writes `MODEL_ID` to `.env.vllm`.        |
| `download`   | Downloads the model weights (`hf download`) into the local Hugging Face cache.                            |
| `start`      | Pulls the latest `vllm-openai` Docker image and starts the vLLM service in the background.                |
| `logs`       | Tails/follows the logs of the running vLLM container.                                                     |
| `stop`       | Stops and removes the vLLM service and any orphaned containers.                                           |
| `claude`     | Launches Claude Code with `ANTHROPIC_BASE_URL` pointed at the local vLLM server, using `--model ${MODEL_ID}`. |
| `link`       | Symlinks this script as `vllm-serve` in `~/.local/bin`, so it can be run directly as `vllm-serve` from anywhere. |

### Profiles

The `docker-compose.yml` defines two **profiles**, selected automatically based on the `MODEL_ID` prefix:

- `nvidia/*` → profile `nvidia` — uses `--load-format fastsafetensors` and `--speculative-config` with `moe_backend: triton`.
- `unsloth/*` → profile `unsloth` — requires `CUTE_DSL_ARCH=sm_121a`, uses fewer speculative tokens and no `moe_backend` key.

## Configuration

The service configuration lives in `docker-compose.yml`. The container listens on port `8000` and exposes an OpenAI-compatible API.

Key parameters (all containers):

| Parameter              | Value      | Meaning                                          |
| ---------------------- | ---------- | ------------------------------------------------ |
| `--gpu-memory-utilization` | `0.4`  | Fraction of GPU memory reserved for the model    |
| `--max-model-len`      | `262144`   | Maximum context length in tokens (256K)          |
| `--max-num-seqs`       | `4`        | Maximum concurrent sequences                     |
| `--max-num-batched-tokens` | `8192` | Maximum tokens per prefill batch                 |
| `--kv-cache-dtype`     | `fp8`      | KV cache quantization                              |
| `--attention-backend`  | `flashinfer` | Attention kernel backend                       |
| `--moe-backend`        | `marlin`   | MoE routing backend                              |
| `--reasoning-parser`   | `qwen3`    | Enable chain-of-thought reasoning output         |
| `--tool-call-parser`   | `qwen3_xml` | Structured tool-calling format                  |

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
# Option 1: Claude Code
./vllm-serve.sh claude

# Option 2: Set env vars manually
export ANTHROPIC_BASE_URL=http://localhost:8000
export ANTHROPIC_API_KEY=vllm
```

## Models

The list of models offered by `./vllm-serve.sh select` is defined in [`models.conf`](models.conf) — one `MODEL_ID` per line. To add a new variant, add a line there (and, if it uses a new prefix, a matching profile in `docker-compose.yml`).

| Variant | Hugging Face | Notes |
| ------- | ------------ | ----- |
| **nvidia** | [nvidia/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4) | `--load-format fastsafetensors`, `moe_backend: triton` for speculative decoding |
| **unsloth** | [unsloth/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-NVFP4) | Requires `CUTE_DSL_ARCH=sm_121a`; slightly more conservative speculative config |

## License

MIT License, Copyright (c) 2026 M. R. Hartmann
