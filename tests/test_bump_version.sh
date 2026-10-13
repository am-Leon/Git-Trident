#!/bin/bash
# tests/test_bump_version.sh
# Tests for scripts/bump-version.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

start_suite "Version Bump Script Validation"

# Setup sandbox function
setup_sandbox() {
    SANDBOX_DIR=$(mktemp -d -t git-trident-bump-test-XXXXXXXX)
    mkdir -p "$SANDBOX_DIR/scripts"
    mkdir -p "$SANDBOX_DIR/lib"
    mkdir -p "$SANDBOX_DIR/tests"

    # Copy bump script to sandbox
    cp "$PROJECT_ROOT/scripts/bump-version.sh" "$SANDBOX_DIR/scripts/"

    # Create dummy constants.sh file
    cat << 'EOF' > "$SANDBOX_DIR/lib/git-trident-constants.sh"
TRIDENT_VERSION="1.0.2"
GITHUB_REPO="am-Leon/Git-Trident"
EOF

    # Create dummy test_remote_installation.sh file
    cat << 'EOF' > "$SANDBOX_DIR/tests/test_remote_installation.sh"
# Dummy test file with version assertions
assert_equals "$TRIDENT_VERSION" "1.0.2" "version matches"
EOF

    # Dummy CHANGELOG with an [Unreleased] heading for the dating check
    cat << 'EOF' > "$SANDBOX_DIR/CHANGELOG.md"
# Changelog

## [9.9.9] — Unreleased

- something
EOF

    # Create dummy build.sh
    echo "exit 0" > "$SANDBOX_DIR/build.sh"
    chmod +x "$SANDBOX_DIR/build.sh"

    # Create dummy run_all.sh
    echo "exit 0" > "$SANDBOX_DIR/tests/run_all.sh"
    chmod +x "$SANDBOX_DIR/tests/run_all.sh"
}

cleanup_sandbox() {
    rm -rf "$SANDBOX_DIR"
}

# TBV_01_ARG_VALIDATION
start_test_case "tbv_01_arg_validation"
setup_sandbox

# Run with no arguments
bash "$SANDBOX_DIR/scripts/bump-version.sh" >/dev/null 2>&1
assert_failure "$?" "bump-version.sh fails when run with no arguments"

# Run with invalid version format
bash "$SANDBOX_DIR/scripts/bump-version.sh" "1.0" >/dev/null 2>&1
assert_failure "$?" "bump-version.sh fails when run with major.minor format"

bash "$SANDBOX_DIR/scripts/bump-version.sh" "abc" >/dev/null 2>&1
assert_failure "$?" "bump-version.sh fails when run with alphabetic format"

cleanup_sandbox

# TBV_02_SAME_VERSION
start_test_case "tbv_02_same_version"
setup_sandbox

# Run with current version 1.0.2
bash "$SANDBOX_DIR/scripts/bump-version.sh" "1.0.2" >/dev/null 2>&1
assert_success "$?" "bump-version.sh exits 0 when version is already target version"

# Check that version was not changed
grep -q 'TRIDENT_VERSION="1.0.2"' "$SANDBOX_DIR/lib/git-trident-constants.sh"
assert_success "$?" "Constants file is unchanged"

cleanup_sandbox

# TBV_03_LOCAL_BUMP
start_test_case "tbv_03_local_bump"
setup_sandbox

# Run with new version 2.3.4
bash "$SANDBOX_DIR/scripts/bump-version.sh" "2.3.4" >/dev/null 2>&1
assert_success "$?" "bump-version.sh local bump completes successfully"

# Verify constants.sh is updated
grep -q 'TRIDENT_VERSION="2.3.4"' "$SANDBOX_DIR/lib/git-trident-constants.sh"
assert_success "$?" "Constants file is updated to 2.3.4"

# Verify test assertions are updated
grep -q '"2.3.4"' "$SANDBOX_DIR/tests/test_remote_installation.sh"
assert_success "$?" "Test file assertions are updated to 2.3.4"

# The [Unreleased] heading must be dated. A published release whose changelog
# still says "Unreleased" is how a changelog stops being believed.
grep -qE "^## \[2\.3\.4\] — [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$SANDBOX_DIR/CHANGELOG.md"
assert_success "$?" "CHANGELOG [Unreleased] heading is dated as [2.3.4] — YYYY-MM-DD"

grep -q 'Unreleased' "$SANDBOX_DIR/CHANGELOG.md" && u=1 || u=0
[ "$u" -eq 0 ]
assert_success "$?" "No 'Unreleased' marker remains after the bump"

cleanup_sandbox

# TBV_04_RELEASE_VALIDATIONS
start_test_case "tbv_04_release_validations"
setup_sandbox

# Make build.sh fail
echo "exit 1" > "$SANDBOX_DIR/build.sh"

# Commit everything first. Release preflight now refuses a dirty tree, and an
# uncommitted sandbox would abort for THAT reason — the assertion below would
# still pass while testing nothing about build.sh.
(
    cd "$SANDBOX_DIR" || exit
    git init >/dev/null 2>&1
    git checkout -b main >/dev/null 2>&1 || true
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add -A && git commit -m "Initial commit" >/dev/null 2>&1
)

