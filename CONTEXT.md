# Context

## Glossary

**Model ID**: The Hugging Face repository identifier of the weights being served (e.g. `nvidia/Qwen3.8-27B-NVFP4`).

**Variant**: An alternative way of serving the same Model ID, written as a `:variant` suffix on the Model ID (e.g. `:instanttensor`). Each variant has its own service.

**Service**: One docker-compose entry (and profile) that serves a Model ID, optionally for a variant.
