#!/bin/bash
# tests/test_sync_utils.sh
# Tests for validation guards in synchronization utilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define required configuration state
export CONFIG_LOADED=true
export STAGING_TAG_SUFFIX="-rc-"
export PLATFORMS="android ios web"
export PRODUCTION_TAG_PREFIX="prod-"
export STAGING_TAG_PREFIX="stg-"
export RELEASE_STAGING_PREFIX="release/stg/"
export PLATFORM_SPECIFIC_TAGS=false

# Source the target libraries
source "$PROJECT_ROOT/lib/git-trident-common.sh"
source "$PROJECT_ROOT/lib/git-trident-version-utils.sh"
source "$PROJECT_ROOT/lib/git-trident-staging-sync-from-production.sh"

start_suite "Synchronization Guards Validation"

# Mock functions used by the script
is_valid_tag() {
    return 0 # All tags exist in mock
}

extract_base_version_from_tag() {
    local tag="$1"
    local prefix="$2"
    # prod-2.0.0 -> 2.0.0
    echo "${tag#"$prefix"}"
}

get_latest_production_tag() {
    # mock latest
    echo "2.0.0" 
}

# ==========================================
# SYNC_01 & SYNC_02
# ==========================================
start_test_case "sync_01_not_deprecated"
# 2.0.0 vs 2.0.0 (not greater, so success)
(validate_production_tag_not_deprecated "2.0.0") >/dev/null 2>&1
assert_success "$?" "sync_01_not_deprecated"

start_test_case "sync_02_deprecated"
# latest=2.0.0 > base_version=1.0.0 -> deprecated (fail)
(validate_production_tag_not_deprecated "1.0.0") >/dev/null 2>&1
assert_failure "$?" "sync_02_deprecated"

# ==========================================
# SYNC_03 & SYNC_04 (Legacy mode tests)
# ==========================================
extract_version_from_tag() {
    local tag="$1"
    local prefix="$2"
    echo "${tag#"$prefix"}"
}

start_test_case "sync_03_include_tag_yes"
# Prod: 1.0.0, Staging: stg-2.0.0
(should_include_tag_for_production_sync "1.0.0" "stg-2.0.0") >/dev/null 2>&1
assert_success "$?" "sync_03_include_tag_yes"

start_test_case "sync_04_include_tag_no"
# Prod: 2.0.0, Staging: stg-1.0.0
(should_include_tag_for_production_sync "2.0.0" "stg-1.0.0") >/dev/null 2>&1
assert_failure "$?" "sync_04_include_tag_no"

print_summary
