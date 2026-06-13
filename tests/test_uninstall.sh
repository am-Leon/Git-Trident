#!/bin/bash
# tests/test_uninstall.sh
# Tests for bin/git-trident-uninstall

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

start_suite "Standalone Uninstaller Validation"

# TU_01_UNINSTALL_FLOW
start_test_case "tu_01_uninstall_flow"

# Create a temporary sandbox directory for testing uninstallation safely
SANDBOX_DIR=$(mktemp -d -t git-trident-uninstall-test-XXXXXXXX)
MOCK_HOME="$SANDBOX_DIR/mock_home"
MOCK_INSTALL_DIR="$SANDBOX_DIR/mock_install"

mkdir -p "$MOCK_HOME"
mkdir -p "$MOCK_INSTALL_DIR/bin"
mkdir -p "$MOCK_INSTALL_DIR/lib"

# 1. Copy required files to mock install directory
cp "$PROJECT_ROOT/bin/git-trident-uninstall" "$MOCK_INSTALL_DIR/bin/"
cp "$PROJECT_ROOT/lib/git-trident-constants.sh" "$MOCK_INSTALL_DIR/lib/"
cp "$PROJECT_ROOT/lib/git-trident-common.sh" "$MOCK_INSTALL_DIR/lib/"

# 2. Create a mock shell profile and insert PATH modifications
MOCK_PROFILE="$MOCK_HOME/.bash_profile"
cat << 'EOF' > "$MOCK_PROFILE"
# Some pre-existing profile configuration
export EDITOR=vim

# Git Trident PATH modifications
export PATH="/Users/abduelrahman/.git-trident/bin:$PATH" # Git Trident
EOF

# 3. Create a mock global configuration file
echo "AUTO_PUSH_ON_FINISH=true" > "$MOCK_HOME/.git-trident-config"

# Check preconditions in sandbox
[ -d "$MOCK_INSTALL_DIR" ]
assert_success "$?" "Sandbox mock install directory exists before uninstall"
[ -f "$MOCK_HOME/.git-trident-config" ]
assert_success "$?" "Sandbox mock global config exists before uninstall"
grep -q "# Git Trident" "$MOCK_PROFILE"
assert_success "$?" "Sandbox mock profile has Git Trident entries before uninstall"

# 4. Run the uninstaller script with --force in the sandbox
# We mock SHELL to bash so it targets .bash_profile
export SHELL="/bin/bash"
HOME="$MOCK_HOME" bash "$MOCK_INSTALL_DIR/bin/git-trident-uninstall" --force >/dev/null 2>&1
uninstall_status="$?"

# 5. Assertions
assert_success "$uninstall_status" "Uninstaller script exited with 0"

# Verify that the installation directory was deleted
[ ! -d "$MOCK_INSTALL_DIR" ]
assert_success "$?" "Mock installation directory was completely removed"

# Verify that the global config file was deleted
[ ! -f "$MOCK_HOME/.git-trident-config" ]
assert_success "$?" "Mock global config file was removed"

# Verify that the profile has been cleaned up
grep -q "git-trident" "$MOCK_PROFILE"
assert_failure "$?" "Mock shell profile no longer contains Git Trident entries"

# Clean up sandbox
rm -rf "$SANDBOX_DIR"

print_summary
