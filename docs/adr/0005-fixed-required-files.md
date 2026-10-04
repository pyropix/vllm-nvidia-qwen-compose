# Required files: a fixed set, split by Model ID and Draft model

`is_downloaded` in `lib/download.sh` requires a fixed set of files in a repo's snapshot, each resolved to a blob:

- Every repo (Model ID and Draft model) needs `config.json` and at least one `*.safetensors`.
- Model ID repos also need `tokenizer.json` or `tokenizer_config.json`.

A file that was never fetched leaves no snapshot symlink and no partial blob, so the other checks can't see it. The fixed set catches the files vLLM can't start without. Every shard listed in a safetensors weight index must also be a snapshot symlink resolved to a blob of the repo, and so must the at-least-one `*.safetensors` file.

"Resolved to a blob" means the snapshot symlink's own target is an entry of the repo's `blobs/` that resolves to a regular file. A pruned (deduplicated) HF cache can leave that entry as a symlink into a shared store outside the repo. So the check compares only the first hop against `blobs/`.

A Draft model uses its target model's tokenizer and ships none of its own. `z-lab/Qwen3.8-27B-DFlash2` and `Doopeworld/Qwen3.8-27B-DSpark-vLLM` have only `config.json` and `model.safetensors`. So `download_missing` passes `draft` to `is_downloaded` for the Draft model, which skips the tokenizer check.

On 2026-10-01 we checked the registry once, by hand, against the Hugging Face Hub file list of each repo in `models.json`. Every Model ID ships `config.json` and a tokenizer. Every Draft model ships only `config.json` and safetensors. No script or test repeats this check.

## Considered options

- Record a repo's file list at download time and check against it. That is more state to keep in step with the HF cache, and a Download made before the change would have no list.
- Query the Hub for the file list. The check must work offline.

## Consequences

- A blob entry that is a symlink to any existing file outside the repo counts as cached. The check does not verify that the shared store belongs to the HF cache.
- The check skips optional files such as `generation_config.json` or a chat template. A Download missing one counts as complete.
- The HF cache keeps no offline list of a repo's files, so the check detects only missing files from the fixed set.
- A registry entry whose repo lacks a required file always shows as an incomplete Download. Before adding a new entry to `models.json`, check it the same way against its Hub file list.
