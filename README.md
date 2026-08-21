# vLLM NVidea Qwen3.6 Compose

Runs the Qwen3.6-35B-A3B model as an OpenAI-compatible inference server using [vLLM](https://github.com/vllm-project/vllm) on DGX Spark. The model is downloaded from Hugging Face and served locally with GPU acceleration (NVIDIA, ARM64/aarch64).

## Prerequisites

- Docker with the NVIDIA Container Toolkit configured
- NVIDIA GPU, tested with GB10 DGX Spark platform
- A Hugging Face account with access to the model

## Setup

1. Copy `.env.vllm.example` to `.env.vllm` and set your `HF_TOKEN` used for downloding the model weights.
2. Run the scripts below in order to install the Hugging Face CLI, authenticate, download the model, and start the server.

## Shell scripts

| Script | What it does |
| --- | --- |
| `00_hf_install.sh` | Installs the Hugging Face CLI (`hf`) by running the official install script. |
| `01_hf_login.sh` | Authenticates the Hugging Face CLI (`hf auth login`), prompting for a token if not already logged in. |
| `02_hf_download_llm.sh` | Downloads the model weights (`hf download`) into the local Hugging Face cache. |
| `03_vllm_start.sh` | Pulls the latest `vllm-openai` Docker image and starts the vLLM service in the background |
| `04_vllm_logs.sh` | Tails/follows the logs of the running vLLM container. |
| `05_vllm_stop.sh` | Stops and removes the vLLM service and any orphaned containers. |

## Configuration

The service configuration (model, port, GPU memory utilization, context length, etc.) lives in `docker-compose.yml`. The container listens on port `8000` and exposes an OpenAI-compatible API for the model, served under the name `qwen3.6-35B-A3B-NVFP4`.

## Models

- [nvidia/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4)

## Resources

- [vLLM Documentation](https://docs.vllm.ai/en/latest/)

- [DGX Spark User Guide](https://docs.nvidia.com/dgx/dgx-spark/)

- [Agent Ready Qwen3.6 35B server](https://build.nvidia.com/spark/vllm/agent-ready-qwen35b)

## License

MIT License, Copyright (c) 2026 M. R. Hartmann
