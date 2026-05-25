#!/bin/bash
# tests/test_config_cleanup_hooks.sh
# Tests for two-tier config architecture, global key protection, cleanup restructures, and dry-run flag.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX_DIR="$SCRIPT_DIR/sandbox_test"

# Setup sandbox
setup_sandbox() {
    rm -rf "$SANDBOX_DIR"
    mkdir -p "$SANDBOX_DIR/home"
    cd "$SANDBOX_DIR" || exit 1
}

# Teardown sandbox
teardown_sandbox() {
    cd "$SCRIPT_DIR" || exit 1
    rm -rf "$SANDBOX_DIR"
}

start_suite "Two-Tier Configuration, Cleanup Commands & Dry Run"

# =============================================================================
# Test 1: Config Scaffolding (Config Init)
# =============================================================================
start_test_case "config_01_interactive_init"
setup_sandbox

# Simulate inputting answers into config init
# Inputs:
# 1. Production branch: prod-main
# 2. Staging branch: stg-rc
# 3. Develop branch: dev-flow
# 4. Remote: upstream
# 5. Staging tag prefix: rc-tags/
# 6. Production tag prefix: rel-tags/
# 7. RC suffix: -rc-
# 8. Platform specific: n (false)
echo -e "prod-main\nstg-rc\ndev-flow\nupstream\nrc-tags/\nrel-tags/\n-rc-\nn" | "$PROJECT_ROOT/bin/git-trident-config" init >/dev/null 2>&1

assert_success "$?" "git-trident-config init command exit status"

[ -f ./git-trident-config ]
assert_success "$?" "config file created"

# Source the generated config to check variables
PRODUCTION_BRANCH=""
STAGING_BRANCH=""
DEVELOP_BRANCH=""
REMOTE=""
STAGING_TAG_PREFIX=""
PRODUCTION_TAG_PREFIX=""

source ./git-trident-config
assert_equals "$PRODUCTION_BRANCH" "prod-main" "PRODUCTION_BRANCH configured correctly"
assert_equals "$STAGING_BRANCH" "stg-rc" "STAGING_BRANCH configured correctly"
assert_equals "$DEVELOP_BRANCH" "dev-flow" "DEVELOP_BRANCH configured correctly"
assert_equals "$REMOTE" "upstream" "REMOTE configured correctly"
assert_equals "$STAGING_TAG_PREFIX" "rc-tags/" "STAGING_TAG_PREFIX configured correctly"
assert_equals "$PRODUCTION_TAG_PREFIX" "rel-tags/" "PRODUCTION_TAG_PREFIX configured correctly"

# =============================================================================
# Test 2: Two-Tier Configuration Loading
# =============================================================================
start_test_case "config_02_two_tier_loading"
setup_sandbox

# Setup mock HOME for global config
export HOME="$SANDBOX_DIR/home"

# Write mock Global Config
cat <<EOF > "$HOME/.git-trident-config"
AUTO_PUSH_ON_FINISH=true
DELETE_BRANCH_ON_FINISH=false
HOOKS_ENABLED=true
CONFIG_VALIDATION_MODE=relaxed
EOF

# Write mock Project Config
cat <<EOF > "./git-trident-config"
PRODUCTION_BRANCH="main-prod"
STAGING_BRANCH="main-stg"
DEVELOP_BRANCH="main-dev"
REMOTE="origin"
STAGING_TAG_PREFIX="stg/"
PRODUCTION_TAG_PREFIX="prod/"
EOF

# Reset existing env variables
unset AUTO_PUSH_ON_FINISH
unset DELETE_BRANCH_ON_FINISH
unset HOOKS_ENABLED
unset PRODUCTION_BRANCH
unset CONFIG_LOADED

# Source common and trigger loading
source "$PROJECT_ROOT/lib/git-trident-common.sh" --no-init
load_project_config >/dev/null 2>&1

assert_equals "$CONFIG_LOADED" "true" "Config loaded status is true"
assert_equals "$AUTO_PUSH_ON_FINISH" "true" "Global variable AUTO_PUSH_ON_FINISH loaded"
assert_equals "$DELETE_BRANCH_ON_FINISH" "false" "Global variable DELETE_BRANCH_ON_FINISH loaded"
assert_equals "$PRODUCTION_BRANCH" "main-prod" "Project variable PRODUCTION_BRANCH loaded and overrides default"

# =============================================================================
# Test 3: Global-Only Keys Override Protection
# =============================================================================
start_test_case "config_03_global_only_key_protection"
setup_sandbox

export HOME="$SANDBOX_DIR/home"

# Global sets AUTO_PUSH_ON_FINISH to true
cat <<EOF > "$HOME/.git-trident-config"
AUTO_PUSH_ON_FINISH=true
EOF

# Project tries to override AUTO_PUSH_ON_FINISH to false (restricted global-only key)
cat <<EOF > "./git-trident-config"
PRODUCTION_BRANCH="main-prod"
STAGING_BRANCH="main-stg"
DEVELOP_BRANCH="main-dev"
REMOTE="origin"
STAGING_TAG_PREFIX="stg/"
PRODUCTION_TAG_PREFIX="prod/"
AUTO_PUSH_ON_FINISH=false
EOF

unset AUTO_PUSH_ON_FINISH
unset CONFIG_LOADED