# Run in release mode - should abort because build.sh fails
(cd "$SANDBOX_DIR" && bash scripts/bump-version.sh "2.3.4" --release --yes >/dev/null 2>&1)
assert_failure "$?" "Release aborts if build.sh fails"

# Restore build.sh, make run_all.sh fail. The failed run above left the version
# files edited, so commit them to get back to a clean tree.
echo "exit 0" > "$SANDBOX_DIR/build.sh"
echo "exit 1" > "$SANDBOX_DIR/tests/run_all.sh"
(cd "$SANDBOX_DIR" && git add -A && git commit -m "wip: after failed build" >/dev/null 2>&1)

(cd "$SANDBOX_DIR" && bash scripts/bump-version.sh "2.3.5" --release --yes >/dev/null 2>&1)
assert_failure "$?" "Release aborts if tests/run_all.sh fails"

# --- New preflight guards ---------------------------------------------------
(cd "$SANDBOX_DIR" && echo "stray" > stray.txt)
(cd "$SANDBOX_DIR" && bash scripts/bump-version.sh "9.9.9" --release --yes >/dev/null 2>&1)
assert_failure "$?" "Release refuses a dirty working tree"
rm -f "$SANDBOX_DIR/stray.txt"

# A lower version must be refused: publishing it would make `version update` a
# downgrade for everyone already on the current release.
(cd "$SANDBOX_DIR" && bash scripts/bump-version.sh "0.0.1" >/dev/null 2>&1)
assert_failure "$?" "Refuses a version lower than the current one"

# An existing tag means that release is already cut.
(cd "$SANDBOX_DIR" && git tag v8.8.8 >/dev/null 2>&1)
(cd "$SANDBOX_DIR" && bash scripts/bump-version.sh "8.8.8" --release --yes >/dev/null 2>&1)
assert_failure "$?" "Release refuses a tag that already exists"

# Without --yes and without a terminal it must fail, not block forever.
(cd "$SANDBOX_DIR" && bash scripts/bump-version.sh "7.7.7" --release </dev/null >/dev/null 2>&1)
assert_failure "$?" "Release without --yes fails fast when there is no terminal"

cleanup_sandbox

# TBV_05_RELEASE_PUSH
start_test_case "tbv_05_release_push"
setup_sandbox

# The bare remote lives OUTSIDE the working tree. Nested inside it, as it was,
# git reports remote.git/ as untracked and the clean-tree preflight refuses the
# release — a fixture artefact that looks exactly like a script bug.
REMOTE_DIR="${SANDBOX_DIR}-remote.git"
mkdir -p "$REMOTE_DIR"
(cd "$REMOTE_DIR" && git init --bare >/dev/null 2>&1)

# Export git identity so it propagates into bump-version.sh's git commit subshell
export GIT_AUTHOR_NAME="Test User"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test User"
export GIT_COMMITTER_EMAIL="test@example.com"

(
    cd "$SANDBOX_DIR" || exit
    git init >/dev/null 2>&1
    # Ensure branch is 'main' regardless of git version (older git defaults to 'master')
    git checkout -b main >/dev/null 2>&1 || true
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Commit dummy files so git has a main branch
    git add -A
    git commit -m "Initial commit" >/dev/null 2>&1
    
    git remote add origin "$REMOTE_DIR"
    git push -u origin main >/dev/null 2>&1
)

# Run release
(
    cd "$SANDBOX_DIR" || exit
    bash scripts/bump-version.sh "3.0.0" --release --yes >/dev/null 2>&1
)
assert_success "$?" "Release mode completes successfully under mock git environment"

# Verify mock git repository has the release commit. The message is no longer
# "wip: Bump version to X" — a published release is not work in progress.
(
    cd "$SANDBOX_DIR" || exit
    git log -1 --format="%s" | grep -q "^chore: Release v3.0.0$"
)
assert_success "$?" "Git log has the release commit message"

# Only the files the script changed may be in that commit. It used to
# `git add -A`, sweeping unrelated work into a commit labelled as a bump.
(
    cd "$SANDBOX_DIR" || exit
    changed="$(git show --name-only --format= HEAD | grep -c .)"
    [ "$changed" -le 3 ]
)
assert_success "$?" "Release commit contains only the files the script changed"

# The tag must be annotated, so it carries its own author and date.
(
    cd "$SANDBOX_DIR" || exit
    [ "$(git cat-file -t "$(git rev-parse v3.0.0)")" = "tag" ]
)
assert_success "$?" "Tag v3.0.0 is annotated, not lightweight"

# Verify tag was created
(
    cd "$SANDBOX_DIR" || exit
    git tag -l | grep -q "v3.0.0"
)
assert_success "$?" "Git tag v3.0.0 was successfully created"

# Verify tag was pushed to remote
(
    cd "$REMOTE_DIR" || exit
    git tag -l | grep -q "v3.0.0"
)
assert_success "$?" "Git tag v3.0.0 was pushed to remote"

rm -rf "$REMOTE_DIR"

# Clean up identity env vars
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

cleanup_sandbox

print_summary
