# shellcheck shell=bash
# Require module: the source-time guard the other lib/*.sh modules call.
# Sourced by vllm-serve.sh before every other module.

# require_defined NAME...: succeed if every NAME is a defined function or a set
# variable. Otherwise print the sourcing module and the missing names to stderr
# and return 1. Modules call it as `require_defined ... || return 1`.
require_defined() {
  local name missing=()
  for name in "$@"; do
    declare -F "${name}" >/dev/null || [[ -v "${name}" ]] || missing+=("${name}")
  done
  (( ${#missing[@]} == 0 )) && return 0
  echo "Error: ${BASH_SOURCE[1]:-unknown module} is missing: ${missing[*]}" >&2
  return 1
}
