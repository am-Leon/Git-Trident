#!/bin/bash
# tests/test_e2e_dry_run.sh
# --dry-run must change NOTHING.
#
# A dry run that quietly performs some mutations is worse than having none at
# all, because it is trusted. Every assertion here compares a fingerprint of the
# ENTIRE repository — all refs and their shas, working-tree status, and the
# remote's refs — taken before and after the command.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

fingerprint() {
    { git for-each-ref --format='%(refname) %(objectname)' 2>/dev/null
      git status --porcelain 2>/dev/null
      git ls-remote origin 2>/dev/null
    } | sort | shasum | awk '{print $1}'
}

assert_unchanged_by_dry_run() {
    local before after
    before="$(fingerprint)"
    "$GT_BIN/git-trident" --dry-run "$@" >/dev/null 2>&1 </dev/null
    after="$(fingerprint)"
    assert_equals "$after" "$before" "--dry-run $* changes nothing"
}

start_suite "E2E: --dry-run Changes Nothing"

start_test_case "dr_00_setup"
gt_fixture_new_repo dry-run || exit 1
gt_fixture_run staging release start 1.0.0 >/dev/null 2>&1
gt_fixture_commit "feat: Prepare the first release"
gt_fixture_run staging release finish 1.0.0 >/dev/null 2>&1
git checkout -q develop
gt_fixture_run push-all origin >/dev/null 2>&1
assert_tag_exists "staging/1.0.0-rc-01" "Fixture has real state to operate on"

start_test_case "dr_01_staging_flows"
assert_unchanged_by_dry_run staging release start 2.0.0
assert_unchanged_by_dry_run staging release finish 1.0.0
assert_unchanged_by_dry_run staging hotfix start 1.0.0
assert_unchanged_by_dry_run staging hotfix finish 1.0.0

start_test_case "dr_02_production_flows"
assert_unchanged_by_dry_run production release start 1.0.0
assert_unchanged_by_dry_run production release finish 1.0.0
assert_unchanged_by_dry_run production hotfix start
assert_unchanged_by_dry_run production hotfix finish

start_test_case "dr_03_utility_commands"
assert_unchanged_by_dry_run push-all origin
assert_unchanged_by_dry_run cleanup prune tags
assert_unchanged_by_dry_run cleanup prune temp
assert_unchanged_by_dry_run cleanup sync branches
assert_unchanged_by_dry_run staging sync-tags 1.0.0

# ---------------------------------------------------------------------------
# A dry run must also EXPLAIN itself, otherwise it is just a no-op.
# ---------------------------------------------------------------------------
start_test_case "dr_04_reports_what_it_would_do"
out="$("$GT_BIN/git-trident" --dry-run staging release finish 1.0.0 2>&1 </dev/null)"
assert_contains "$out" "would create tag staging/1.0.0-rc-01" "Names the tag it would create"
assert_contains "$out" "would merge release/stg/1.0.0 into staging" "Names the merge into staging"
assert_contains "$out" "would merge staging into develop" "Names the sync to develop"
assert_contains "$out" "DRY RUN — nothing was changed" "States plainly that nothing changed"

start_test_case "dr_05_push_all_lists_refs"
gt_fixture_commit "feat: Add an unpushed change"
out="$("$GT_BIN/git-trident" --dry-run push-all origin 2>&1 </dev/null)"
assert_contains "$out" "would push branch" "Names the branch it would push"
assert_contains "$out" "nothing was changed" "States plainly that nothing changed"

# ---------------------------------------------------------------------------
# Without --dry-run the same command must still work.
# ---------------------------------------------------------------------------
start_test_case "dr_06_real_run_still_works"
gt_fixture_run staging hotfix start 1.0.0
assert_success "$GT_RUN_STATUS" "hotfix start works without --dry-run"
gt_fixture_commit "fix: Apply the actual hotfix"
gt_fixture_run staging hotfix finish 1.0.0
assert_success "$GT_RUN_STATUS" "hotfix finish works without --dry-run"
assert_tag_exists "staging/1.0.0-rc-02" "Real run created the tag"

# ---------------------------------------------------------------------------
# The dispatcher CONSUMES --dry-run, so any command with its own --dry-run flag
# never sees it. Each must honour GT_DRY_RUN instead.
#
# This is not hypothetical: adding the global flag silently broke
# `git trident abort --dry-run`, which went from reporting what it would remove
# to actually removing it.
# ---------------------------------------------------------------------------
start_test_case "dr_07_commands_with_their_own_dry_run_flag"

gt_fixture_destroy
gt_fixture_new_repo dry-run-own || exit 1
gt_fixture_run staging release start 1.0.0 >/dev/null 2>&1
gt_fixture_commit "feat: Prepare the release"
gt_fixture_tag "staging/1.0.0-rc-01"
git branch temp-rebase-orphan >/dev/null 2>&1

# Through the dispatcher — the flag is stripped before abort's own parser runs.
before="$(fingerprint)"
"$GT_BIN/git-trident" abort --dry-run >/dev/null 2>&1 </dev/null
assert_equals "$(fingerprint)" "$before" "abort --dry-run (via dispatcher) changes nothing"

# And directly, where abort's own parser does see it.
before="$(fingerprint)"
"$GT_BIN/git-trident-abort" --dry-run >/dev/null 2>&1 </dev/null
assert_equals "$(fingerprint)" "$before" "abort --dry-run (direct) changes nothing"

# sync-tags likewise.
before="$(fingerprint)"
"$GT_BIN/git-trident" staging sync-tags 1.0.0 --dry-run >/dev/null 2>&1 </dev/null
assert_equals "$(fingerprint)" "$before" "sync-tags --dry-run (via dispatcher) changes nothing"

# Sanity: without the flag, abort really does remove the local-only state.
"$GT_BIN/git-trident" abort >/dev/null 2>&1 </dev/null
assert_tag_absent "staging/1.0.0-rc-01" "abort without --dry-run still removes local-only state"

gt_fixture_destroy
print_summary
