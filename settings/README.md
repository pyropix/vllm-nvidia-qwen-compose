# Pi agent example configuration

This directory contains an example configuration for the [Pi](https://pi.dev/) coding agent ([source on GitHub](https://github.com/earendil-works/pi)). It is set up to use the local vLLM server from this repository.

It belongs in the **home directory of a user**. Copy the `.pi` folder to `~`, so the files end up at:

```text
~/.pi/agent/settings.json   # default provider and model
~/.pi/agent/models.json     # vllm-qwen provider and its models
```

## Install

```bash
cp -r settings/.pi ~/
```

If `~/.pi` already exists, merge the files by hand instead so you don't overwrite your own settings.

## Files

- `settings.json` sets the default provider (`vllm-qwen`) and default model.
- `models.json` defines the `vllm-qwen` provider (OpenAI-compatible API at `http://localhost:8000/v1`) and the Qwen models it serves.

Adjust `baseUrl` and the model list to match your setup. For example, use `http://host.docker.internal:8000/v1` when Pi runs inside a container.
