# Context

## Glossary

**Model ID**: The Hugging Face repository identifier of the weights being served (e.g. `nvidia/Qwen3.8-27B-NVFP4`).

**Variant**: An alternative way of serving the same Model ID (e.g. `instanttensor`), listed under that Model ID in the Model registry. Each Variant has its own Service and shares its Model ID's Draft model.

**Service**: One docker-compose entry (and profile) that serves a Model ID, optionally for a Variant.

**Draft model**: A separate Hugging Face repository (e.g. `z-lab/Qwen3.8-27B-DFlash2`) whose weights are served only to accelerate another Model ID's Service through speculative decoding. A Draft model is never selected on its own and is not itself a Model ID that gets a Service. Not every Service has one (some rely on speculation built into the model).

**Model registry**: The single list of selectable Model IDs, with each one's Variants and optional Draft model. It is the only place the Model ID to Draft model pairing is configured; other files only describe it.
