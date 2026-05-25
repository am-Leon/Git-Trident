#!/bin/bash
# tests/test_remote_installation.sh
# Tests for centralized constants, version checks, and remote installation paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

start_suite "Remote Installation & Centralized Constants"

# RI_01_CENTRAL_CONSTANTS_FILE
start_test_case "ri_01_central_constants_file"
[ -f "$PROJECT_ROOT/lib/git-trident-constants.sh" ]
assert_success "$?" "Constants file exists"

# RI_02_CENTRAL_CONSTANTS_CONTENT
start_test_case "ri_02_central_constants_content"
unset TRIDENT_VERSION
unset GITHUB_REPO
unset GITHUB_RELEASE_API
source "$PROJECT_ROOT/lib/git-trident-constants.sh"
assert_equals "$TRIDENT_VERSION" "1.0.0" "Version constant is correct"
assert_equals "$GITHUB_REPO" "am-Leon/Git-Trident" "GitHub repo constant is correct"
assert_equals "$GITHUB_RELEASE_API" "https://api.github.com/repos/am-Leon/Git-Trident/releases/latest" "Release API constant is correct"

# RI_03_COMMON_SH_SOURCES_CONSTANTS
start_test_case "ri_03_common_sh_sources_constants"
unset TRIDENT_VERSION
unset GITHUB_REPO
unset GITHUB_RELEASE_API
# Source git-trident-common.sh with dummy variables to satisfy verification
export CONFIG_LOADED=true
export PRODUCTION_BRANCH="main"
export STAGING_BRANCH="staging"
export DEVELOP_BRANCH="develop"
export REMOTE="origin"
export STAGING_TAG_PREFIX="staging/"
export PRODUCTION_TAG_PREFIX="production/"

source "$PROJECT_ROOT/lib/git-trident-common.sh" --no-init >/dev/null 2>&1
assert_equals "$TRIDENT_VERSION" "1.0.0" "Version loaded via common.sh"
assert_equals "$GITHUB_REPO" "am-Leon/Git-Trident" "GitHub repo loaded via common.sh"

# RI_04_BUILD_SCRIPT_SYNCS_REPO
start_test_case "ri_04_build_script_syncs_repo"
# Verify GITHUB_REPO is synced in install.sh
grep_repo=$(grep -E '^GITHUB_REPO=' "$PROJECT_ROOT/install.sh" | head -n 1)
assert_contains "$grep_repo" "am-Leon/Git-Trident" "build.sh correctly synced GITHUB_REPO to install.sh"

# RI_05_REMOTE_INSTALLATION_FLOW
start_test_case "ri_05_remote_installation_flow"
# Create a temporary directory for the installation test
TEST_INSTALL_DIR=$(mktemp -d -t git-trident-test-XXXXXXXX)

# Build the latest package if it doesn't exist
if [ ! -f "$PROJECT_ROOT/dist/git-trident.tar.gz" ]; then
    (cd "$PROJECT_ROOT" && bash build.sh >/dev/null 2>&1)
fi

# Run install.sh simulating remote execution. We pipe "n" to bypass hook prompt.
echo "n" | HOME="$TEST_INSTALL_DIR" SHELL="/bin/bash" LOCAL_TARBALL="$PROJECT_ROOT/dist/git-trident.tar.gz" bash "$PROJECT_ROOT/install.sh" "$TEST_INSTALL_DIR/installed-tools" >/dev/null 2>&1
install_status="$?"
assert_success "$install_status" "install.sh remote installation path executed successfully"

# Check that the files were correctly placed in the custom install dir
[ -f "$TEST_INSTALL_DIR/installed-tools/.git-trident/bin/git-trident" ]
assert_success "$?" "git-trident binary installed correctly"

[ -f "$TEST_INSTALL_DIR/installed-tools/.git-trident/lib/git-trident-constants.sh" ]
assert_success "$?" "git-trident-constants.sh installed correctly"

[ -f "$TEST_INSTALL_DIR/.git-trident-config" ]
assert_success "$?" "Global configuration template created in HOME"

# Clean up our test installation directory
rm -rf "$TEST_INSTALL_DIR"

print_summary
