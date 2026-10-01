#!/usr/bin/env bash
# Module dependencies: each lib/*.sh declares what it takes from the dispatcher
# and the other modules in a "# Requires:" header line. These tests hold the
# declarations to the code, so a new module only needs its own header.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Print the module paths vllm-serve.sh sources, in its order.
dispatcher_modules() {
  # shellcheck disable=SC2016  # matches the literal ${SCRIPT_DIR}
  sed -n 's|^source "${SCRIPT_DIR}/\(lib/[a-z_]*\.sh\)"$|\1|p' "${REPO_DIR}/vllm-serve.sh"
}

# Print the names a module declares in its "# Requires:" line.
module_requires() {
  sed -n 's/^# Requires:\(.*\)$/\1/p' "${REPO_DIR}/$1" | tr ' ' '\n' | sed '/^$/d'
}

# Print the functions and top-level variables a file defines.
file_defines() {
  sed -n -e 's/^\([a-z_][a-z0-9_]*\)() {.*/\1/p' -e 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$1"
}

# Code of a file without comment lines.
file_code() {
  grep -v '^[[:space:]]*#' "$1"
}

test_dispatcher_sources_every_module() {
  local file listed
  listed="$(dispatcher_modules)"
  for file in "${REPO_DIR}"/lib/*.sh; do
    grep -qx "lib/$(basename "${file}")" <<<"${listed}" || fail "${file} is not sourced by vllm-serve.sh"
  done
}

test_every_module_has_a_requires_line() {
  local module
  while IFS= read -r module; do
    grep -q '^# Requires:' "${REPO_DIR}/${module}" || fail "${module} has no '# Requires:' line"
  done < <(dispatcher_modules)
}

# Every declared name exists once the dispatcher's variables are set and all
# modules are sourced in its order.
test_requires_are_defined() {
  (
    # shellcheck disable=SC2034  # read by the sourced modules
    SCRIPT_DIR="${SANDBOX}" ENV_FILE="${SANDBOX}/.env.vllm" MODELS_FILE="${SANDBOX}/models.json"
    # shellcheck disable=SC2034
    TARGETS_FILE="${SANDBOX}/targets.json"
    local module name
    while IFS= read -r module; do
      # shellcheck source=/dev/null
      source "${REPO_DIR}/${module}"
    done < <(dispatcher_modules)
    while IFS= read -r module; do
      while IFS= read -r name; do
        declare -F "${name}" >/dev/null || [[ -v "${name}" ]] \
          || fail "${module} requires '${name}', which nothing defines"
      done < <(module_requires "${module}")
    done < <(dispatcher_modules)
  )
}

# A module that uses a function or variable defined by the dispatcher or
# another module declares it.
test_requires_cover_what_modules_use() {
  local module other name declared own
  while IFS= read -r module; do
    declared="$(module_requires "${module}")"
    own="$(file_defines "${REPO_DIR}/${module}")"
    while IFS= read -r name; do
      grep -qx "${name}" <<<"${own}" && continue
      grep -qw -- "${name}" <(file_code "${REPO_DIR}/${module}") || continue
      grep -qx "${name}" <<<"${declared}" || fail "${module} uses '${name}' but does not require it"
    done < <(
      file_defines "${REPO_DIR}/vllm-serve.sh"
      while IFS= read -r other; do
        [[ "${other}" == "${module}" ]] || file_defines "${REPO_DIR}/${other}"
      done < <(dispatcher_modules)
    )
  done < <(dispatcher_modules)
}

run_tests
