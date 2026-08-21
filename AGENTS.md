# vLLM

`docker-compose.yml` serves Qwen3.x models from `models.conf` (currently `nvidia/Qwen3.6-27B-NVFP4`, `nvidia/Qwen3.6-35B-A3B-NVFP4`, `unsloth/Qwen3.8-27B-NVFP4`)
Endpoint: http://localhost:8000/v1/models

## Hardware Platform

- NVIDIA DGX Spark platform
- NVIDIA GB10 Grace Blackwell (sm_121a)
- **Tested on:** Lenovo ThinkStation PGX

## Workflow

- `./setup-cli.sh` — install/manage the Hugging Face CLI and pi agent CLI
- `./vllm-serve.sh [select|download|start|logs|stop|pi|link|unlink]` — select and download model, start and stop vLLM

## Observability

Grafana: `http://localhost:3000`
Prometheus: `http://localhost:9090`
Config: `./monitoring/prometheus.yaml`

## Git

- Use semantic commit messages: `type(scope): description`
- Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`
- Do NOT add any author in the commit message
