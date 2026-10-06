#!/usr/bin/env bash
# =============================================================================
# Git Trident Installer
# =============================================================================
# Runs on Bash 3.2+ — macOS (stock /bin/bash 3.2), Linux, and Windows Git Bash.
#
# This script previously re-exec'd into a Bash 4+ binary because of a single
# associative array. That broke the documented install path, because under
#   curl -fsSL ... | bash
# the script arrives on stdin, so "$0" is the interpreter path rather than a
# file, and the re-exec became "run the bash binary as a shell script":
#   /bin/bash: /bin/bash: cannot execute binary file
# Keeping this file Bash 3.2-clean removes the need for a shim entirely, and
# removes `brew install bash` from onboarding.
#
# NOTE: `set -u` is active below. On Bash 3.2, expanding an EMPTY array as
# "${arr[@]}" raises "unbound variable" (Bash 4.4+ does not). Always use the
# ${arr[@]+"${arr[@]}"} form for arrays that may be empty.
# =============================================================================

set -e
set -u

# =============================================================================
# PATH SETUP & ARGUMENT PARSING
# =============================================================================

PROJECT_FOLDER=".git-trident"
CUSTOM_PATH=""

# Improved Argument Parsing
if [[ $# -gt 0 ]]; then
    case "$1" in
        --help|-h)
            echo "Usage: ./install.sh [CUSTOM_PATH]"
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
# Plain scalars, not an associative array: `declare -A` is Bash 4.0+ and would
# break macOS's stock /bin/bash 3.2.
UI_RED='\033[0;31m'
UI_GREEN='\033[0;32m'
UI_YELLOW='\033[1;33m'
UI_BLUE='\033[0;34m'
UI_NC='\033[0m'

log_info()  { echo -e "${UI_GREEN}[INFO]${UI_NC} $1"; }
log_step()  { echo -e "${UI_BLUE}[STEP]${UI_NC} $1"; }
log_warn()  { echo -e "${UI_YELLOW}[WARN]${UI_NC} $1"; }
log_error() { echo -e "${UI_RED}[ERROR]${UI_NC} $1"; }
log_empty() { echo -e ""; }

# Cross-platform sed in-place editing helper for installation
_sed_in_place() {
    local file="$1"
    local script="$2"
    local os
    os=$(uname -s)

    if [[ "$os" == "Darwin" ]]; then
        sed -i '' "$script" "$file"
    else
        sed -i "$script" "$file"
    fi
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================
check_dependencies() {
    local missing_deps=()
    local dependencies=("git" "grep" "sed" "awk" "curl" "date" "tar")

    for dep in ${dependencies[@]+"${dependencies[@]}"}; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "\033[0;31m[ERROR]\033[0m Missing dependencies: ${missing_deps[*]+"${missing_deps[*]}"}"
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
    local os
    os=$(uname -s)

    if [[ -n "${MSYSTEM:-}" ]] || [[ "$os" == *"MINGW"* ]] || [[ "$os" == *"MSYS"* ]]; then
        candidates=("$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile")
    elif [[ "$shell_name" == "zsh" ]]; then
        candidates=("$HOME/.zprofile" "$HOME/.zshrc")
    else
        candidates=("$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile")
    fi

    local profile_path=""
    for file in ${candidates[@]+"${candidates[@]}"}; do
        if [[ -f "$file" ]]; then
            profile_path="$file"
            break
        fi
    done

    if [[ -z "$profile_path" ]]; then
        local fallback="$HOME/.profile"
        if [[ -n "${MSYSTEM:-}" ]] || [[ "$os" == *"MINGW"* ]] || [[ "$os" == *"MSYS"* ]]; then
            fallback="$HOME/.bash_profile"
        elif [[ "$shell_name" == "zsh" ]]; then
            fallback="$HOME/.zshrc"
        elif [[ "$shell_name" == "bash" ]]; then
            fallback="$HOME/.bash_profile"
        fi
        touch "$fallback"
        profile_path="$fallback"
    fi

    # Ensure profile path uses POSIX format if on MINGW/MSYS and cygpath is available
    if command -v cygpath >/dev/null 2>&1; then
        profile_path=$(cygpath -u "$profile_path")
    fi

    echo "$profile_path"
    return 0
}

# =============================================================================
# POST-INSTALLATION INSTRUCTIONS
# =============================================================================

show_post_install_instructions() {
    local profile=$1
    local global_config="$HOME/.git-trident-config"

    log_empty
    log_info "🎉 GIT TRIDENT INSTALLATION COMPLETE!"
    log_info "=========================================="
    log_info "📁 Installed to:      $INSTALL_DIR"
    log_info "📝 Profile updated:   $profile"
    log_info "⚙️  Global config:    $global_config"

    log_empty
    if [[ -d "$INSTALL_DIR/completions" ]]; then
        log_empty
        log_info "⌨️  SHELL COMPLETION (optional)"
        log_info "=========================================="
        log_info "• bash:  echo 'source $INSTALL_DIR/completions/git-trident.bash' >> ~/.bashrc"
        log_info "• zsh :  mkdir -p ~/.zfunc && cp $INSTALL_DIR/completions/_git-trident ~/.zfunc/"
        log_info "         then ensure ~/.zshrc has: fpath=(~/.zfunc \$fpath); autoload -Uz compinit; compinit"
    fi

    log_info "🔧 NEXT STEPS"
    log_info "=========================================="
    log_info "• Inside any Git project, initialize Git Trident:"
    log_info "     git trident config init"
    log_info "   This creates the project config and sets up hooks."

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
    # Capture the status FIRST: every command below overwrites $?.
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

    # Exit explicitly with the captured status.
    #
    # This is not a behaviour fix: bash already preserves the status that
    # triggered an EXIT trap unless the handler exits itself, and a failed
    # install exited 1 both before and after this change (verified). It makes
    # the contract explicit instead of implicit, and gives exit_code — which was
    # captured and then never used — an actual purpose.
    exit "$exit_code"
}
trap exit_handler EXIT INT TERM

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
    mkdir -p "$INSTALL_DIR"/{bin,lib,templates,docs,hooks,completions}
    cp -r "$SCRIPT_DIR"/bin/* "$INSTALL_DIR/bin/"
    cp -r "$SCRIPT_DIR"/lib/* "$INSTALL_DIR/lib/"
    [[ -d "$SCRIPT_DIR/templates" ]] && cp -r "$SCRIPT_DIR/templates"/* "$INSTALL_DIR/templates/"
    [[ -d "$SCRIPT_DIR/hooks" ]] && cp -r "$SCRIPT_DIR/hooks"/* "$INSTALL_DIR/hooks/"
    # docs/ and completions/ are packaged by build.sh; the directories were
    # being created and then left empty.
    [[ -d "$SCRIPT_DIR/docs" ]] && cp -r "$SCRIPT_DIR/docs"/* "$INSTALL_DIR/docs/" 2>/dev/null
    [[ -d "$SCRIPT_DIR/completions" ]] && cp -r "$SCRIPT_DIR/completions"/* "$INSTALL_DIR/completions/" 2>/dev/null
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
    _sed_in_place "$profile" '/# Git Trident/d' 2>/dev/null || true
    _sed_in_place "$profile" '/\.git-trident\/bin/d' 2>/dev/null || true
    echo -e "\n# Git Trident - Added $(date +%Y-%m-%d)\nexport PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$profile"

    # 5. Verification
    log_empty
    log_step "Finalizing..."
    export PATH="$INSTALL_DIR/bin:$PATH"
    if command -v git-trident >/dev/null 2>&1; then
        SUCCESS_FLAG=true
        show_post_install_instructions "$profile"

        # Clean up temp folder before executing shell
        if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
            rm -rf "$TEMP_DIR"
        fi

        if [ -t 0 ] && [ -t 1 ]; then
            # Interactive terminal — we can restart the shell to load the new PATH
            log_empty
            log_info "♻️  Restarting your shell to apply PATH changes..."
            exec "$SHELL" -l
        else
            # Piped execution (curl | bash) — cannot restart
            log_empty
            log_info "💡 If you face 'command not found', run: ${UI_GREEN}source $profile${UI_NC}"
        fi
    else
        log_error "Installation verification failed."
        exit 1
    fi
}

# =============================================================================
# EXECUTION
# =============================================================================

check_dependencies
run_install