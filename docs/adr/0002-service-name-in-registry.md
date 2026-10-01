# Service name stored in the Model registry

Supersedes the ADR-0001 consequence "Service names are still derived by convention from the Model ID and Variant".

Each entry in `models.json` declares its Service name as `service`, and each Variant is an object `{"name", "service"}` carrying its own Service name. `vllm-serve.sh` looks the name up in the registry for `start`, `stop` and `logs`, and `status` maps a running Service back to its Model ID and Variant by reverse lookup. The org-prefix derivation (`nvidia` to `nv`, `unsloth` to `us`) is gone; `vllm-serve.sh` knows nothing about Hugging Face orgs.

## Considered options

- Keep deriving names by convention: a new org needs a code change, `status` re-derives every name, and the convention lives outside the registry.
- Derive names but allow per-entry overrides: two ways to name a Service, and a reader cannot tell which applies.

## Consequences

- Adding a Model ID or Variant means adding its `service` to `models.json` and a matching service to `docker-compose.yml`. `start`, `stop` and `logs` fail when the registry has no `service` for the selection or compose lacks that service.
- A running `vllm-*` container whose name is in no registry entry is reported as "not in models.json".
- The registry is again the only place that pairs a Model ID with its Service name, Draft model and Context window.
