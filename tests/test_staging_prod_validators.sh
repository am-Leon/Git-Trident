#!/bin/bash
# tests/test_staging_prod_validators.sh
# Tests for validation guards in staging and production flows

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
source "$PROJECT_ROOT/lib/git-trident-staging.sh"
source "$PROJECT_ROOT/lib/git-trident-production.sh"

start_suite "Staging & Production Guards Validation"

# ==========================================
# STG_01 & STG_02
# ==========================================
is_valid_tag() {
    local tag="$1"
    if [ "$tag" = "prod-1.2.3" ]; then
        return 0 # Exists
    fi
    return 1 # Missing
}

start_test_case "stg_01_prod_guard (prod tag exists)"
(validate_version_not_in_production "1.2.3") >/dev/null 2>&1
assert_failure "$?" "stg_01_prod_guard"

start_test_case "stg_02_prod_guard_pass (prod tag missing)"
(validate_version_not_in_production "1.2.4") >/dev/null 2>&1
assert_success "$?" "stg_02_prod_guard_pass"

# ==========================================
# STG_03 & STG_04
# ==========================================
get_staging_tags_for_version() {
    local version="$1"
    if [ "$version" = "2.0.0" ]; then
        echo "stg-2.0.0-rc-01" # RCs exist
    else
        echo "" # No RCs
    fi
}

start_test_case "stg_03_new_rel_guard (rc tags exist)"
(validate_new_base_version "2.0.0") >/dev/null 2>&1
assert_failure "$?" "stg_03_new_rel_guard"

start_test_case "stg_04_new_rel_pass (no rc tags)"
(validate_new_base_version "2.1.0") >/dev/null 2>&1
assert_success "$?" "stg_04_new_rel_pass"

# ==========================================
# PROD_01 & PROD_02
# ==========================================
is_production_tag_released() {
    local version="$1"
    if [ "$version" = "3.0.0" ]; then
        return 0 # Released
    fi
    return 1 # Not released
}

# validate_production_version_format returns 0 to mock validation
validate_production_version_format() {
    return 0
}

start_test_case "prod_01_tag_exists"
(validate_release_version "3.0.0") >/dev/null 2>&1
assert_failure "$?" "prod_01_tag_exists"

start_test_case "prod_02_tag_missing"
(validate_release_version "3.1.0") >/dev/null 2>&1
assert_success "$?" "prod_02_tag_missing"

print_summary