source "$PROJECT_ROOT/lib/git-trident-common.sh" --no-init
load_project_config >/dev/null 2>&1

# Assert project override is ignored and restored back to global baseline (true)
assert_equals "$AUTO_PUSH_ON_FINISH" "true" "Restricted global key AUTO_PUSH_ON_FINISH project override was ignored/restored"

# =============================================================================
# Test 4: Quiet Loading with SUPPRESS_CONFIG_ERRORS
# =============================================================================
start_test_case "config_04_suppress_errors"
setup_sandbox

# Delete configs to force error
rm -f "$HOME/.git-trident-config"
rm -f "./git-trident-config"

unset CONFIG_LOADED
export SUPPRESS_CONFIG_ERRORS=true

source "$PROJECT_ROOT/lib/git-trident-common.sh" --no-init
output=$(load_project_config 2>&1)

assert_failure "$?" "load_project_config fails when no configs exist"
assert_equals "$output" "" "Error output was completely suppressed with SUPPRESS_CONFIG_ERRORS"

# =============================================================================
# Test 5: Cleanup CLI Arguments and Routing
# =============================================================================
start_test_case "cleanup_01_subcommand_routing"
setup_sandbox

# Define mock environment for cleanup command
export HOME="$SANDBOX_DIR/home"
cat <<EOF > "$HOME/.git-trident-config"
CONFIG_VALIDATION_MODE=relaxed
EOF

cat <<EOF > "./git-trident-config"
PRODUCTION_BRANCH="production"
STAGING_BRANCH="staging"
DEVELOP_BRANCH="develop"
REMOTE="origin"
STAGING_TAG_PREFIX="staging/"
PRODUCTION_TAG_PREFIX="production/"
EOF

# Mock git command to avoid hitting the actual git repo/network
git() {
    local cmd="$1"
    shift
    if [[ "$cmd" == "ls-remote" ]]; then
        return 0
    elif [[ "$cmd" == "fetch" ]]; then
        return 0
    elif [[ "$cmd" == "branch" && "$*" == "-vv" ]]; then
        echo "  feature/gone abc1234 [origin/feature/gone: gone] commit msg"
        echo "* develop abc1234 commit msg"
        return 0
    elif [[ "$cmd" == "branch" && "$*" == "--show-current" ]]; then
        echo "develop"
        return 0
    elif [[ "$cmd" == "symbolic-ref" ]]; then
        echo "develop"
        return 0
    elif [[ "$cmd" == "tag" && "$*" == "-l production/"* ]]; then
        echo "production/1.0.0"
        return 0
    elif [[ "$cmd" == "tag" && "$*" == "-l staging/"* ]]; then
        echo "staging/1.0.0-rc-01"
        return 0
    elif [[ "$cmd" == "rev-parse" ]]; then
        echo "develop"
        return 0
    else
        command git "$cmd" "$@"
    fi
}
export -f git

# Mock confirm_action to always return true (0)
confirm_action() {
    return 0
}
export -f confirm_action

# Test subcommand routing validations

# 1. Sync subcommand with tags
output_sync_tags=$(echo "y" | "$PROJECT_ROOT/bin/git-trident-cleanup" sync tags 2>&1)
assert_contains "$output_sync_tags" "SYNCING TAGS" "cleanup sync tags is routed"

# 2. Sync subcommand with branches
output_sync_branches=$(echo "y" | "$PROJECT_ROOT/bin/git-trident-cleanup" sync branches 2>&1)
assert_contains "$output_sync_branches" "SYNCING LOCAL BRANCHES" "cleanup sync branches is routed"

# 3. Sync subcommand with no target (both)
output_sync_all=$(echo "y" | "$PROJECT_ROOT/bin/git-trident-cleanup" sync 2>&1)
assert_contains "$output_sync_all" "FULL SYNC" "cleanup sync (no target) routes both tags and branches"

# 4. Prune subcommand
output_prune=$(echo "y" | "$PROJECT_ROOT/bin/git-trident-cleanup" prune 2>&1)
assert_contains "$output_prune" "Scanning for deprecated staging tags" "cleanup prune is routed"

# =============================================================================
# Test 6: Dry Run Flag Standardization
# =============================================================================
start_test_case "cleanup_02_dry_run_flag"
setup_sandbox

# Verify that --dry-run flag is parsed in git-trident-staging-sync-tags
# We mock git-trident-staging-sync-tags dependencies
export CONFIG_LOADED=true
export STAGING_TAG_SUFFIX="-rc-"
export PLATFORMS="android ios web"
export PRODUCTION_TAG_PREFIX="production/"
export STAGING_TAG_PREFIX="staging/"
export RELEASE_STAGING_PREFIX="release/staging/"
export PLATFORM_SPECIFIC_TAGS=false
export REMOTE="origin"

# Verify argument parser parses --dry-run
output_dry_run=$("$PROJECT_ROOT/bin/git-trident-staging-sync-tags" 1.0.0 --dry-run 2>&1)
assert_contains "$output_dry_run" "Checking sync impact" "Dry-run mode recognized correctly via --dry-run flag in sync-tags"

# Clean up mock functions
unset -f git
unset -f confirm_action

teardown_sandbox
print_summary

teardown_sandbox
print_summary
