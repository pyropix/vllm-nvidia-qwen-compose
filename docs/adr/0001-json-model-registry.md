# JSON model registry with the Draft model declared per Model ID

The model registry is `models.json` (replacing `models.conf`), parsed with `jq` as a hard dependency. Each entry lists a Model ID, its optional Variants and its optional Draft model; Variants share their Model ID's Draft model. `select` writes `MODEL_ID`, `MODEL_VARIANT` and `DRAFT_MODEL_ID` (empty when there is none) to `.env.vllm`, and compose interpolates `${DRAFT_MODEL_ID}` into `--speculative-config`, so the registry is the only place the pairing is declared. `download` fetches the Draft model alongside the Model ID.

## Considered options

- Keep `models.conf` with a `:variant` suffix and add more suffix fields: does not scale to a second per-model attribute.
- Parse with Python instead of `jq`: heavier for a shell-driven workflow.
- Leave the draft ID hardcoded in compose: the pairing would be declared twice and could drift, and `download` could not know about it.

## Consequences

- JSON has no comments, so the registry's fields are documented in `docs/profiles.md`.
- The registry also carries each Model ID's `context` window; `select` writes it as `MAX_MODEL_LEN` and compose interpolates it into `--max-model-len`, while the pi extension reads it directly from `models.json`. `start` and `download` fail with the same "run `select` again" message when `MAX_MODEL_LEN` is stale.
- An old `.env.vllm` without `DRAFT_MODEL_ID` makes `start` and `download` fail early with a "run `select` again" message when the registry declares a Draft model.
- ~~Service names are still derived by convention from the Model ID and Variant.~~ Superseded by [ADR-0002](0002-service-name-in-registry.md): the registry stores the Service name.
