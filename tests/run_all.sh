#!/bin/bash
# run_all.sh
# Executes all test scripts in the tests/ directory.
#
# Suites run under GT_TEST_BASH — by default the PLATFORM'S OWN bash, not
# whatever happens to be first on PATH:
#
#   macOS    /bin/bash  → 3.2.57   ← the compatibility floor
#   Linux    /bin/bash  → 4.x/5.x
#   Windows  /bin/bash  → MSYS2 bash 4.4/5.x (Git Bash)
#
# This matters because a developer with `brew install bash` has Bash 5 ahead of
# /bin/bash on PATH. Testing under that shell hides Bash-4-only constructs that
# break for every macOS user. Override deliberately when testing another shell:
#
#   GT_TEST_BASH=/opt/homebrew/bin/bash bash tests/run_all.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Resolve the shell under test
# ---------------------------------------------------------------------------
if [ -z "${GT_TEST_BASH:-}" ]; then
    if [ -x /bin/bash ]; then
        GT_TEST_BASH=/bin/bash
    else
        GT_TEST_BASH="$(command -v bash 2>/dev/null)"
    fi
fi

if [ -z "$GT_TEST_BASH" ] || [ ! -x "$GT_TEST_BASH" ]; then
    echo -e "${RED}❌ No usable bash found (GT_TEST_BASH='${GT_TEST_BASH:-}')${NC}"
    exit 1
fi
export GT_TEST_BASH

GT_TEST_BASH_VERSION="$("$GT_TEST_BASH" -c 'echo "$BASH_VERSION"' 2>/dev/null)"
GT_HOST_OS="$(uname -s 2>/dev/null || echo unknown)"
case "$GT_HOST_OS" in
    Darwin*)              GT_HOST_LABEL="macOS" ;;
    Linux*)               GT_HOST_LABEL="Linux" ;;
    CYGWIN*|MINGW*|MSYS*) GT_HOST_LABEL="Windows (Git Bash)" ;;
    *)                    GT_HOST_LABEL="$GT_HOST_OS" ;;
esac

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_NAMES=""

echo "============================================="
echo "🧪 GIT TRIDENT - MASTER TEST RUNNER"
echo "============================================="
echo "  Platform : $GT_HOST_LABEL"
echo "  Shell    : $GT_TEST_BASH"
echo "  Version  : ${GT_TEST_BASH_VERSION:-unknown}"

# Loudly flag when we are NOT testing the macOS floor, so a green run on
# Bash 5 is never mistaken for proof that 3.2 works.
case "$GT_TEST_BASH_VERSION" in
    3.2*) echo -e "  ${GREEN}✓ Testing the Bash 3.2 compatibility floor${NC}" ;;
    *)    echo -e "  ${YELLOW}⚠ Not Bash 3.2 — macOS compatibility is NOT proven by this run${NC}" ;;
esac
echo "============================================="

for test_script in "$SCRIPT_DIR"/test_*.sh; do
    # Skip the framework itself
    if [ "$(basename "$test_script")" = "test_framework.sh" ]; then
        continue
    fi

    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo -e "\n⏳ Running $(basename "$test_script")..."

    if "$GT_TEST_BASH" "$test_script"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        FAILED_NAMES="$FAILED_NAMES  - $(basename "$test_script")"$'\n'
        echo -e "${RED}⚠️ Suite $(basename "$test_script") failed.${NC}"
    fi
done

echo -e "\n============================================="
echo "🏆 MASTER SUMMARY"
echo "============================================="
echo "Platform:     $GT_HOST_LABEL / bash ${GT_TEST_BASH_VERSION:-unknown}"
echo "Total Suites: $TOTAL_SUITES"
echo -e "${GREEN}Passed:       $PASSED_SUITES${NC}"

if [ "$FAILED_SUITES" -gt 0 ]; then
    echo -e "${RED}Failed:       $FAILED_SUITES${NC}"
    echo -e "${RED}$FAILED_NAMES${NC}"
    echo -e "${RED}❌ SOME TESTS FAILED.${NC}"
    exit 1
else
    echo -e "${GREEN}🎉 ALL SUITES PASSED PERFECTLY!${NC}"
    exit 0
fi
