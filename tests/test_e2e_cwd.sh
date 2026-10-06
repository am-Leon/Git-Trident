#!/bin/bash
# tests/test_e2e_cwd.sh
# Git Trident must work from anywhere inside the working tree, and inside a
# worktree — not only from the repository root.
#
# Before GT_REPO_ROOT/GT_GIT_DIR existed, the project config was looked up as
# "./git-trident-config" and lock/cache files were written to a literal ".git/",
# both relative to the CURRENT directory. Every command failed one level down,
# which for the monorepo and KMP projects this tool targets is the normal way to
# work.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"
source "$SCRIPT_DIR/lib/repo_fixture.sh"

start_suite "E2E: Working Directory & Worktree Independence"

start_test_case "ec_01_commands_from_a_subdirectory"
gt_fixture_new_repo cwd || exit 1
mkdir -p "$GT_FIXTURE_REPO/modules/app/src"
cd "$GT_FIXTURE_REPO/modules/app/src" || exit 1

for cmd in "status" "verify-sync --brief" "tags staging" "version config"; do
    gt_fixture_run $cmd
    assert_not_contains "$(gt_run_output)" "No project configuration file found" \
        "git trident $cmd works three levels below the root"
done

start_test_case "ec_02_full_release_from_a_subdirectory"
gt_fixture_run staging release start 1.0.0
assert_success "$GT_RUN_STATUS" "staging release start from a subdirectory"
gt_fixture_commit "feat: Prepare release from a subdirectory"
gt_fixture_run staging release finish 1.0.0
assert_success "$GT_RUN_STATUS" "staging release finish from a subdirectory"
assert_tag_exists "staging/1.0.0-rc-01" "Tag created when run from a subdirectory"

start_test_case "ec_03_artifacts_land_at_the_repository_root"
cd "$GT_FIXTURE_REPO/modules/app/src" || exit 1
gt_fixture_run staging release start 2.0.0 >/dev/null 2>&1
gt_fixture_run staging changelog 2.0.0
assert_no_shell_errors "changelog from a subdirectory produces no shell errors"
[ -d "$GT_FIXTURE_REPO/release_notes" ]
assert_success "$?" "release_notes/ created at the repository root"
[ -d "$GT_FIXTURE_REPO/modules/app/src/release_notes" ]
assert_failure "$?" "No stray release_notes/ in the subdirectory"

start_test_case "ec_04_git_dir_artifacts_use_the_real_git_dir"
cd "$GT_FIXTURE_REPO" || exit 1
git checkout -q develop
real_git_dir="$(git rev-parse --absolute-git-dir)"

# First run flushes anything outstanding. A SUCCESSFUL tag push deliberately
# clears the remote-tag cache (otherwise the next run reads stale data for up to
# REMOTE_TAG_CACHE_DURATION), so the cache is only observable on a run that had
# nothing to push.
gt_fixture_run push-all origin
gt_fixture_run push-all origin
assert_contains "$(gt_run_output)" "up to date" "Second push-all finds nothing to push"

[ -f "$real_git_dir/git-trident-remote-tags-origin" ]
assert_success "$?" "Remote-tag cache written inside the real git dir"
[ -e "$GT_FIXTURE_REPO/modules/app/src/.git" ]
assert_failure "$?" "No stray .git/ created in the subdirectory"

# And the cache really is cleared once a push succeeds.
gt_fixture_tag "staging/9.9.9-rc-01" >/dev/null 2>&1
gt_fixture_run push-all origin
[ -f "$real_git_dir/git-trident-remote-tags-origin" ]
assert_failure "$?" "Cache cleared after a successful tag push"

start_test_case "ec_05_runs_inside_a_git_worktree"
cd "$GT_FIXTURE_REPO" || exit 1
wt="$GT_FIXTURE_ROOT/worktree"
git worktree add -q "$wt" -b wt-branch >/dev/null 2>&1
cd "$wt" || exit 1
# In a worktree .git is a FILE, so "$GT_REPO_ROOT/.git" would not be a directory.
[ -f "$wt/.git" ]
assert_success "$?" "Worktree .git is a file, not a directory"
gt_fixture_run status
assert_no_shell_errors "status works inside a worktree"
assert_not_contains "$(gt_run_output)" "No project configuration file found" \
    "Project config resolves inside a worktree"
cd "$GT_FIXTURE_REPO" || exit 1
git worktree remove --force "$wt" >/dev/null 2>&1

gt_fixture_destroy
print_summary
