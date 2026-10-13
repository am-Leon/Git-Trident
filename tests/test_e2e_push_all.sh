#!/bin/bash
# tests/test_e2e_push_all.sh
# End-to-end: push-all against a real bare remote.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

remote_tags() {
    git ls-remote --tags origin 2>/dev/null | sed 's|.*refs/tags/||' | grep -v '\^{}' | sort -V | tr '\n' ' '
}

start_suite "E2E: push-all"

start_test_case "pa_01_nothing_to_push"
gt_fixture_new_repo push-all || exit 1
gt_fixture_run push-all origin
assert_success "$GT_RUN_STATUS" "push-all on a freshly synced repo exits 0"
assert_no_shell_errors "push-all produces no shell errors"
assert_contains "$(gt_run_output)" "up to date" "Reports everything up to date"
assert_not_contains "$(gt_run_output)" "Failed to push" "No phantom failure"

start_test_case "pa_02_pushes_branches_and_tags"
gt_fixture_run staging release start 1.0.0  >/dev/null 2>&1
gt_fixture_commit "feat: Prepare the first release"
gt_fixture_run staging release finish 1.0.0 >/dev/null 2>&1

gt_fixture_run push-all origin
assert_success "$GT_RUN_STATUS" "push-all with pending work exits 0"
assert_no_shell_errors "push-all produces no shell errors"
assert_contains "$(remote_tags)" "staging/1.0.0-rc-01" "RC tag reached the remote"

local_head=$(git rev-parse staging)
remote_head=$(git ls-remote origin refs/heads/staging | cut -f1)
assert_equals "$remote_head" "$local_head" "Remote staging matches local staging"

start_test_case "pa_03_idempotent"
gt_fixture_run push-all origin
assert_success "$GT_RUN_STATUS" "Re-running push-all exits 0"
assert_contains "$(gt_run_output)" "up to date" "Second run reports up to date"
assert_not_contains "$(gt_run_output)" "Failed to push" "No phantom failure on re-run"

start_test_case "pa_04_unreachable_remote_fails_clearly"
git remote set-url origin "$GT_FIXTURE_ROOT/does-not-exist.git"
gt_fixture_run push-all origin
assert_failure "$GT_RUN_STATUS" "Unreachable remote makes push-all fail"
assert_contains "$(gt_run_output)" "repository" "git's real error is surfaced, not swallowed"
git remote set-url origin "$GT_FIXTURE_REMOTE"

start_test_case "pa_05_tag_count_is_accurate"
# `echo "" | wc -l` is 1, which used to report a phantom tag and inflate totals.
gt_fixture_run push-all origin
assert_not_contains "$(gt_run_output)" "Tags: 1 new tag(s)" \
    "Zero unpushed tags are not counted as one"

gt_fixture_destroy
print_summary
