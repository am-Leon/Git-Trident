#!/usr/bin/env bash
# =============================================================================
# Git Trident — Release Build Script
#
# Produces dist/git-trident.tar.gz, the artifact attached to a GitHub Release
# and fetched by install.sh.
#
# The archive is intentionally FLAT (bin/, lib/, … at the root, with no
# wrapping directory) because install.sh extracts it straight into the install
# root. Changing that layout breaks every existing client, including the
# `version update` path.
# =============================================================================
set -e
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
TARBALL_NAME="git-trident.tar.gz"
TARBALL="$DIST_DIR/$TARBALL_NAME"

# ---------------------------------------------------------------------------
# Logging — all of it, in one place. log_empty() used to be defined two thirds
# of the way down, in the middle of the output it formats.
# ---------------------------------------------------------------------------
log_info()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_step()  { echo -e "\033[0;34m[STEP]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
log_empty() { echo ""; }

# ---------------------------------------------------------------------------
# Contents of the release artifact.
#
# tests/ is deliberately absent: it is a development concern, and shipping it
# would roughly double the download for something no installed client runs.
# LICENSE is present because the MIT terms require the notice to travel with
# "all copies or substantial portions of the Software" — a tarball is a copy.
# ---------------------------------------------------------------------------
PACKAGE_DIRS="bin lib templates hooks completions docs"
PACKAGE_FILES="install.sh README.md LICENSE CHANGELOG.md"

# Members whose absence means the artifact is unusable; verified after writing.
REQUIRED_MEMBERS="bin/git-trident lib/git-trident-common.sh install.sh LICENSE"

# ---------------------------------------------------------------------------
# 1. Constants
# ---------------------------------------------------------------------------
if [ ! -f "$PROJECT_ROOT/lib/git-trident-constants.sh" ]; then
    log_error "Missing constants file: $PROJECT_ROOT/lib/git-trident-constants.sh"
    exit 1
fi
# shellcheck source=lib/git-trident-constants.sh
source "$PROJECT_ROOT/lib/git-trident-constants.sh"

# ---------------------------------------------------------------------------
# 2. Check install.sh agrees with the constants — do not rewrite it.
#
# This step used to `sed -i` install.sh to force the value into agreement. A
# build that edits tracked source is a build that can produce an artifact which
# matches nothing in git, and silently leaves the working tree dirty. (The
# substitution had also been dead for some time: it keyed off a trailing
# comment that install.sh no longer carries, so it matched nothing and the
# "✓ Synced" line it printed was false.)
# ---------------------------------------------------------------------------
log_step "Checking install.sh is in sync with constants..."
INSTALLER_REPO="$(grep -E '^GITHUB_REPO=' "$PROJECT_ROOT/install.sh" | head -1 | cut -d'"' -f2)"
if [ "$INSTALLER_REPO" != "$GITHUB_REPO" ]; then
    log_error "install.sh and lib/git-trident-constants.sh disagree:"
    log_error "    install.sh : GITHUB_REPO=\"$INSTALLER_REPO\""
    log_error "    constants  : GITHUB_REPO=\"$GITHUB_REPO\""
    log_empty
    log_error "Fix install.sh line $(grep -nE '^GITHUB_REPO=' "$PROJECT_ROOT/install.sh" | head -1 | cut -d: -f1) and build again."
    exit 1
fi
log_info "✓ GITHUB_REPO=\"$GITHUB_REPO\""

# ---------------------------------------------------------------------------
# 3. Stage
# ---------------------------------------------------------------------------
log_step "Preparing build environment..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

TEMP_BUILD_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEMP_BUILD_DIR"; }
trap cleanup EXIT

log_step "Staging package contents..."
for d in $PACKAGE_DIRS; do
    if [ ! -d "$PROJECT_ROOT/$d" ]; then
        log_error "Missing directory: $d"
        exit 1
    fi
    cp -R "$PROJECT_ROOT/$d" "$TEMP_BUILD_DIR/"
done
for f in $PACKAGE_FILES; do
    if [ ! -f "$PROJECT_ROOT/$f" ]; then
        log_error "Missing file: $f"
        exit 1
    fi
    cp "$PROJECT_ROOT/$f" "$TEMP_BUILD_DIR/"
done

# Development residue that must not reach users.
find "$TEMP_BUILD_DIR" -name ".DS_Store" -type f -delete 2>/dev/null || true
find "$TEMP_BUILD_DIR" -name "*.bak" -type f -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Pack
# ---------------------------------------------------------------------------
log_step "Building package tarball ($TARBALL_NAME)..."
( cd "$TEMP_BUILD_DIR" && tar -czf "$TARBALL" ./* )

# ---------------------------------------------------------------------------
# 5. Verify what was actually written.
#
# Everything above can succeed and still produce an archive that cannot be
# installed — a lost executable bit alone is enough, and that is exactly how
# "Permission denied" reached users before. So the artifact is unpacked into a
# clean directory and exercised, rather than trusted because tar exited 0.
# ---------------------------------------------------------------------------
log_step "Verifying the tarball..."

if ! tar -tzf "$TARBALL" >/dev/null 2>&1; then
    log_error "Tarball is not readable: $TARBALL"
    exit 1
fi

MEMBERS="$(tar -tzf "$TARBALL" | sed 's|^\./||')"
for member in $REQUIRED_MEMBERS; do
    if ! echo "$MEMBERS" | grep -qx "$member"; then
        log_error "Required member missing from tarball: $member"
        exit 1
    fi
done
log_info "✓ All required members present"

VERIFY_DIR="$(mktemp -d)"
tar -xzf "$TARBALL" -C "$VERIFY_DIR"

NOT_EXEC=""
for f in "$VERIFY_DIR"/bin/* "$VERIFY_DIR"/hooks/*; do
    [ -f "$f" ] || continue
    [ -x "$f" ] || NOT_EXEC="$NOT_EXEC  ${f#"$VERIFY_DIR"/}"$'\n'
done
if [ -n "$NOT_EXEC" ]; then
    log_error "Executable bit lost in the archive for:"
    echo "$NOT_EXEC"
    rm -rf "$VERIFY_DIR"
    exit 1
fi
log_info "✓ Executable bits preserved"

# Run the packaged binary from the unpacked tree. This catches a broken
# SCRIPT_DIR/GT_INSTALL_ROOT resolution, which only shows up outside the repo.
PACKED_VERSION="$("$VERIFY_DIR/bin/git-trident" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
rm -rf "$VERIFY_DIR"

if [ -z "$PACKED_VERSION" ]; then
    log_error "The packaged bin/git-trident could not report its version."
    exit 1
fi
if [ "$PACKED_VERSION" != "$TRIDENT_VERSION" ]; then
    log_error "Packaged version ($PACKED_VERSION) != constants ($TRIDENT_VERSION)"
    exit 1
fi
log_info "✓ Packaged binary runs and reports $PACKED_VERSION"

TARBALL_SIZE="$(ls -lh "$TARBALL" | awk '{print $5}')"
FILE_COUNT="$(echo "$MEMBERS" | grep -cv '/$' || true)"

log_empty
log_info "✓ Successfully built: $TARBALL"
log_info "  version: $TRIDENT_VERSION   size: $TARBALL_SIZE   files: $FILE_COUNT"

log_empty
log_info "🚀 Next steps for publishing:"
log_info "  To automate the entire release process (bump, test, build, commit, tag, and push),"
log_info "  run the following command:"
log_info "    ./scripts/bump-version.sh <NEW_VERSION> --release"
log_info "  Alternatively, to release manually:"
log_info "    1. Push your latest code changes to your GitHub repository."
log_info "    2. Create a new release tag (e.g. v1.0.0)."
log_info "    3. Upload '$TARBALL' as a release asset."
log_info "    4. Developers can then install the tool anywhere using the curl command!"
