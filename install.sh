#!/usr/bin/env bash
# =============================================================================
# Git Trident Installer - Bash 5.0+ Professional Edition
# =============================================================================

# 1. AUTO-UPGRADE SHELL / VERSION CHECK
if ((BASH_VERSINFO[0] < 4)); then
    if [[ -x "/usr/local/bin/bash" ]]; then
        exec "/usr/local/bin/bash" "$0" "$@"
    elif [[ -x "/opt/homebrew/bin/bash" ]]; then
        exec "/opt/homebrew/bin/bash" "$0" "$@"
    else
        echo -e "\033[0;31m[ERROR]\033[0m This script requires Bash 4.0+."
        echo -e "Detected: $BASH_VERSION. Please 'brew install bash'."
        exit 1
    fi
fi

set -e
set -u

# =============================================================================
# PATH SETUP & ARGUMENT PARSING
# =============================================================================

PROJECT_FOLDER=".git-trident"
ACTION="install"
CUSTOM_PATH=""

# Improved Argument Parsing
if [[ $# -gt 0 ]]; then
    case "$1" in
        --uninstall)
            ACTION="uninstall"
            ;;
        --help|-h)
            echo "Usage: ./install.sh [CUSTOM_PATH] | --uninstall"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            CUSTOM_PATH="${1%/}"
            ;;
    esac
fi

# Define INSTALL_DIR based on input
if [[ -n "$CUSTOM_PATH" ]]; then
    if [[ "$CUSTOM_PATH" == */"$PROJECT_FOLDER" ]]; then
        INSTALL_DIR="$CUSTOM_PATH"
    else
        INSTALL_DIR="$CUSTOM_PATH/$PROJECT_FOLDER"
    fi
else
    INSTALL_DIR="$HOME/$PROJECT_FOLDER"
fi


# =============================================================================
# LOGGING & UI
# =============================================================================
declare -A UI=(
    [RED]='\033[0;31m' [GREEN]='\033[0;32m' [YELLOW]='\033[1;33m'
    [BLUE]='\033[0;34m' [NC]='\033[0m'
)

log_info()  { echo -e "${UI[GREEN]}[INFO]${UI[NC]} $1"; }
log_step()  { echo -e "${UI[BLUE]}[STEP]${UI[NC]} $1"; }
log_warn()  { echo -e "${UI[YELLOW]}[WARN]${UI[NC]} $1"; }
log_error() { echo -e "${UI[RED]}[ERROR]${UI[NC]} $1"; }
log_empty() { echo -e ""; }

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================
check_dependencies() {
    local missing_deps=()
    local dependencies=("git" "grep" "sed" "awk" "curl" "date" "tar")

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "\033[0;31m[ERROR]\033[0m Missing dependencies: ${missing_deps[*]}"
        echo "Please install them via your package manager (brew/apt/yum)."
        exit 1
    fi
}

BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"

# =============================================================================
# SAFE SCRIPT_DIR (handles piped execution: curl | bash)
# =============================================================================

# If BASH_SOURCE[0] is unset (piped execution), SCRIPT_DIR becomes empty string
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi

SUCCESS_FLAG=false
TEMP_DIR=""

# =============================================================================
# DETECT & HANDLE REMOTE INSTALLATION MODE (curl | bash)
# =============================================================================
GITHUB_REPO="am-Leon/Git-Trident"
INSTALL_VERSION="${INSTALL_VERSION:-latest}"

# Remote mode: empty SCRIPT_DIR OR local bin/git-trident not found
if [[ -z "$SCRIPT_DIR" ]] || [[ ! -f "$SCRIPT_DIR/bin/git-trident" ]]; then
    check_dependencies
    log_step "Remote execution detected. Preparing to download package..."

    TEMP_DIR=$(mktemp -d -t git-trident-install-XXXXXXXX)
    TARBALL_PATH="$TEMP_DIR/git-trident.tar.gz"

    if [[ -n "${LOCAL_TARBALL:-}" && -f "$LOCAL_TARBALL" ]]; then
        log_info "Testing Mode: Using local tarball instead of download: $LOCAL_TARBALL"
        cp "$LOCAL_TARBALL" "$TARBALL_PATH"
    else
        if [[ "$INSTALL_VERSION" == "latest" ]]; then
            DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/latest/download/git-trident.tar.gz"
        else
            DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$INSTALL_VERSION/git-trident.tar.gz"
        fi

        log_info "Downloading release package from: $DOWNLOAD_URL"

        if ! curl -fsSL "$DOWNLOAD_URL" -o "$TARBALL_PATH"; then
            log_error "Failed to download git-trident package."
            log_error "Please verify the GITHUB_REPO ('$GITHUB_REPO') and tag version ('$INSTALL_VERSION') are valid."
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    fi

    log_info "Extracting package..."
    mkdir -p "$TEMP_DIR/source"
    tar -xzf "$TARBALL_PATH" -C "$TEMP_DIR/source"

    SCRIPT_DIR="$TEMP_DIR/source"
fi

# =============================================================================
# PROFILE DETECTION (Prioritizes .zprofile for macOS)
# =============================================================================

detect_active_profile() {
    local shell_name
    shell_name=$(basename "$SHELL")
    local candidates=()

    if [[ "$shell_name" == "zsh" ]]; then
        candidates=("$HOME/.zprofile" "$HOME/.zshrc")
    else
        candidates=("$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile")
    fi

    for file in "${candidates[@]}"; do
        if [[ -f "$file" ]]; then
            echo "$file"
            return 0
        fi
    done

    local fallback="$HOME/.profile"
    [[ "$shell_name" == "zsh" ]] && fallback="$HOME/.zshrc"
    [[ "$shell_name" == "bash" ]] && fallback="$HOME/.bash_profile"
    touch "$fallback" && echo "$fallback"
}

