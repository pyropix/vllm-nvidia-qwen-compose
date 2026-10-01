#!/usr/bin/env bash
# The test harness itself: what makes a test fail.
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Run a throwaway test file made of the test bodies on stdin; sets OUT and STATUS.
run_inner_tests() {
    local inner="${SANDBOX}/inner_tests.sh"
    {
        echo 'set -euo pipefail'
        echo "source '${REPO_DIR}/tests/lib.sh'"
        cat
        echo 'run_tests'
    } >"${inner}"
    set +e
    OUT="$(bash "${inner}" 2>&1)"
    STATUS=$?
    set -e
}

test_failing_bare_command_fails_the_test() {
    run_inner_tests <<'INNER'
test_bare() {
    false
    true
}
INNER
    assert_status 1
    assert_out_contains "not ok - test_bare"
}

test_failing_bare_command_stops_the_test() {
    export RAN_AFTER_FAILURE="${SANDBOX}/ran-after-failure"
    run_inner_tests <<'INNER'
test_stops() {
    false
    touch "${RAN_AFTER_FAILURE}"
}
INNER
    assert_status 1
    assert_out_contains "not ok - test_stops"
    [[ ! -e "${RAN_AFTER_FAILURE}" ]] || fail "test kept running after a failing bare command"
}

test_assert_failure_still_fails_the_test() {
    run_inner_tests <<'INNER'
test_assert() {
    serve status
    assert_status 99
}
INNER
    assert_status 1
    assert_out_contains "not ok - test_assert"
}

test_passing_test_is_ok() {
    run_inner_tests <<'INNER'
test_fine() {
    true
    serve status
    assert_status 0
}
INNER
    assert_status 0
    assert_out_contains "ok - test_fine"
}

run_tests
