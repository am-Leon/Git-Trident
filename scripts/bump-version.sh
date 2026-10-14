#!/bin/bash
# =============================================================================
# Git Trident — Version Bump Script
# =============================================================================
# Usage:
#   ./scripts/bump-version.sh <VERSION>              # Bump files locally only
#   ./scripts/bump-version.sh <VERSION> --release    # Bump + commit + tag + push
#
# Examples:
#   ./scripts/bump-version.sh 1.0.3
#   ./scripts/bump-version.sh 1.0.3 --release
#
# --release pushes a tag, and a pushed tag triggers a public GitHub Release.
# That is not reversible in any way that helps users who already fetched it, so
# everything that can be checked is checked BEFORE the first file is modified.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}❌ $1${NC}" >&2; exit 1; }

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

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}❌ Invalid version format: $version${NC}" >&2
        echo -e "   Expected: ${CYAN}MAJOR.MINOR.PATCH${NC} (e.g., 1.0.3)" >&2
        exit 1
    fi
}

# Returns 0 when $1 is strictly greater than $2. Field-by-field integer
# comparison; `sort -V` is a GNU extension and is absent on macOS.
version_gt() {
    local a="$1" b="$2"
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<< "$a"
    IFS=. read -r b1 b2 b3 <<< "$b"
    [ "$a1" -ne "$b1" ] && { [ "$a1" -gt "$b1" ]; return $?; }
    [ "$a2" -ne "$b2" ] && { [ "$a2" -gt "$b2" ]; return $?; }
    [ "$a3" -gt "$b3" ]
}

