# vLLM

Serves Qwen3.x models (see `models.conf`) via `docker-compose.yml` on NVIDIA GB10 (sm_121a).
OpenAI-compatible API: `http://localhost:8000`. Full docs: `README.md`.

## Workflow

- `./vllm-serve.sh` — select/download/start/stop vLLM (see README or `--help` for subcommands)
- `./setup-cli.sh` — install/manage the `hf` and pi CLIs

## Git

- Conventional commits: `type(scope): description` (feat, fix, chore, docs, refactor, test, perf)
- Do NOT add an author to commit messages
