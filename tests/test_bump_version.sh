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

cleanup_sandbox

# TBV_04_RELEASE_VALIDATIONS
start_test_case "tbv_04_release_validations"
setup_sandbox

# Make build.sh fail
echo "exit 1" > "$SANDBOX_DIR/build.sh"

# Run in release mode - should abort because build.sh fails
(cd "$SANDBOX_DIR" && git init >/dev/null 2>&1)
bash "$SANDBOX_DIR/scripts/bump-version.sh" "2.3.4" --release >/dev/null 2>&1
assert_failure "$?" "Release aborts if build.sh fails"

# Restore build.sh, make run_all.sh fail
echo "exit 0" > "$SANDBOX_DIR/build.sh"
echo "exit 1" > "$SANDBOX_DIR/tests/run_all.sh"

bash "$SANDBOX_DIR/scripts/bump-version.sh" "2.3.5" --release >/dev/null 2>&1
assert_failure "$?" "Release aborts if tests/run_all.sh fails"

cleanup_sandbox

# TBV_05_RELEASE_PUSH
start_test_case "tbv_05_release_push"
setup_sandbox

# Setup mock git repository and bare remote in sandbox
mkdir -p "$SANDBOX_DIR/remote.git"
(cd "$SANDBOX_DIR/remote.git" && git init --bare >/dev/null 2>&1)

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
    
    git remote add origin "$SANDBOX_DIR/remote.git"
    git push -u origin main >/dev/null 2>&1
)

# Run release
(
    cd "$SANDBOX_DIR" || exit
    bash scripts/bump-version.sh "3.0.0" --release >/dev/null 2>&1
)
assert_success "$?" "Release mode completes successfully under mock git environment"

# Verify mock git repository has the bump commit
(
    cd "$SANDBOX_DIR" || exit
    git log -1 --format="%s" | grep -q "Bump version to 3.0.0"
)
assert_success "$?" "Git log has the bump version commit message"

# Verify tag was created
(
    cd "$SANDBOX_DIR" || exit
    git tag -l | grep -q "v3.0.0"
)
assert_success "$?" "Git tag v3.0.0 was successfully created"

# Verify tag was pushed to remote
(
    cd "$SANDBOX_DIR/remote.git" || exit
    git tag -l | grep -q "v3.0.0"
)
assert_success "$?" "Git tag v3.0.0 was pushed to remote"

# Clean up identity env vars
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

cleanup_sandbox

print_summary
