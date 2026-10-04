# vLLM address: one value, checked, not generated

`VLLM_ADDR` in `lib/status.sh` is the reference value for the host:port vLLM listens on. The other files that need the address keep their own literal. These are the `--port` of every Service in `docker-compose.yml`, `BASE_URL` in the pi extension and `baseUrl` in `settings/.pi/agent/models.json`. A test asserts that each of them matches `VLLM_ADDR`. Nothing is generated from it, and the port can't be configured.

## Considered options

- Configure the port once, for example as `VLLM_PORT` in `.env.vllm`, and have compose, the shell and the pi extension read it. This makes the port configurable, which nobody needs. It also can't reach `settings/.pi/agent/models.json`, a static file users copy and edit.
- Generate the files from one value. That adds a build step for a handful of literals, and the generated files would still have to be checked in.

## Consequences

- To change the port, edit every literal. The test lists any that still disagree.
- No test checks the prose in docs and code comments, so it may say `8000` on its own.
- Tests refer to `VLLM_ADDR`, never to the literal.
