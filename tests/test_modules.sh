#!/usr/bin/env bash
# Module dependencies: each lib/*.sh guards itself with require_defined (from
# lib/require.sh), listing what it takes from the dispatcher and the other
# modules. These tests hold the guards to the code and the dispatcher's
# source order to the guards.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Print the module paths vllm-serve.sh sources after lib/require.sh, in order.
dispatcher_modules() {
  # shellcheck disable=SC2016  # matches the literal ${SCRIPT_DIR}
  sed -n 's|^source "${SCRIPT_DIR}/\(lib/[a-z_]*\.sh\)"$|\1|p' "${REPO_DIR}/vllm-serve.sh" \
    | grep -vx 'lib/require.sh'
}

# Print the names a module lists in its require_defined lines.
module_requires() {
  sed -n 's/^require_defined \(.*\) || return 1$/\1/p' "${REPO_DIR}/$1" | tr ' ' '\n' | sed '/^$/d'
}

# Print the functions and top-level variables a file defines.
file_defines() {
  sed -n -e 's/^\([a-z_][a-z0-9_]*\)() {.*/\1/p' -e 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$1"
}

# Code of a file without comment lines, trailing comments and guard lines.
file_code() {
  grep -v -e '^[[:space:]]*#' -e '^require_defined ' "$1" | sed 's/[[:space:]]#.*$//'
}

# Source lib/require.sh and then the given modules, in order, in a clean bash
# with errexit on. With --vars, set the dispatcher's variables first.
# Prints stderr; the exit status is the shell's.
source_in_clean_shell() {
  local vars="" script module
  if [[ "$1" == "--vars" ]]; then
    vars="SCRIPT_DIR='${SANDBOX}' ENV_FILE='${SANDBOX}/.env.vllm'"
    vars+=" MODELS_FILE='${SANDBOX}/models.json' TARGETS_FILE='${SANDBOX}/targets.json';"
    shift
  fi
  script="set -euo pipefail; ${vars} source '${REPO_DIR}/lib/require.sh'"
  for module in "$@"; do script+="; source '${REPO_DIR}/${module}'"; done
  { env -i PATH="${PATH}" bash --norc --noprofile -c "${script}" >/dev/null; } 2>&1
}

test_dispatcher_sources_require_first() {
  # shellcheck disable=SC2016  # matches the literal ${SCRIPT_DIR}
  [[ "$(grep -m1 '^source ' "${REPO_DIR}/vllm-serve.sh")" == 'source "${SCRIPT_DIR}/lib/require.sh"' ]] \
    || fail "vllm-serve.sh does not source lib/require.sh first"
}

test_dispatcher_sources_every_module() {
  local file listed
  listed="$(dispatcher_modules)"
  for file in "${REPO_DIR}"/lib/*.sh; do
    [[ "$(basename "${file}")" == require.sh ]] && continue
    grep -qx "lib/$(basename "${file}")" <<<"${listed}" || fail "${file} is not sourced by vllm-serve.sh"
  done
}

test_require_defined_accepts_functions_and_set_variables() {
  local err
  err="$(env -i PATH="${PATH}" bash --norc --noprofile -c "
    source '${REPO_DIR}/lib/require.sh'
    f() { :; }; V=1
    require_defined f V" 2>&1)" || fail "require_defined rejected a function or set variable: ${err}"
}

test_require_defined_names_module_and_missing() {
  local err status=0
  printf 'require_defined present nope_fn NOPE_VAR || return 1\necho after\n' >"${SANDBOX}/mod.sh"
  err="$(env -i PATH="${PATH}" bash --norc --noprofile -c "
    source '${REPO_DIR}/lib/require.sh'
    present() { :; }
    source '${SANDBOX}/mod.sh'" 2>&1)" || status=$?
  (( status != 0 )) || fail "sourcing with a missing name succeeded"
  [[ "${err}" == *mod.sh* ]] || fail "error does not name the module: ${err}"
  [[ "${err}" == *nope_fn* && "${err}" == *NOPE_VAR* ]] || fail "error does not list missing names: ${err}"
  [[ "${err}" != *present* && "${err}" != *after* ]] || fail "unexpected output: ${err}"
}

test_every_module_has_a_guard() {
  local module
  while IFS= read -r module; do
    grep -q '^require_defined .* || return 1$' "${REPO_DIR}/${module}" \
      || fail "${module} has no 'require_defined ... || return 1' line"
  done < <(dispatcher_modules)
}

# Each module with outside dependencies, sourced alone, fails and names one.
test_each_module_alone_fails() {
  local module err name named
  while IFS= read -r module; do
    [[ -n "$(module_requires "${module}")" ]] || continue
    if err="$(source_in_clean_shell "${module}")"; then
      fail "${module} sourced alone succeeded"
      continue
    fi
    named=0
    while IFS= read -r name; do
      [[ "${err}" == *"${name}"* ]] && named=1
    done < <(module_requires "${module}")
    (( named )) || fail "${module} alone failed without naming a dependency: ${err}"
  done < <(dispatcher_modules)
}

test_dispatcher_order_passes_every_guard() {
  local err modules=()
  mapfile -t modules < <(dispatcher_modules)
  err="$(source_in_clean_shell --vars "${modules[@]}")" \
    || fail "sourcing in the dispatcher's order failed: ${err}"
}

test_wrong_order_fails() {
  local modules=() reversed=() i err
  mapfile -t modules < <(dispatcher_modules)
  for (( i = ${#modules[@]} - 1; i >= 0; i-- )); do reversed+=("${modules[i]}"); done
  if err="$(source_in_clean_shell --vars "${reversed[@]}")"; then
    fail "sourcing in reverse order succeeded"
  fi
  [[ "${err}" == *missing* ]] || fail "reverse order failed without a guard message: ${err}"
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

# The scan ignores trailing comments: a name only in one is not a use.
test_scan_ignores_trailing_comments() {
  printf 'x=1  # see load_env\n' >"${SANDBOX}/c.sh"
  if grep -qw load_env <(file_code "${SANDBOX}/c.sh"); then
    fail "trailing comment counted as a use"
  fi
}

run_tests