# Asks only when there is someone to ask. --yes (or GT_ASSUME_YES=true, the
# same switch the rest of the tool uses) answers in advance, which is what makes
# a release runnable from CI. Without a terminal and without that flag it fails
# loudly rather than blocking forever on a read that can never return.
confirm() {
    local prompt="$1" reply=""

    if [[ "${ASSUME_YES:-false}" == "true" ]] || [[ "${GT_ASSUME_YES:-false}" == "true" ]]; then
        echo -e "${CYAN}${prompt} → yes (--yes)${NC}"
        return 0
    fi

    if [ ! -t 0 ] && [ ! -e /dev/tty ]; then
        die "$prompt
   No terminal available to confirm. Re-run with --yes to proceed unattended."
    fi

    printf "%b" "${YELLOW}${prompt} [y/N]: ${NC}"
    if [ -e /dev/tty ]; then
        read -r reply </dev/tty || reply=""
    else
        read -r reply || reply=""
    fi
    case "$reply" in [Yy]|[Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

# --- Parse arguments ---
if [[ $# -lt 1 ]]; then
    echo -e "${YELLOW}Usage:${NC} ./scripts/bump-version.sh <VERSION> [--release]"
    echo ""
    echo "  VERSION     Semantic version (e.g., 1.0.3)"
    echo "  --release   Commit, tag, and push after bumping"
    echo "  --yes, -y   Do not prompt for confirmation (for unattended runs)"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  ./scripts/bump-version.sh 1.0.3"
    echo "  ./scripts/bump-version.sh 1.0.3 --release"
    exit 1
fi

NEW_VERSION="$1"
shift
validate_version "$NEW_VERSION"

RELEASE_FLAG=""
ASSUME_YES="${GT_ASSUME_YES:-false}"
while [ $# -gt 0 ]; do
    case "$1" in
        --release)      RELEASE_FLAG="--release" ;;
        --yes|-y)       ASSUME_YES=true ;;
        *)              die "Unknown option: $1" ;;
    esac
    shift
done

CONSTANTS_FILE="$PROJECT_ROOT/lib/git-trident-constants.sh"
TEST_FILE="$PROJECT_ROOT/tests/test_remote_installation.sh"
CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"
TAG="v$NEW_VERSION"

cd "$PROJECT_ROOT"

CURRENT_VERSION="$(grep 'TRIDENT_VERSION=' "$CONSTANTS_FILE" | head -1 | cut -d'"' -f2)"

# =============================================================================
# Preflight — every check that can fail runs before anything is written.
#
# The previous version edited two files, built, tested, `git add -A`'d and
# pushed before it ever looked at whether the tag already existed. A failure
# at that point left a pushed commit claiming a release that has no tag.
# =============================================================================
if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo -e "${YELLOW}⚠️  Version is already $NEW_VERSION — nothing to change.${NC}"
    exit 0
fi

if ! version_gt "$NEW_VERSION" "$CURRENT_VERSION"; then
    die "$NEW_VERSION is not newer than the current $CURRENT_VERSION.
   Publishing a lower version makes 'git trident version update' a downgrade
   for everyone already on $CURRENT_VERSION."
fi

if [[ "$RELEASE_FLAG" == "--release" ]]; then
    # Only the release path needs git. A plain local bump is just three file
    # edits and must work in a checkout-less copy of the tree.
    git rev-parse --git-dir >/dev/null 2>&1 || die "Not inside a Git repository."

    # A dirty tree means `git add -A` would sweep unrelated work into the
    # release commit — which is exactly what it used to do, despite a comment
    # claiming it was checking for that.
    if [[ -n "$(git status --porcelain)" ]]; then
        echo -e "${RED}❌ Working tree is not clean:${NC}" >&2
        git status --short >&2
        die "Commit or stash these before releasing."
    fi

    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        die "Tag $TAG already exists locally. Delete it or choose another version."
    fi

    if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
        die "Tag $TAG already exists on origin — that release is published."
    fi

    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    echo -e "${CYAN}Release target${NC}"
    echo -e "   branch : ${YELLOW}${CURRENT_BRANCH}${NC}"
    echo -e "   tag    : ${GREEN}${TAG}${NC}"
    echo -e "   commit : $(git log -1 --format='%h %s')"
    echo ""
    confirm "Tag and push a public release from '$CURRENT_BRANCH'?" \
        || die "Aborted — nothing was changed."
fi

echo -e "${CYAN}📦 Bumping version: ${YELLOW}$CURRENT_VERSION${CYAN} → ${GREEN}$NEW_VERSION${NC}"
echo ""

# =============================================================================
# Edits — every file touched here is recorded in CHANGED_FILES so the commit
# can stage exactly those, and nothing else.
# =============================================================================
CHANGED_FILES=()

echo -e "  Updating ${CYAN}lib/git-trident-constants.sh${NC}..."
_sed_in_place "$CONSTANTS_FILE" "s/TRIDENT_VERSION=\".*\"/TRIDENT_VERSION=\"$NEW_VERSION\"/"
CHANGED_FILES+=("$CONSTANTS_FILE")

echo -e "  Updating ${CYAN}tests/test_remote_installation.sh${NC}..."
# Scoped to lines that assert TRIDENT_VERSION. A blanket replace of every
# quoted X.Y.Z also rewrites unrelated fixtures — it once turned a prefixing
# test into "normalise(0.2.0) == v0.1.1", which passed review and failed CI.
# Dots are escaped so 0.1.1 cannot match 0x1y1.
CURRENT_VERSION_RE="$(printf '%s' "$CURRENT_VERSION" | sed 's/\./\\./g')"
_sed_in_place "$TEST_FILE" "/TRIDENT_VERSION/s/\"$CURRENT_VERSION_RE\"/\"$NEW_VERSION\"/g"
CHANGED_FILES+=("$TEST_FILE")

# Date the [Unreleased] heading. Without this the published release carries a
# changelog section still labelled "Unreleased", which is how a changelog stops
# being trusted.
if [[ -f "$CHANGELOG_FILE" ]]; then
    if grep -qE '^## \[.*\].*Unreleased' "$CHANGELOG_FILE"; then
        RELEASE_DATE="$(date +%Y-%m-%d)"
        echo -e "  Updating ${CYAN}CHANGELOG.md${NC} → [$NEW_VERSION] — $RELEASE_DATE"
        _sed_in_place "$CHANGELOG_FILE" \
            "s/^## \[.*\].*Unreleased.*$/## [$NEW_VERSION] — $RELEASE_DATE/"
        CHANGED_FILES+=("$CHANGELOG_FILE")
    else
        echo -e "  ${YELLOW}⚠️  CHANGELOG.md has no [Unreleased] heading — left untouched.${NC}"
    fi
fi

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

# =============================================================================
# Release
# =============================================================================
if [[ "$RELEASE_FLAG" == "--release" ]]; then
    echo -e "${YELLOW}🚀 Release mode: building, testing, tagging, pushing...${NC}"
    echo ""

    echo -e "  Building project..."
    bash "$PROJECT_ROOT/build.sh" >/dev/null 2>&1 \
        || die "Build failed. Release aborted — file edits are left in place for inspection."
    echo -e "  ${GREEN}✓${NC} Project built and packaged successfully"

    echo -e "  Running tests..."
    bash "$PROJECT_ROOT/tests/run_all.sh" >/dev/null 2>&1 \
        || die "Tests failed. Release aborted — file edits are left in place for inspection."
    echo -e "  ${GREEN}✓${NC} All tests passed successfully"

    # Stage ONLY what this script changed. `git add -A` committed whatever else
    # happened to be in the tree under a message that said "bump version".
    git add -- "${CHANGED_FILES[@]}"
    git commit -q -m "chore: Release $TAG"
    echo -e "  ${GREEN}✓${NC} Committed: chore: Release $TAG"

    # Annotated, so the tag carries an author and date of its own.
    git tag -a "$TAG" -m "Git Trident $TAG"
    echo -e "  ${GREEN}✓${NC} Created tag: $TAG"

    git push
    echo -e "  ${GREEN}✓${NC} Pushed to remote"

    # Last, and on its own: pushing the tag is what triggers the public release.
    git push origin "$TAG"
    echo -e "  ${GREEN}✓${NC} Pushed tag: $TAG"

    echo ""
    echo -e "${GREEN}✅ Release $TAG tagged and pushed — GitHub Actions will build the release.${NC}"
else
    echo -e "${YELLOW}💡 To release, run:${NC}"
    echo -e "   ./scripts/bump-version.sh $NEW_VERSION --release"
fi