# =============================================================================
# POST-INSTALLATION INSTRUCTIONS
# =============================================================================

show_post_install_instructions() {
    local profile=$1
    local global_config="$HOME/.git-trident-config"
    local project_template="$INSTALL_DIR/templates/git-trident-config"

    log_empty
    log_info "🎉 GIT TRIDENT INSTALLATION COMPLETE!"
    log_info "=========================================="
    log_info "📁 Installed to:      $INSTALL_DIR"
    log_info "📝 Profile updated:   $profile"
    log_info "⚙️  Global config:    $global_config"

    log_empty
    log_info "🔧 NEXT STEPS"
    log_info "=========================================="
    log_info "1. Restart your terminal or run:"
    log_info "     source $profile"

    log_empty
    log_info "2. Inside any Git project, initialize Git Trident:"
    log_info "     git trident config init"
    log_info "   This creates the project config and sets up hooks."

    log_empty
    log_info "3. Verify the installation:"
    log_info "     git trident -h"
    log_info "     git trident version"

    log_empty
    log_info "💡 CONFIGURATION NOTES"
    log_info "=========================================="
    log_info "• Global settings (auto-push, debug, security) → ~/.git-trident-config"
    log_info "• Project settings (branches, platforms, tags) → ./git-trident-config"
}

# =============================================================================
# CORE ACTIONS
# =============================================================================

exit_handler() {
    local exit_code=$?
    # Clean up temp folder if it exists
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    # Clean up incomplete installation directory on failure
    if [[ "$SUCCESS_FLAG" == "false" ]]; then
        log_error "Installation failed. Cleaning up..."
        [[ -d "$INSTALL_DIR" ]] && rm -rf -- "$INSTALL_DIR"
    fi
}
trap exit_handler EXIT INT TERM

uninstall() {
    log_warn "Starting uninstallation from: $INSTALL_DIR"
    local profile
    profile=$(detect_active_profile)

    # 1. Remove Installation Directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf -- "$INSTALL_DIR"
        log_info "✓ Removed directory: $INSTALL_DIR"
    fi

    # 2. Clean Shell Profile
    sed -i.bak '/# Git Trident/d' "$profile" 2>/dev/null || true
    sed -i.bak '/\.git-trident\/bin/d' "$profile" 2>/dev/null || true
    log_info "✓ Profile cleaned: $profile"

    # 3. Handle Global Config (with confirmation, safe for pipes)
    local global_config="$HOME/.git-trident-config"
    if [[ -f "$global_config" ]]; then
        local remove_config="n"
        if [ -t 0 ]; then
            echo -e -n "${UI[YELLOW]}[PROMPT]${UI[NC]} Remove global configuration file? (~/.git-trident-config) [y/N]: "
            read -r response
            remove_config="$response"
        fi

        if [[ "$remove_config" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            rm -f "$global_config"
            log_info "✓ Global configuration removed."
        else
            log_info "✓ Global configuration preserved."
        fi
    fi

    SUCCESS_FLAG=true
    log_info "Uninstallation complete. Please restart your terminal."
    exit 0
}

run_install() {
    log_step "Starting Deployment..."
    local profile
    profile=$(detect_active_profile)

    # 1. Safety Backup
    if [[ -d "$INSTALL_DIR" ]]; then
        log_info "Backing up existing installation to $BACKUP_DIR"
        cp -r -- "$INSTALL_DIR" "$BACKUP_DIR"
    fi

    # 2. Deploy Files
    mkdir -p "$INSTALL_DIR"/{bin,lib,templates,docs,hooks}
    cp -r "$SCRIPT_DIR"/bin/* "$INSTALL_DIR/bin/"
    cp -r "$SCRIPT_DIR"/lib/* "$INSTALL_DIR/lib/"
    [[ -d "$SCRIPT_DIR/templates" ]] && cp -r "$SCRIPT_DIR/templates"/* "$INSTALL_DIR/templates/"
    [[ -d "$SCRIPT_DIR/hooks" ]] && cp -r "$SCRIPT_DIR/hooks"/* "$INSTALL_DIR/hooks/"
    chmod +x "$INSTALL_DIR"/bin/*
    if [[ -d "$INSTALL_DIR/hooks" ]] && ls "$INSTALL_DIR/hooks"/* >/dev/null 2>&1; then
        chmod +x "$INSTALL_DIR"/hooks/*
    fi

    # 3. Global Config — deploy the global-only template
    if [[ ! -f "$HOME/.git-trident-config" ]]; then
        cp "$INSTALL_DIR/templates/git-trident-global-config" "$HOME/.git-trident-config"
        log_info "✓ Created default global config: ~/.git-trident-config"
    else
        log_info "• Global config already exists, skipping: ~/.git-trident-config"
    fi

    # 4. Path Update
    sed -i.bak '/# Git Trident/d' "$profile" 2>/dev/null || true
    sed -i.bak '/\.git-trident\/bin/d' "$profile" 2>/dev/null || true
    rm -f "${profile}.bak" 2>/dev/null || true
    echo -e "\n# Git Trident - Added $(date +%Y-%m-%d)\nexport PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$profile"

    # 5. Verification
    log_empty
    log_step "Finalizing..."
    export PATH="$INSTALL_DIR/bin:$PATH"
    if command -v git-trident >/dev/null 2>&1; then
        SUCCESS_FLAG=true
        show_post_install_instructions "$profile"
    else
        log_error "Installation verification failed."
        exit 1
    fi
}

# =============================================================================
# EXECUTION
# =============================================================================

if [[ "$ACTION" == "uninstall" ]]; then
    uninstall
else
    check_dependencies
    run_install
fi