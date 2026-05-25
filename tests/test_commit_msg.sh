#!/bin/bash
# tests/test_commit_msg.sh
# Tests for hooks/commit-msg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define variables needed by the script
export CONFIG_LOADED=true # Prevent loading of actual config files
export HOOKS_ENABLED=true
export HOOK_COMMIT_MSG_ENABLED=true
export REQUIRE_CAPITAL_START=true
export MIN_WORD_COUNT=3
export CMD_MIN_WORD_COUNT=2
export COMMIT_PREFIXES="wip|fix|feat|enhance|cmd|test"
export COMMIT_PREFIX_DESCRIPTIONS="Work In Progress|Bug Fixes|New Features|Enhancements|Commands|Tests"
export COMMIT_PLATFORM_PREFIX_FORMAT="[platform]"
export PLATFORMS="android ios web"
export STAGING_TAG_PREFIX="stg-"
export PRODUCTION_TAG_PREFIX="prod-"

run_commit_test() {
    local test_name="$1"
    local commit_msg="$2"
    local expected_result="$3"
    local is_platform_mode="${4:-false}"
    
    export PLATFORM_SPECIFIC_TAGS="$is_platform_mode"
    
    local temp_file=$(mktemp)
    echo "$commit_msg" > "$temp_file"
    
    start_test_case "$test_name"
    
    # Run the validation
    if bash "$PROJECT_ROOT/hooks/commit-msg" "$temp_file" >/dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    rm -f "$temp_file"
    
    assert_equals "$result" "$expected_result" "$test_name"
}

start_suite "Commit Message Validation (Legacy)"

# cm_01_merge_bypass
run_commit_test "cm_01_merge_bypass" "Merge branch develop" 0 false

# cm_02_legacy_valid (need 3 words minimum so "Add login flow")
run_commit_test "cm_02_legacy_valid" "feat: Add login flow" 0 false

# cm_03_legacy_space_err (two spaces after colon)
run_commit_test "cm_03_legacy_space_err" "feat:  Add login flow" 1 false

# cm_06_filename_valid
run_commit_test "cm_06_filename_valid" "feat: [Auth] Add login flow" 0 false

# cm_07_filename_case_err (description starts with lowercase 'a' after stripping prefix and fileName)
run_commit_test "cm_07_filename_case_err" "feat: [Auth] add login flow" 1 false

# cm_08_cmd_prefix_lower (cmd minimum 2 words)
run_commit_test "cm_08_cmd_prefix_lower" "cmd: update libs" 0 false

# cm_09_cmd_prefix_word_count
run_commit_test "cm_09_cmd_prefix_word_count" "cmd: run" 1 false

# cm_10_multiple_prefixes
run_commit_test "cm_10_multiple_prefixes" "feat: Add fix: new" 1 false

# cm_11_lower_start_err
run_commit_test "cm_11_lower_start_err" "feat: add login flow" 1 false

# cm_12_word_count_err
run_commit_test "cm_12_word_count_err" "feat: Add login" 1 false

# cm_13_word_count_valid
run_commit_test "cm_13_word_count_valid" "feat: Add new login" 0 false

# cm_14_flow_bypass
run_commit_test "cm_14_flow_bypass" "[flow]: Sync: Update STG" 0 false

start_suite "Commit Message Validation (Platform)"

# cm_04_platform_valid
run_commit_test "cm_04_platform_valid" "[android] feat: Add login flow" 0 true

# cm_05_platform_space_err
run_commit_test "cm_05_platform_space_err" "[android]feat: Add login flow" 1 true

# Extra platform spacing checks
run_commit_test "cm_05b_platform_space_extra" "[android]  feat: Add login flow" 1 true
run_commit_test "cm_05c_platform_space_prefix" "[android] feat:  Add login flow" 1 true

# Print final result
print_summary
