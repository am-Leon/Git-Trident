#!/bin/bash
# test_framework.sh
# Core framework for Git Trident testing

export TOTAL_TESTS=0
export PASSED_TESTS=0
export FAILED_TESTS=0

# Log colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print helper
test_log() {
    echo -e "$1"
}

# Run a test section
start_suite() {
    test_log "\n============================================="
    test_log "🚀 SUITE: $1"
    test_log "=============================================\n"
}

start_test_case() {
    test_log "🧪 TESTING: $1"
}

# Assert functions
assert_success() {
    local exit_code=$1
    local test_name=$2
    ((TOTAL_TESTS++))
    if [ "$exit_code" -eq 0 ]; then
        test_log "${GREEN}  ✅ PASS:${NC} $test_name"
        ((PASSED_TESTS++))
    else
        test_log "${RED}  ❌ FAIL:${NC} $test_name (Exit code: $exit_code, expected 0)"
        ((FAILED_TESTS++))
    fi
}

assert_failure() {
    local exit_code=$1
    local test_name=$2
    ((TOTAL_TESTS++))
    if [ "$exit_code" -ne 0 ]; then
        test_log "${GREEN}  ✅ PASS:${NC} $test_name"
        ((PASSED_TESTS++))
    else
        test_log "${RED}  ❌ FAIL:${NC} $test_name (Exit code: $exit_code, expected non-zero)"
        ((FAILED_TESTS++))
    fi
}

assert_equals() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"
    ((TOTAL_TESTS++))
    if [ "$actual" = "$expected" ]; then
        test_log "${GREEN}  ✅ PASS:${NC} $test_name"
        ((PASSED_TESTS++))
    else
        test_log "${RED}  ❌ FAIL:${NC} $test_name"
        test_log "     Expected: '$expected'"
        test_log "     Got:      '$actual'"
        ((FAILED_TESTS++))
    fi
}

assert_regex() {
    local actual="$1"
    local pattern="$2"
    local test_name="$3"
    ((TOTAL_TESTS++))
    if [[ "$actual" =~ $pattern ]]; then
        test_log "${GREEN}  ✅ PASS:${NC} $test_name"
        ((PASSED_TESTS++))
    else
        test_log "${RED}  ❌ FAIL:${NC} $test_name"
        test_log "     String:     '$actual'"
        test_log "     Not matched by: '$pattern'"
        ((FAILED_TESTS++))
    fi
}

assert_contains() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"
    ((TOTAL_TESTS++))
    if [[ "$actual" == *"$expected"* ]]; then
        test_log "${GREEN}  ✅ PASS:${NC} $test_name"
        ((PASSED_TESTS++))
    else
        test_log "${RED}  ❌ FAIL:${NC} $test_name"
        test_log "     String:   '$actual'"
        test_log "     Expected to contain: '$expected'"
        ((FAILED_TESTS++))
    fi
}

assert_not_contains() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"
    ((TOTAL_TESTS++))
    if [[ "$actual" != *"$expected"* ]]; then
        test_log "${GREEN}  ✅ PASS:${NC} $test_name"
        ((PASSED_TESTS++))
    else
        test_log "${RED}  ❌ FAIL:${NC} $test_name"
        test_log "     String:   '$actual'"
        test_log "     Expected NOT to contain: '$expected'"
        ((FAILED_TESTS++))
    fi
}

print_summary() {
    test_log "\n============================================="
    test_log "📊 TEST SUMMARY ($0)"
    test_log "============================================="
    test_log "Total Tests: $TOTAL_TESTS"
    test_log "${GREEN}Passed:      $PASSED_TESTS${NC}"
    if [ $FAILED_TESTS -gt 0 ]; then
        test_log "${RED}Failed:      $FAILED_TESTS${NC}"
        return 1
    else
        test_log "${GREEN}🎉 ALL TESTS PASSED!${NC}"
        return 0
    fi
}
