#!/bin/bash
# tests/test_e2e_staging_flow.sh
# End-to-end: staging release and staging hotfix, driven through bin/git-trident.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

start_suite "E2E: Staging Release & Hotfix Lifecycle"

# ===========================================================================
# ES_01 — release start creates the release branch from develop
# ===========================================================================
start_test_case "es_01_release_start"
gt_fixture_new_repo staging-flow || exit 1

gt_fixture_run staging release start 1.0.0
assert_success "$GT_RUN_STATUS" "staging release start exits 0"
assert_no_shell_errors "staging release start produces no shell errors"
assert_equals "$(git branch --show-current)" "release/stg/1.0.0" \
    "Checked out release/stg/1.0.0"
assert_branch_contains "release/stg/1.0.0" "develop" \
    "Release branch contains everything on develop"

# ===========================================================================
# ES_02 — release finish tags rc-01, merges to staging, syncs develop
# ===========================================================================
start_test_case "es_02_release_finish"
gt_fixture_commit "feat: Prepare the first release"

gt_fixture_run staging release finish 1.0.0
assert_success "$GT_RUN_STATUS" "staging release finish exits 0"
assert_no_shell_errors "staging release finish produces no shell errors"

assert_tag_exists "staging/1.0.0-rc-01" "Created staging/1.0.0-rc-01"
assert_tag_absent "staging/1.0.0-rc-02" "Did not create a second RC"
assert_branch_contains "staging" "staging/1.0.0-rc-01" \
    "staging branch contains the RC tag"
assert_branch_contains "develop" "staging" \
    "develop was synced from staging"

# The release branch should be cleaned up (DELETE_BRANCH_ON_FINISH=true).
git show-ref --verify --quiet "refs/heads/release/stg/1.0.0"
assert_failure "$?" "Release branch deleted after finish"

# ===========================================================================
# ES_03 — a NEW release cannot reuse an existing base version
# ===========================================================================
start_test_case "es_03_release_start_rejects_existing_version"
gt_fixture_run staging release start 1.0.0
assert_failure "$GT_RUN_STATUS" "Starting a release for an existing version fails"
assert_contains "$(gt_run_output)" "already has RC releases" \
    "Explains that the version already has RCs"

# ===========================================================================
# ES_04 — hotfix start branches from the latest RC
# ===========================================================================
start_test_case "es_04_hotfix_start"
git checkout -q develop
gt_fixture_run staging hotfix start 1.0.0
assert_success "$GT_RUN_STATUS" "staging hotfix start exits 0"
assert_no_shell_errors "staging hotfix start produces no shell errors"
assert_equals "$(git branch --show-current)" "hotfix/stg/1.0.0" \
    "Checked out hotfix/stg/1.0.0"
assert_branch_contains "HEAD" "staging/1.0.0-rc-01" \
    "Hotfix branch is based on the latest RC"

# ===========================================================================
# ES_05 — hotfix finish increments the RC number
# ===========================================================================
start_test_case "es_05_hotfix_finish_increments_rc"
gt_fixture_commit "fix: Correct the reported defect"

gt_fixture_run staging hotfix finish 1.0.0
assert_success "$GT_RUN_STATUS" "staging hotfix finish exits 0"
assert_no_shell_errors "staging hotfix finish produces no shell errors"

assert_tag_exists "staging/1.0.0-rc-02" "Created staging/1.0.0-rc-02"
assert_tags_equal "staging/1.0.0-rc-01 staging/1.0.0-rc-02" \
    "Exactly two RC tags exist, in order"
assert_branch_contains "staging/1.0.0-rc-02" "staging/1.0.0-rc-01" \
    "rc-02 contains rc-01 (merge chain intact)"
assert_branch_contains "staging" "staging/1.0.0-rc-02" \
    "staging branch contains rc-02"
assert_branch_contains "develop" "staging" \
    "develop synced after the hotfix"

# ===========================================================================
# ES_06 — a second hotfix continues the sequence (rc-03), not restart it
# ===========================================================================
start_test_case "es_06_second_hotfix_continues_sequence"
git checkout -q develop
gt_fixture_run staging hotfix start 1.0.0
gt_fixture_commit "fix: Correct a second defect"
gt_fixture_run staging hotfix finish 1.0.0
assert_success "$GT_RUN_STATUS" "Second staging hotfix finish exits 0"
assert_tag_exists "staging/1.0.0-rc-03" "Created staging/1.0.0-rc-03"
assert_tags_equal "staging/1.0.0-rc-01 staging/1.0.0-rc-02 staging/1.0.0-rc-03" \
    "RC sequence is contiguous"

# No lock residue after a completed run (A7 trap).
locks=$(ls "$(git rev-parse --absolute-git-dir)/git-trident-locks" 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$locks" "0" "No lock directories left behind"

# ===========================================================================
# ES_07 — verify-sync reports a healthy repository
# ===========================================================================
start_test_case "es_07_verify_sync_healthy"
gt_fixture_run verify-sync
assert_success "$GT_RUN_STATUS" "verify-sync exits 0 on a healthy repository"
assert_no_shell_errors "verify-sync produces no shell errors"
assert_contains "$(gt_run_output)" "ALL CRITICAL CHECKS PASSED" \
    "verify-sync reports all critical checks passed"

gt_fixture_destroy
print_summary
