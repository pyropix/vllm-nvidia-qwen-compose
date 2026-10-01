# Required files: a fixed set, split by Model ID and Draft model

`is_downloaded` in `lib/download.sh` requires a fixed set of files in a repo's snapshot, each resolved to a blob:

- Every repo (Model ID and Draft model): `config.json` and at least one `*.safetensors`.
- Model ID repos only: `tokenizer.json` or `tokenizer_config.json`.

A file that was never fetched leaves no snapshot symlink and no partial blob, so the other checks can't see it. The fixed set catches the files vLLM can't start without.

A Draft model uses its target model's tokenizer and ships none of its own: `z-lab/Qwen3.8-27B-DFlash2` and `Doopeworld/Qwen3.8-27B-DSpark-vLLM` have only `config.json` and `model.safetensors`. So `download_missing` passes `draft` to `is_downloaded` for the Draft model, which skips the tokenizer check. Every Model ID and Draft model in `models.json` was checked to ship its required files.

## Considered options

- Record a repo's file list at download time and check against it: more state to keep in step with the HF cache, and a Download made before it would have no list.
- Query the Hub for the file list: the check must work offline.

## Consequences

- Optional files (e.g. `generation_config.json`, a chat template) aren't checked. A Download missing one counts as complete.
- The HF cache keeps no offline list of a repo's files, so only the fixed set is detected.
- A Model ID or Draft model added to `models.json` that doesn't ship the required files always counts as incomplete. Check new entries before adding them.
