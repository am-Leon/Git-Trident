#!/bin/bash
# tests/test_version_utils.sh
# Tests for lib/git-trident-version-utils.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define required configuration state
export CONFIG_LOADED=true
export STAGING_TAG_SUFFIX="-rc-"
export PLATFORMS="android ios web"

# Source the target library
source "$PROJECT_ROOT/lib/git-trident-version-utils.sh"

start_suite "Version Utilities Validation"

# VU_01_EXTRACT_PLATFORM
start_test_case "vu_01_extract_platform"
actual=$(extract_platform_from_version "android-1.2.3-rc-01")
assert_equals "$actual" "android" "vu_01_extract_platform"

# VU_02_EXTRACT_PLATFORM_NONE
start_test_case "vu_02_extract_platform_none"
actual=$(extract_platform_from_version "1.2.3")
assert_equals "$actual" "" "vu_02_extract_platform_none"

# VU_03_BASE_VERS_PLATFORM
start_test_case "vu_03_base_vers_platform"
actual=$(extract_base_version "android-1.2.3-rc-05")
assert_equals "$actual" "1.2.3" "vu_03_base_vers_platform"

# VU_04_BASE_VERS_LEGACY
start_test_case "vu_04_base_vers_legacy"
actual=$(extract_base_version "1.2.3-rc-01")
assert_equals "$actual" "1.2.3" "vu_04_base_vers_legacy"

# VU_05_RC_NUM_EXTRACT
start_test_case "vu_05_rc_num_extract"
actual=$(extract_rc_number "1.2.3-rc-08")
assert_equals "$actual" "08" "vu_05_rc_num_extract"

# VU_06_RC_NUM_EXTRACT_NONE
start_test_case "vu_06_rc_num_extract_none"
actual=$(extract_rc_number "1.2.3")
assert_equals "$actual" "" "vu_06_rc_num_extract_none"

# VU_07_STG_VALID_PLATFORM
start_test_case "vu_07_stg_valid_platform"
export PLATFORM_SPECIFIC_TAGS=true
validate_staging_version_format "android-1.2.3" >/dev/null 2>&1
assert_success "$?" "vu_07_stg_valid_platform"

# VU_08_STG_INVALID_PLATFORM
start_test_case "vu_08_stg_invalid_platform"
export PLATFORM_SPECIFIC_TAGS=true
validate_staging_version_format "1.2.3" >/dev/null 2>&1
assert_failure "$?" "vu_08_stg_invalid_platform"

# VU_09_STG_RC_INVALID
start_test_case "vu_09_stg_rc_invalid"
export PLATFORM_SPECIFIC_TAGS=false
validate_staging_version_format "1.2.3-rc-01" >/dev/null 2>&1
assert_failure "$?" "vu_09_stg_rc_invalid"

print_summary
