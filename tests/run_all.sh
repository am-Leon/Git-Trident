#!/bin/bash
# run_all.sh
# Executes all test scripts in the tests/ directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' 

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo "============================================="
echo "🧪 GIT TRIDENT - MASTER TEST RUNNER"
echo "============================================="

for test_script in "$SCRIPT_DIR"/test_*.sh; do
    # Skip the framework itself
    if [[ "$(basename "$test_script")" == "test_framework.sh" ]]; then
        continue
    fi
    
    ((TOTAL_SUITES++))
    echo -e "\n⏳ Running $(basename "$test_script")..."
    
    if bash "$test_script"; then
        ((PASSED_SUITES++))
    else
        ((FAILED_SUITES++))
        echo -e "${RED}⚠️ Suite $(basename "$test_script") failed.${NC}"
    fi
done

echo -e "\n============================================="
echo "🏆 MASTER SUMMARY"
echo "============================================="
echo "Total Suites: $TOTAL_SUITES"
echo -e "${GREEN}Passed:       $PASSED_SUITES${NC}"

if [ "$FAILED_SUITES" -gt 0 ]; then
    echo -e "${RED}Failed:       $FAILED_SUITES${NC}"
    echo -e "${RED}❌ SOME TESTS FAILED.${NC}"
    exit 1
else
    echo -e "${GREEN}🎉 ALL SUITES PASSED PERFECTLY!${NC}"
    exit 0
fi
