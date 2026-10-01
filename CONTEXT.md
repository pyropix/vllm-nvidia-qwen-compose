# Context

## Glossary

**Model ID**: The Hugging Face repository identifier of the weights being served (e.g. `nvidia/Qwen3.8-27B-NVFP4`).

**Variant**: An alternative way of serving the same Model ID (e.g. `instanttensor`), listed under that Model ID in the Model registry. Each Variant has its own Service and shares its Model ID's Draft model.

**Service**: One docker-compose entry (and profile) that serves a Model ID, optionally for a Variant.

**Draft model**: A separate Hugging Face repository (e.g. `z-lab/Qwen3.8-27B-DFlash2`) whose weights are served only to accelerate other Model IDs' Services through speculative decoding. A Draft model is never selected on its own and is not itself a Model ID that gets a Service. Several Model IDs may share the same Draft model. Not every Service has one (some rely on speculation built into the model).

**Download**: Fetching everything a Model ID needs to be served: its weights plus its Draft model, if it has one. The Draft model is mandatory, not optional. A Download belongs to a Model ID, not a Variant; all Variants of a Model ID share one Download. A Download is complete only when both the Model ID's weights and its Draft model are present; a Service must not start from an incomplete Download. A Draft model shared by several Model IDs is fetched once and serves all of them.

**Model registry**: The single list of selectable Model IDs, with each one's Variants and optional Draft model. It is the only place the Model ID to Draft model pairing is configured; other files only describe it.
