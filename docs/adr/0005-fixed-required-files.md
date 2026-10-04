# Required files: a fixed set, split by Model ID and Draft model

`is_downloaded` in `lib/download.sh` requires a fixed set of files in a repo's snapshot, each resolved to a blob:

- Every repo (Model ID and Draft model): `config.json` and at least one `*.safetensors`.
- Model ID repos only: `tokenizer.json` or `tokenizer_config.json`.

A file that was never fetched leaves no snapshot symlink and no partial blob, so the other checks can't see it. The fixed set catches the files vLLM can't start without. Every shard listed in a safetensors weight index, and the at-least-one `*.safetensors` file, must likewise be a snapshot symlink resolved to a blob of the repo. "Resolved to a blob" means the snapshot symlink's own target is an entry of the repo's `blobs/` that resolves to a regular file. That entry may itself be a symlink into a shared store outside the repo, as a pruned (deduplicated) HF cache leaves it, so only the first hop is checked against `blobs/`.

A Draft model uses its target model's tokenizer and ships none of its own: `z-lab/Qwen3.8-27B-DFlash2` and `Doopeworld/Qwen3.8-27B-DSpark-vLLM` have only `config.json` and `model.safetensors`. So `download_missing` passes `draft` to `is_downloaded` for the Draft model, which skips the tokenizer check. The registry was checked once, by hand, on 2026-10-01 against the Hugging Face Hub file list of each repo in `models.json`: every Model ID ships `config.json` and a tokenizer; every Draft model ships `config.json` and safetensors only. This check is not repeated by any script or test.

## Considered options

- Record a repo's file list at download time and check against it: more state to keep in step with the HF cache, and a Download made before it would have no list.
- Query the Hub for the file list: the check must work offline.

## Consequences

- A blob entry that is a symlink to any existing file outside the repo counts as cached. The check does not verify that the shared store belongs to the HF cache.
- Optional files (e.g. `generation_config.json`, a chat template) aren't checked. A Download missing one counts as complete.
- The HF cache keeps no offline list of a repo's files, so only the fixed set is detected.
- A registry entry whose repo lacks a required file always shows as an incomplete Download. Check new entries the same way, against their Hub file list, before adding them to `models.json`.
