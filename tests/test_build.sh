#!/bin/bash
# tests/test_build.sh
# Tests for build.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

start_suite "Build Script Validation"

# TB_01_BUILD_SUCCESS
start_test_case "tb_01_build_success"
# Clean build output first
rm -rf "$PROJECT_ROOT/dist"

# Run build.sh
(cd "$PROJECT_ROOT" && bash build.sh >/dev/null 2>&1)
assert_success "$?" "build.sh executed successfully"

# Check dist/git-trident.tar.gz exists
[ -f "$PROJECT_ROOT/dist/git-trident.tar.gz" ]
assert_success "$?" "Tarball git-trident.tar.gz was created"

# TB_02_TARBALL_CONTENTS
start_test_case "tb_02_tarball_contents"
# Check that key files are in the tarball
tarball_contents=$(tar -tf "$PROJECT_ROOT/dist/git-trident.tar.gz")
assert_contains "$tarball_contents" "bin/git-trident" "Tarball contains main dispatcher"
assert_contains "$tarball_contents" "lib/git-trident-common.sh" "Tarball contains common lib"
assert_contains "$tarball_contents" "lib/git-trident-constants.sh" "Tarball contains constants"
assert_contains "$tarball_contents" "install.sh" "Tarball contains installer"
assert_contains "$tarball_contents" "README.md" "Tarball contains README"

print_summary
