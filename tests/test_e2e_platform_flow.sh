#!/bin/bash
# tests/test_e2e_platform_flow.sh
# End-to-end in multi-platform (KMP) mode: shared is common, android/ios are
# independent. This is the configuration the tool was built for, and the one
# where platform-filtered push-all used to fail with "Failed to push 1 tags:"
# when there was nothing to push.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

start_suite "E2E: Multi-Platform Lifecycle"

start_test_case "pf_01_platform_release"
gt_fixture_platform_repo platform-flow || exit 1

gt_fixture_run staging release start android-1.0.0
assert_success "$GT_RUN_STATUS" "staging release start android-1.0.0"
assert_no_shell_errors "platform release start produces no shell errors"
assert_equals "$(git branch --show-current)" "release/stg/android-1.0.0" \
    "Platform release branch name includes the platform"

gt_fixture_commit "[android] feat: Prepare the android release"
gt_fixture_run staging release finish android-1.0.0
assert_success "$GT_RUN_STATUS" "staging release finish android-1.0.0"
assert_tag_exists "staging/android-1.0.0-rc-01" "Created staging/android-1.0.0-rc-01"

start_test_case "pf_02_platform_version_format_enforced"
git checkout -q develop
gt_fixture_run staging release start 1.0.0
assert_failure "$GT_RUN_STATUS" "A bare version is rejected in platform mode"
assert_contains "$(gt_run_output)" "platform" "Error mentions the platform requirement"

start_test_case "pf_03_unknown_platform_rejected"
gt_fixture_run staging release start windows-1.0.0
assert_failure "$GT_RUN_STATUS" "An unconfigured platform is rejected"

start_test_case "pf_04_independent_platforms_are_isolated"
git checkout -q develop
gt_fixture_run staging release start ios-1.0.0   >/dev/null 2>&1
gt_fixture_commit "[ios] feat: Prepare the ios release"
gt_fixture_run staging release finish ios-1.0.0  >/dev/null 2>&1
assert_tag_exists "staging/ios-1.0.0-rc-01" "Created staging/ios-1.0.0-rc-01"

# An android hotfix must NOT propagate into ios: both are independent.
git checkout -q develop
gt_fixture_run staging hotfix start android-1.0.0  >/dev/null 2>&1
gt_fixture_commit "[android] fix: Patch an android only defect"
gt_fixture_run staging hotfix finish android-1.0.0 >/dev/null 2>&1
assert_tag_exists "staging/android-1.0.0-rc-02" "android hotfix produced rc-02"
assert_tag_absent  "staging/ios-1.0.0-rc-02" \
    "ios did NOT receive an android-only hotfix (independent platforms)"

start_test_case "pf_05_platform_filtered_push_with_no_tags"
# Regression for P0-4. The failure needed a SPECIFIC combination:
# branch commits to push, but ZERO unpushed tags. `echo "" | wc -l` returns 1,
# so the empty tag list was counted as one entry and the per-tag loop ran once
# with an empty value, producing:
#     [ERROR] ✗
#     [ERROR] Failed to push 1 tags:
#     EXIT CODE = 1
# With nothing at all to push, push-all exits early and never reaches that code,
# so a naive "run it twice" test does not exercise the bug.
git checkout -q develop
gt_fixture_run push-all -p android origin
assert_success "$GT_RUN_STATUS" "Initial platform-filtered push succeeds"

# Branch work only: a commit on develop, and no new tag.
gt_fixture_commit "[android] feat: Add work with no new tag"
unpushed_commits=$(git rev-list --count origin/develop..develop 2>/dev/null)
assert_equals "$unpushed_commits" "1" "Exactly one unpushed commit, and no new tags"

gt_fixture_run push-all -p android origin
assert_success "$GT_RUN_STATUS" \
    "Platform-filtered push with branch changes but zero tags exits 0"
assert_not_contains "$(gt_run_output)" "Failed to push" \
    "No phantom tag-push failure when the tag list is empty"
assert_not_contains "$(gt_run_output)" "Tags: 1 new tag(s)" \
    "An empty tag list is not counted as one tag"
assert_no_shell_errors "platform-filtered push-all produces no shell errors"

start_test_case "pf_06_verify_sync_platform_mode"
gt_fixture_run verify-sync
assert_no_shell_errors "verify-sync produces no shell errors in platform mode"
assert_contains "$(gt_run_output)" "Platform" "verify-sync reports platform information"

gt_fixture_destroy
print_summary
