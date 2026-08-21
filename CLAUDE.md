# Hardware
- **Machine:** Lenovo ThinkStation PGX — NVIDIA GB10 Grace Blackwell Superchip
- **CUDA Compute Capability:** 12.1 (sm_121a — same chip as NVIDIA DGX Spark)

# vLLM: Qwen3.6-35B-A3B-NVFP4 variants

## nvidia/Qwen3.6-35B-A3B-NVFP4
- `--moe-backend marlin`
- `--load-format fastsafetensors`
- `--speculative-config '{"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton"}'`

> These flags apply to the **nvidia** compose profile (`MODEL_ID=nvidia/…`).
> The **unsloth** profile uses different flags (see below).

## unsloth/Qwen3.6-35B-A3B-NVFP4
- env: `CUTE_DSL_ARCH=sm_121a` (required — 2x perf penalty without it)
- `--moe-backend marlin` (flashinfer_b12x removed; flashinfer_cutlass incompatible with f8e4m3fn quant scheme; triton not valid for NvFP4; marlin is the working fallback)
- `--speculative-config '{"method":"mtp","num_speculative_tokens":2}'` (no moe_backend key)
- omit `--load-format fastsafetensors` (not documented; unsloth profile drops this flag)

# Project: vllm-nvidea-qwen3.6-compose

A Docker Compose setup that serves Qwen3.6-35B-A3B-NVFP4 as an
OpenAI-compatible API on `http://localhost:8000`.
Image: `vllm/vllm-openai:latest-aarch64`.

This directory is its own git repository, nested inside the parent
`2026_vllm/` project folder (which is not under git).

## Workflow

One-time setup (run once per machine — from this directory):
- `./setup-cli.sh` — install/manage the Hugging Face CLI and Claude Code CLI (`hf-install|hf-reinstall|hf-with-transformers|hf-check|hf-uninstall|claude-install|claude-check|claude-uninstall`, no args → interactive menu)

Day-to-day via `./vllm-serve.sh [select|download|start|logs|stop|claude]` (no args → interactive menu)

| Command | Description |
|---------|-------------|
| `./vllm-serve.sh` | Interactive menu |
| `./vllm-serve.sh select` | Pick model variant from `models.conf` |
| `./vllm-serve.sh download` | Login to HF and download model weights |
| `./vllm-serve.sh start` | Pull image and start vLLM container on :8000 |
| `./vllm-serve.sh logs` | Tail container logs |
| `./vllm-serve.sh stop` | Stop and remove the container |
| `./vllm-serve.sh claude` | Launch Claude Code pointed at local vLLM server |

## Config
- Copy `.env.vllm.example` → `.env.vllm`, set `HF_TOKEN` and `MODEL_ID`
- `models.conf` lists the model IDs offered by `./vllm-serve.sh select`; add a line to make a new variant selectable
- `MODEL_ID` prefix determines compose profile: `nvidia/*` → profile `nvidia`, `unsloth/*` → profile `unsloth`
- Profiles are selected automatically by `./vllm-serve.sh start`; manual `docker compose` requires `--profile nvidia` or `--profile unsloth`
- Served at `http://localhost:8000` as `qwen3.6-35B-A3B-NVFP4` (OpenAI-compatible)
- `--gpu-memory-utilization 0.4`, `--max-model-len 262144`, `--max-num-seqs 4`
- Tool use: `--tool-call-parser qwen3_xml --enable-auto-tool-choice`
- Reasoning: `--reasoning-parser qwen3`

## Claude Code Integration

Point Claude Code at the local vLLM server:

```bash
./vllm-serve.sh claude
```

Sets `ANTHROPIC_BASE_URL=http://localhost:8000` and `ANTHROPIC_API_KEY=vllm`,
allowing you to use the local model as the `--model` target.

## Verify Server

```bash
curl http://localhost:8000/v1/models
```

## Parent-Level Files (outside this repo, not under git)

- `../AGENTS.md` — Points to this file (auto-discovered by Claude)
- `../git-local-user-pyropix.sh` — Sets git identity to `pyropix` for this subproject

# Git
- Use semantic commit messages: `type(scope): description`
- Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`
- Example: `feat(vllm): add flashinfer backend for unsloth variant`
- Commit from this directory (has its own `.git`)
