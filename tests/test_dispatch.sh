#!/usr/bin/env bash
# Dispatcher: vllm-serve.sh only sources the modules and routes commands.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Replace the modules in the sandbox with stubs that print the route taken, so
# the tests see only what the dispatcher does with its arguments.
stub_modules() {
  local module fn
  for module in "${SANDBOX}"/lib/*.sh; do : >"${module}"; done
  for fn in cmd_status cmd_select cmd_download cmd_start cmd_logs cmd_ready \
    cmd_stop cmd_reset_metrics cmd_pi cmd_link cmd_unlink usage menu; do
    printf '%s() { echo "route:%s $*"; }\n' "${fn}" "${fn}" >>"${SANDBOX}/lib/ui.sh"
  done
}

test_script_has_only_sourcing_and_dispatch() {
  local defs
  defs="$(grep -cE '^[A-Za-z_]+\(\) *\{' "${REPO_DIR}/vllm-serve.sh" || true)"
  [[ "${defs}" == 0 ]] || fail "vllm-serve.sh defines ${defs} functions"
}

# Each command routes to its function, passing the arguments it takes.
assert_route() {
  local expected="$1"
  shift
  stub_modules
  run_script "$@"
  assert_status 0
  [[ "${OUT}" == "route:${expected}" ]] || fail "'$*' routed to '${OUT}', expected 'route:${expected}'"
}

test_status_routes()        { assert_route "cmd_status " status; }
test_select_routes()        { assert_route "cmd_select " select; }
test_download_routes()      { assert_route "cmd_download " download; }
test_start_routes()         { assert_route "cmd_start " start; }
test_logs_routes()          { assert_route "cmd_logs " logs; }
test_ready_routes()         { assert_route "cmd_ready " ready; }
test_ready_wait_routes()    { assert_route "cmd_ready --wait" ready --wait; }
test_stop_routes()          { assert_route "cmd_stop " stop; }
test_stop_all_routes()      { assert_route "cmd_stop --all" stop --all; }
test_reset_metrics_routes() { assert_route "cmd_reset_metrics " reset-metrics; }
test_reset_metrics_yes_routes() { assert_route "cmd_reset_metrics --yes" reset-metrics --yes; }
test_pi_routes()            { assert_route "cmd_pi " pi; }
test_link_routes()          { assert_route "cmd_link " link; }
test_unlink_routes()        { assert_route "cmd_unlink " unlink; }
test_no_args_opens_menu()   { assert_route "menu " ; }
test_help_routes()          { assert_route "usage " --help; }
test_help_word_routes()     { assert_route "usage " help; }
test_short_help_routes()    { assert_route "usage " -h; }

test_unknown_command_fails_with_usage() {
  stub_modules
  run_script bogus
  assert_status 1
  assert_out_contains "Unknown command: bogus"
  assert_out_contains "route:usage"
}

# Without stubs, --help prints the real usage text listing every command.
test_help_lists_every_command() {
  run_script --help
  assert_status 0
  local cmd
  for cmd in status select download start logs ready stop reset-metrics pi link unlink; do
    assert_out_contains "  ${cmd} "
  done
}

run_tests
