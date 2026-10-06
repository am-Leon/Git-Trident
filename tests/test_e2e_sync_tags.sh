#!/bin/bash
# tests/test_e2e_sync_tags.sh
# End-to-end: propagation in both directions.
#
#   production -> newer staging RCs   (a release lands; in-flight versions must
#                                      pick it up or they are unpromotable)
#   staging    -> newer staging RCs   (a hotfix on an older in-flight version)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

# Create a staging release for <version> with one RC.
stage_version() {
    local v="$1"
    git checkout -q develop
    gt_fixture_run staging release start "$v"  >/dev/null 2>&1
    gt_fixture_commit "feat: Prepare release $v"
    gt_fixture_run staging release finish "$v" >/dev/null 2>&1
    git checkout -q develop
}

start_suite "E2E: Tag Synchronisation (sync-tags)"

# ===========================================================================
# ET_01 — --dry-run reports, and changes nothing
# ===========================================================================
start_test_case "et_01_dry_run_is_read_only"
gt_fixture_new_repo sync-tags || exit 1
stage_version 1.0.0
stage_version 2.0.0

before="$(git tag -l | sort -V | tr '\n' ' ')"
gt_fixture_run staging sync-tags 1.0.0 --dry-run
assert_no_shell_errors "sync-tags --dry-run produces no shell errors"
assert_contains "$(gt_run_output)" "Checking sync impact" \
    "Dry-run announces that it is only checking"
after="$(git tag -l | sort -V | tr '\n' ' ')"
assert_equals "$after" "$before" "Dry-run created no tags"

# ===========================================================================
# ET_02 — a staging hotfix on 1.0.0 must propagate to the newer 2.0.0
# ===========================================================================
start_test_case "et_02_staging_hotfix_propagates_forward"
git checkout -q develop
gt_fixture_run staging hotfix start 1.0.0  >/dev/null 2>&1
gt_fixture_commit "fix: Patch the shared defect"
gt_fixture_run staging hotfix finish 1.0.0 >/dev/null 2>&1
assert_tag_exists "staging/1.0.0-rc-02" "Hotfix produced staging/1.0.0-rc-02"

# 2.0.0's latest RC predates the hotfix, so it needs propagation.
git merge-base --is-ancestor "staging/1.0.0-rc-02" "staging/2.0.0-rc-01" 2>/dev/null
assert_failure "$?" "staging/2.0.0-rc-01 does not yet contain the hotfix"

git checkout -q develop
gt_fixture_run staging sync-tags 1.0.0
assert_no_shell_errors "sync-tags produces no shell errors"
assert_tag_exists "staging/2.0.0-rc-02" "Propagation created staging/2.0.0-rc-02"
git merge-base --is-ancestor "staging/1.0.0-rc-02" "staging/2.0.0-rc-02" 2>/dev/null
assert_success "$?" "staging/2.0.0-rc-02 now contains the hotfix"

# ===========================================================================
# ET_03 — re-running is a no-op once everything is in sync
# ===========================================================================
start_test_case "et_03_resync_is_idempotent"
before="$(git tag -l | sort -V | tr '\n' ' ')"
git checkout -q develop
gt_fixture_run staging sync-tags 1.0.0
after="$(git tag -l | sort -V | tr '\n' ' ')"
assert_equals "$after" "$before" "A second sync-tags run creates no further tags"

# ===========================================================================
# ET_04 — after a production release, newer staging RCs need the changes
# ===========================================================================
start_test_case "et_04_production_propagates_to_newer_staging"
git checkout -q develop
gt_fixture_run production release start 1.0.0  >/dev/null 2>&1
gt_fixture_run production release finish 1.0.0 >/dev/null 2>&1
assert_tag_exists "production/1.0.0" "Released production/1.0.0"

git checkout -q develop
gt_fixture_run staging sync-tags 1.0.0
assert_no_shell_errors "sync-tags from production produces no shell errors"
assert_tag_exists "staging/2.0.0-rc-03" \
    "Production changes propagated into a new 2.0.0 RC"
git merge-base --is-ancestor "production/1.0.0" "staging/2.0.0-rc-03" 2>/dev/null
assert_success "$?" "The new 2.0.0 RC contains the production release"

# ===========================================================================
# ET_05 — promoting a deprecated RC is refused
# ===========================================================================
# staging/2.0.0-rc-01 and -rc-02 are superseded. Promotion must use the latest.
start_test_case "et_05_deprecated_rc_not_promotable"
git checkout -q develop
gt_fixture_run verify-sync --deprecated
assert_no_shell_errors "verify-sync --deprecated produces no shell errors"
assert_contains "$(gt_run_output)" "Deprecated" \
    "Deprecated staging tags are reported once a version is released"

# ===========================================================================
# ET_06 — no temp branches survive a completed propagation
# ===========================================================================
start_test_case "et_06_no_temp_branches_left"
temps=$(git branch --format='%(refname:short)' | grep -cE '^temp-(rebase|propagate)-' || true)
assert_equals "${temps:-0}" "0" "No temp-rebase/temp-propagate branches remain"

gt_fixture_destroy
print_summary
