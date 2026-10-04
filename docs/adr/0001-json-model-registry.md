# JSON model registry with the Draft model declared per Model ID

The model registry is `models.json`, which replaces `models.conf`. `vllm-serve.sh` parses it with `jq`, a hard dependency. Each entry lists a Model ID, its optional Variants and its optional Draft model. Variants share their Model ID's Draft model.

`select` writes `MODEL_ID`, `MODEL_VARIANT` and `DRAFT_MODEL_ID` to `.env.vllm`. `DRAFT_MODEL_ID` is empty when there is no Draft model. Compose interpolates `${DRAFT_MODEL_ID}` into `--speculative-config`, so the registry is the only place that declares the pairing. `download` fetches the Draft model along with the Model ID.

## Considered options

- Keep `models.conf` with a `:variant` suffix and add more suffix fields. This does not scale to a second per-model attribute.
- Parse with Python instead of `jq`. Python is heavier for a shell-driven workflow.
- Leave the draft ID hardcoded in compose. The pairing would live in two places and could drift, and `download` could not know about it.

## Consequences

- JSON has no comments, so `docs/profiles.md` documents the registry's fields.
- The registry also carries each Model ID's `context` window. `select` writes it as `MAX_MODEL_LEN`, and compose interpolates it into `--max-model-len`. The pi extension reads it directly from `models.json`. When `MAX_MODEL_LEN` is stale, `start` and `download` fail with the same "run `select` again" message.
- If an old `.env.vllm` lacks `DRAFT_MODEL_ID` and the registry declares a Draft model, `start` and `download` fail early with a "run `select` again" message.
- ~~Service names are still derived by convention from the Model ID and Variant.~~ Superseded by [ADR-0002](0002-service-name-in-registry.md). The registry stores the Service name.
