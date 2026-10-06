#!/bin/bash
# tests/test_e2e_doctor_and_flags.sh
# Phase 5: `doctor`, `config validate`, and the global flags.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

# -F: the pattern contains '[', which grep would otherwise read as the start of
# a bracket expression rather than a literal character.
has_ansi() { printf '%s' "$1" | grep -qF "$(printf '\033')["; }

start_suite "E2E: Doctor, Config Validate and Global Flags"

# ===========================================================================
# DF_01 — doctor is useful OUTSIDE a repository
# ===========================================================================
start_test_case "df_01_doctor_outside_a_repository"
gt_fixture_new_repo doctor || exit 1
pushd /tmp >/dev/null || exit 1
out="$("$GT_BIN/git-trident" doctor 2>&1 </dev/null)"
popd >/dev/null || exit 1
assert_contains "$out" "Environment" "Reports the environment layer"
assert_contains "$out" "Installation" "Reports the installation layer"
assert_contains "$out" "Not inside a Git repository" "States why repository checks were skipped"
assert_not_contains "$out" "command not found" "No shell errors outside a repository"

# ===========================================================================
# DF_02 — doctor on a healthy repository
# ===========================================================================
start_test_case "df_02_doctor_healthy"
gt_fixture_run doctor
assert_success "$GT_RUN_STATUS" "doctor exits 0 on a healthy repository"
assert_no_shell_errors "doctor produces no shell errors"
assert_contains "$(gt_run_output)" "Everything checks out" "Reports a clean bill of health"

# ===========================================================================
# DF_03 — doctor reports real problems and exits non-zero
# ===========================================================================
start_test_case "df_03_doctor_detects_problems"
git branch -D staging >/dev/null 2>&1
git branch temp-rebase-9-9-9 >/dev/null 2>&1
gt_fixture_run doctor
assert_failure "$GT_RUN_STATUS" "doctor exits non-zero when something is wrong"
assert_contains "$(gt_run_output)" "Branch staging does not exist" "Names the missing branch"
assert_contains "$(gt_run_output)" "orphaned sync branch" "Reports the orphaned temp branch"
assert_contains "$(gt_run_output)" "cleanup prune temp" "Suggests the remedy"
git branch staging >/dev/null 2>&1
git branch -D temp-rebase-9-9-9 >/dev/null 2>&1

# ===========================================================================
# DF_04 — doctor stops at the first broken layer
# ===========================================================================
# A missing project config makes every repository-level answer meaningless, so
# doctor should say that and stop rather than emit confusing downstream noise.
start_test_case "df_04_doctor_stops_at_broken_layer"
mv git-trident-config /tmp/gt-df04-config
gt_fixture_run doctor
assert_failure "$GT_RUN_STATUS" "doctor fails when there is no project config"
assert_contains "$(gt_run_output)" "config init" "Points at config init"
assert_not_contains "$(gt_run_output)" "── Repository" "Repository layer is skipped, not guessed at"
mv /tmp/gt-df04-config git-trident-config

# ===========================================================================
# DF_05 — config validate
# ===========================================================================
start_test_case "df_05_config_validate"
gt_fixture_run config validate
assert_success "$GT_RUN_STATUS" "config validate exits 0 on a good config"
assert_contains "$(gt_run_output)" "Configuration is valid" "Says the config is valid"

sed -i.bak 's|^STAGING_BRANCH=.*|STAGING_BRANCH="does-not-exist"|' git-trident-config
rm -f git-trident-config.bak
gt_fixture_run config validate
assert_failure "$GT_RUN_STATUS" "config validate fails on a bad branch name"
assert_contains "$(gt_run_output)" "does-not-exist" "Names the offending branch"
sed -i.bak 's|^STAGING_BRANCH=.*|STAGING_BRANCH="staging"|' git-trident-config
rm -f git-trident-config.bak

# ===========================================================================
# DF_06 — colour follows STDERR, NO_COLOR and GT_COLOR
# ===========================================================================
start_test_case "df_06_colour_control"
gt_fixture_run status
has_ansi "$GT_RUN_STDERR" && r=1 || r=0
assert_success "$r" "No escape codes when stderr is captured"

out="$(GT_COLOR=always "$GT_BIN/git-trident" status 2>&1 </dev/null)"
has_ansi "$out" && r=0 || r=1
assert_success "$r" "GT_COLOR=always forces colour even when captured"

out="$(NO_COLOR=1 GT_COLOR=auto "$GT_BIN/git-trident" status 2>&1 </dev/null)"
has_ansi "$out" && r=1 || r=0
assert_success "$r" "NO_COLOR suppresses colour"

# ===========================================================================
# DF_07 — global flags are consumed, not forwarded to subcommands
# ===========================================================================
start_test_case "df_07_global_flags_are_stripped"
out="$("$GT_BIN/git-trident" status --no-color --yes 2>&1 </dev/null)"
assert_not_contains "$out" "Unknown option" "Global flags are not passed through to subcommands"

# ===========================================================================
# DF_08 — --yes answers a prompt that would otherwise block
# ===========================================================================
start_test_case "df_08_yes_auto_confirms"
# A FRESH fixture: df_03 deletes and recreates the staging branch to exercise
# doctor's failure reporting, which leaves the topology changed. Reusing it here
# would test that damage rather than --yes.
gt_fixture_destroy
gt_fixture_new_repo doctor-yes || exit 1

sed -i.bak 's/^REQUIRE_CONFIRMATION=.*/REQUIRE_CONFIRMATION=true/' "$HOME/.git-trident-config"
rm -f "$HOME/.git-trident-config.bak"

gt_fixture_run staging release start 1.0.0
gt_fixture_commit "feat: Prepare the first release"
"$GT_BIN/git-trident" staging release finish 1.0.0 --yes >/dev/null 2>&1 </dev/null
assert_success "$?" "release finish --yes completes without a prompt"
assert_tag_exists "staging/1.0.0-rc-01" "Tag created under --yes"

gt_fixture_destroy
print_summary
