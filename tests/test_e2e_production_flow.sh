#!/bin/bash
# tests/test_e2e_production_flow.sh
# End-to-end: promoting a staging RC to production, and production hotfixes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

# Bring a fixture up to "1.0.0 has two staging RCs".
seed_staged_version() {
    gt_fixture_run staging release start 1.0.0  >/dev/null 2>&1
    gt_fixture_commit "feat: Prepare the release candidate"
    gt_fixture_run staging release finish 1.0.0 >/dev/null 2>&1
    git checkout -q develop
    gt_fixture_run staging hotfix start 1.0.0   >/dev/null 2>&1
    gt_fixture_commit "fix: Address QA feedback here"
    gt_fixture_run staging hotfix finish 1.0.0  >/dev/null 2>&1
    git checkout -q develop
}

start_suite "E2E: Production Release & Hotfix Lifecycle"

# ===========================================================================
# EP_01 — production release start promotes the LATEST RC
# ===========================================================================
start_test_case "ep_01_release_start_uses_latest_rc"
gt_fixture_new_repo production-flow || exit 1
seed_staged_version

gt_fixture_run production release start 1.0.0
assert_success "$GT_RUN_STATUS" "production release start exits 0"
assert_no_shell_errors "production release start produces no shell errors"
assert_equals "$(git branch --show-current)" "release/prod/1.0.0" \
    "Checked out release/prod/1.0.0"
assert_branch_contains "HEAD" "staging/1.0.0-rc-02" \
    "Release branch is based on the LATEST RC, not rc-01"

# ===========================================================================
# EP_02 — production release finish tags and syncs back down
# ===========================================================================
start_test_case "ep_02_release_finish_syncs_back"
gt_fixture_run production release finish 1.0.0
assert_success "$GT_RUN_STATUS" "production release finish exits 0"
assert_no_shell_errors "production release finish produces no shell errors"

assert_tag_exists "production/1.0.0" "Created production/1.0.0"
assert_branch_contains "production" "production/1.0.0" \
    "production branch contains the release tag"
assert_branch_contains "staging" "production" \
    "production was synced into staging"
assert_branch_contains "develop" "staging" \
    "staging was synced into develop"

git show-ref --verify --quiet "refs/heads/release/prod/1.0.0"
assert_failure "$?" "Production release branch deleted after finish"

# ===========================================================================
# EP_03 — the same version cannot be released to production twice
# ===========================================================================
start_test_case "ep_03_double_release_rejected"
gt_fixture_run production release start 1.0.0
assert_failure "$GT_RUN_STATUS" "Re-releasing an existing production version fails"
assert_contains "$(gt_run_output)" "already released" \
    "Explains the version is already released"

# ===========================================================================
# EP_04 — staging operations are blocked for a released version
# ===========================================================================
start_test_case "ep_04_staging_blocked_after_production"
git checkout -q develop
gt_fixture_run staging hotfix start 1.0.0
assert_failure "$GT_RUN_STATUS" "staging hotfix on a released version fails"
assert_contains "$(gt_run_output)" "RELEASED TO PRODUCTION" \
    "Explains the version is already in production"

# ===========================================================================
# EP_05 — production hotfix auto-increments the patch version
# ===========================================================================
start_test_case "ep_05_hotfix_auto_increments_patch"
git checkout -q production
gt_fixture_run production hotfix start
assert_success "$GT_RUN_STATUS" "production hotfix start exits 0"
assert_no_shell_errors "production hotfix start produces no shell errors"
assert_equals "$(git branch --show-current)" "hotfix/prod/1.0.1" \
    "Auto-incremented to hotfix/prod/1.0.1"
assert_branch_contains "HEAD" "production" \
    "Hotfix branch is based on production"

# ===========================================================================
# EP_06 — production hotfix finish tags and syncs to staging and develop
# ===========================================================================
start_test_case "ep_06_hotfix_finish_syncs_downstream"
gt_fixture_commit "fix: Repair the critical production issue"

gt_fixture_run production hotfix finish
assert_success "$GT_RUN_STATUS" "production hotfix finish exits 0"
assert_no_shell_errors "production hotfix finish produces no shell errors"

assert_tag_exists "production/1.0.1" "Created production/1.0.1"
assert_branch_contains "production" "production/1.0.1" \
    "production contains the hotfix tag"
assert_branch_contains "staging" "production" \
    "Hotfix reached staging"
assert_branch_contains "develop" "production" \
    "Hotfix reached develop"

# ===========================================================================
# EP_07 — final tag set and a healthy verify-sync
# ===========================================================================
start_test_case "ep_07_final_state"
assert_tags_equal "production/1.0.0 production/1.0.1 staging/1.0.0-rc-01 staging/1.0.0-rc-02" \
    "Final tag set is exactly as expected"

gt_fixture_run status
assert_success "$GT_RUN_STATUS" "status exits 0"
assert_no_shell_errors "status produces no shell errors"
assert_contains "$(gt_run_output)" "All branches synchronized correctly" \
    "status reports branches synchronized"

gt_fixture_destroy
print_summary
