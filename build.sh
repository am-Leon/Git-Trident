#!/usr/bin/env bash
# =============================================================================
# Git Trident — Release Build Script
# =============================================================================
set -e
set -u

# Core configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
TARBALL_NAME="git-trident.tar.gz"

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_step() { echo -e "\033[0;34m[STEP]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Source centralized framework constants
if [[ -f "$PROJECT_ROOT/lib/git-trident-constants.sh" ]]; then
    source "$PROJECT_ROOT/lib/git-trident-constants.sh"
else
    log_error "Missing constants file: $PROJECT_ROOT/lib/git-trident-constants.sh"
    exit 1
fi

# 1. Sync constants to installer and prepare dist directory
log_step "Syncing constants to installer..."
# Auto-patch GITHUB_REPO in install.sh to maintain single source of truth
if [[ -f "$PROJECT_ROOT/install.sh" ]]; then
    sed -i.bak "s|GITHUB_REPO=.* # USER can update this to their public repo|GITHUB_REPO=\"$GITHUB_REPO\" # USER can update this to their public repo|g" "$PROJECT_ROOT/install.sh"
    rm -f "$PROJECT_ROOT/install.sh.bak"
    log_info "✓ Synced GITHUB_REPO='$GITHUB_REPO' to install.sh"
fi

log_step "Preparing build environment..."
if [[ -d "$DIST_DIR" ]]; then
    rm -rf "$DIST_DIR"
fi
mkdir -p "$DIST_DIR"

# 2. Package release files
log_step "Building package tarball ($TARBALL_NAME)..."
# We create a temporary build folder to only collect the necessary files
TEMP_BUILD_DIR=$(mktemp -d)

# Copy run-time directories
cp -r "$PROJECT_ROOT/bin" "$TEMP_BUILD_DIR/"
cp -r "$PROJECT_ROOT/lib" "$TEMP_BUILD_DIR/"
cp -r "$PROJECT_ROOT/templates" "$TEMP_BUILD_DIR/"
cp -r "$PROJECT_ROOT/hooks" "$TEMP_BUILD_DIR/"
cp -r "$PROJECT_ROOT/docs" "$TEMP_BUILD_DIR/"
cp "$PROJECT_ROOT/install.sh" "$TEMP_BUILD_DIR/"
cp "$PROJECT_ROOT/README.md" "$TEMP_BUILD_DIR/"

# Clean up any development garbage like .DS_Store
find "$TEMP_BUILD_DIR" -name ".DS_Store" -type f -delete 2>/dev/null || true

# Compress files
cd "$TEMP_BUILD_DIR"
tar -czf "$DIST_DIR/$TARBALL_NAME" *

# Clean up temp build folder
rm -rf "$TEMP_BUILD_DIR"

log_info "✓ Successfully built: $DIST_DIR/$TARBALL_NAME"
log_empty() { echo ""; }
log_empty
log_info "🚀 Next steps for publishing:"
log_info "  1. Push your latest code changes to your GitHub repository."
log_info "  2. Go to your repository on GitHub -> Releases -> Create a new release."
log_info "  3. Set a version tag (e.g., v1.0.0)."
log_info "  4. Upload '$DIST_DIR/$TARBALL_NAME' as a binary asset to the release."
log_info "  5. Developers can now install your CLI anywhere using the curl command!"
