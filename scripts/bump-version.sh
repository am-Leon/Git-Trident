#!/bin/bash
# =============================================================================
# Git Trident — Version Bump Script
# =============================================================================
# Usage:
#   ./scripts/bump-version.sh <VERSION>              # Bump locally only
#   ./scripts/bump-version.sh <VERSION> --release     # Bump + commit + tag + push
#
# Examples:
#   ./scripts/bump-version.sh 1.0.3
#   ./scripts/bump-version.sh 1.0.3 --release
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Cross-platform sed -i ---
_sed_in_place() {
    local file="$1"
    local expression="$2"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "$expression" "$file"
    else
        sed -i "$expression" "$file"
    fi
}

# --- Validate version format ---
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}❌ Invalid version format: $version${NC}"
        echo -e "   Expected: ${CYAN}MAJOR.MINOR.PATCH${NC} (e.g., 1.0.3)"
        exit 1
    fi
}

# --- Parse arguments ---
if [[ $# -lt 1 ]]; then
    echo -e "${YELLOW}Usage:${NC} ./scripts/bump-version.sh <VERSION> [--release]"
    echo ""
    echo "  VERSION     Semantic version (e.g., 1.0.3)"
    echo "  --release   Commit, tag, and push after bumping"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  ./scripts/bump-version.sh 1.0.3"
    echo "  ./scripts/bump-version.sh 1.0.3 --release"
    exit 1
fi

NEW_VERSION="$1"
RELEASE_FLAG="${2:-}"

validate_version "$NEW_VERSION"

# --- File paths ---
CONSTANTS_FILE="$PROJECT_ROOT/lib/git-trident-constants.sh"
TEST_FILE="$PROJECT_ROOT/tests/test_remote_installation.sh"

# --- Read current version ---
CURRENT_VERSION=$(grep 'TRIDENT_VERSION=' "$CONSTANTS_FILE" | head -1 | cut -d'"' -f2)
echo -e "${CYAN}📦 Bumping version: ${YELLOW}$CURRENT_VERSION${CYAN} → ${GREEN}$NEW_VERSION${NC}"
echo ""

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo -e "${YELLOW}⚠️  Version is already $NEW_VERSION — nothing to change.${NC}"
    exit 0
fi

# --- 1. Update lib/git-trident-constants.sh ---
echo -e "  Updating ${CYAN}lib/git-trident-constants.sh${NC}..."
_sed_in_place "$CONSTANTS_FILE" "s/TRIDENT_VERSION=\".*\"/TRIDENT_VERSION=\"$NEW_VERSION\"/"

# --- 2. Update test assertions ---
echo -e "  Updating ${CYAN}tests/test_remote_installation.sh${NC}..."
_sed_in_place "$TEST_FILE" "s/\"$CURRENT_VERSION\"/\"$NEW_VERSION\"/g"

# --- 3. Verification ---
echo ""
echo -e "${GREEN}✓ Version files updated${NC}"
echo ""
echo "  Constants:"
echo -e "    $(grep 'TRIDENT_VERSION=' "$CONSTANTS_FILE")"
echo ""
echo "  Tests:"
grep -n "$NEW_VERSION" "$TEST_FILE" | while IFS= read -r line; do
    echo -e "    $line"
done
echo ""

# --- 4. Release flow (optional) ---
if [[ "$RELEASE_FLAG" == "--release" ]]; then
    echo -e "${YELLOW}🚀 Release mode: committing, tagging, and pushing...${NC}"
    echo ""

    cd "$PROJECT_ROOT"

    # Verify we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}❌ Not inside a Git repository.${NC}"
        exit 1
    fi

    # 1. Run build script to sync constants and verify build success
    echo -e "  Building project..."
    if ! bash "$PROJECT_ROOT/build.sh" >/dev/null 2>&1; then
        echo -e "${RED}❌ Build failed. Release aborted.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Project built and packaged successfully"

    # 2. Run all tests
    echo -e "  Running tests..."
    if ! bash "$PROJECT_ROOT/tests/run_all.sh" >/dev/null 2>&1; then
        echo -e "${RED}❌ Tests failed. Release aborted.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} All tests passed successfully"

    # Check for uncommitted changes beyond our bump
    git add -A
    git commit -m "wip: Bump version to $NEW_VERSION"
    echo -e "  ${GREEN}✓${NC} Committed: wip: Bump version to $NEW_VERSION"

    git push
    echo -e "  ${GREEN}✓${NC} Pushed to remote"

    git tag "v$NEW_VERSION"
    echo -e "  ${GREEN}✓${NC} Created tag: v$NEW_VERSION"

    git push origin "v$NEW_VERSION"
    echo -e "  ${GREEN}✓${NC} Pushed tag: v$NEW_VERSION"

    echo ""
    echo -e "${GREEN}✅ Release v$NEW_VERSION tagged and pushed successfully.${NC}"
else
    echo -e "${YELLOW}💡 To release, run:${NC}"
    echo -e "   ./scripts/bump-version.sh $NEW_VERSION --release"
fi
