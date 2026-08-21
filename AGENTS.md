# vLLM

Serves Qwen3.x models (see `models.conf`) via `docker-compose.yml` on NVIDIA GB10 (sm_121a).
OpenAI-compatible API: `http://localhost:8000`. Quickstart: `README.md`; launch flags per model: `docker-compose.yml` (details: `docs/profiles.md`).

## Workflow

- `./vllm-serve.sh` — select/download/start/stop vLLM (run with no args for a menu, or see `--help`)
- `./setup-cli.sh` — install/manage the `hf` and pi CLIs

## Git

- Conventional commits: `type(scope): description` (feat, fix, chore, docs, refactor, test, perf)
- Do NOT add an author to commit messages
