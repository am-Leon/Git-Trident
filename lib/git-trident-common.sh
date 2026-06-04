#!/bin/bash
# Git Trident Common Functions - Core utilities and configuration
# Supports both single-environment and multi-platform modes

# =============================================================================
# INITIALIZATION AND CONFIGURATION
# =============================================================================

# Load system constants
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/git-trident-constants.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/git-trident-constants.sh"
fi

# Configuration state tracking
CONFIG_LOADED=${CONFIG_LOADED:-false}
CONFIG_SOURCE=${CONFIG_SOURCE:-"none"}
CONFIG_VALIDATION_MODE=${CONFIG_VALIDATION_MODE:-"strict"}

# Required configuration variables (single-environment mode)
REQUIRED_CONFIG_VARS=(
    "PRODUCTION_BRANCH"
    "STAGING_BRANCH"
    "DEVELOP_BRANCH"
    "REMOTE"
    "STAGING_TAG_PREFIX"
    "PRODUCTION_TAG_PREFIX"
)

# Optional configuration variables with defaults
OPTIONAL_CONFIG_VARS=(
    "REQUIRE_CONFIRMATION=true"
    "CONFLICT_STRATEGY=interactive"
    "DEBUG=false"
    "REMOTE_TAG_CACHE_DURATION=300"
    "REQUIRE_CLEAN_WORKING_TREE=true"
    "VALIDATE_REMOTE_CONNECTIVITY=true"
    "CONFIG_VALIDATION_MODE=strict"
    # Multi-platform configuration
    "PLATFORM_SPECIFIC_TAGS=false"
    "PLATFORMS="
    "COMMON_PLATFORMS="
    "INDEPENDENT_PLATFORMS="
    # Branch prefixes
    "RELEASE_STAGING_PREFIX=release/stg/"
    "RELEASE_PRODUCTION_PREFIX=release/prod/"
    "HOTFIX_STAGING_PREFIX=hotfix/stg/"
    "HOTFIX_PRODUCTION_PREFIX=hotfix/prod/"
    # Git hooks configuration
    "HOOKS_ENABLED=false"
    "GIT_TRIDENT_SKIP_HOOKS=false"
    "HOOK_COMMIT_MSG_ENABLED=true"
    "COMMIT_PREFIXES=wip|fix|feat|enhance|cmd"
    "COMMIT_PREFIX_DESCRIPTIONS=Work In Progress|Bug Fixes|New Features|Enhancements|Commands"
    "COMMIT_PLATFORM_PREFIX_FORMAT=[platform]"
    "REQUIRE_CAPITAL_START=true"
    "MIN_WORD_COUNT=3"
    "CMD_MIN_WORD_COUNT=2"
    # Enhancement toggles
    "AUTO_PUSH_ON_FINISH=false"
    "DELETE_BRANCH_ON_FINISH=true"
    "STAGING_TAG_SUFFIX=-rc-"
    # Changelog & Release Notes
    "CHANGELOG_QA_EXCLUDED_PREFIXES="
    "CHANGELOG_RELEASE_EXCLUDED_PREFIXES=wip|cmd"
    "CHANGELOG_WEBHOOK_URL="
    "CHANGELOG_WEBHOOK_AUTH="
    "CHANGELOG_WEBHOOK_FORMAT=slack"
)

# Keys that belong ONLY in the global config (~/$GLOBAL_CONFIG_FILE_NAME).
# If any of these are found in a project config file they are ignored and a
# warning is emitted so the developer knows where to move them.
GLOBAL_ONLY_CONFIG_KEYS=(
    "AUTO_PUSH_ON_FINISH"
    "DELETE_BRANCH_ON_FINISH"
    "REQUIRE_CONFIRMATION"
    "REQUIRE_CLEAN_WORKING_TREE"
    "VALIDATE_REMOTE_CONNECTIVITY"
    "REMOTE_TAG_CACHE_DURATION"
    "CONFIG_VALIDATION_MODE"
    "DEBUG"
    "HOOKS_ENABLED"
    "GIT_TRIDENT_SKIP_HOOKS"
)

# =============================================================================
# COLOR AND LOGGING UTILITIES
# =============================================================================

# Color output (with fallback for non-TTY)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_empty() { echo -e "${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1" >&2; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $1" >&2 || true; }

# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================

# ---------------------------------------------------------------------------
# _source_config_file  — internal helper
# Sources a shell config file and returns 0 on success.
# ---------------------------------------------------------------------------
_source_config_file() {
    local config_file="$1"
    set -a
    # shellcheck source=/dev/null
    source "$config_file"
    local status=$?
    set +a
    return $status
}

# ---------------------------------------------------------------------------
# _warn_global_only_keys_in_project_config
# Scans a project config file for keys that belong only in the global config
# and prints a warning for each one found.
# ---------------------------------------------------------------------------
_warn_global_only_keys_in_project_config() {
    local project_file="$1"
    local warned=false

    for key in "${GLOBAL_ONLY_CONFIG_KEYS[@]}"; do
        # Match lines like:  KEY=...  or  export KEY=...
        if grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$project_file" 2>/dev/null; then
            if [[ "$warned" == "false" ]]; then
                log_warn "⚠️  Project config contains GLOBAL-ONLY keys (they will be ignored):"
                log_warn "   File: $project_file"
                log_warn "   Move these to: ~/$GLOBAL_CONFIG_FILE_NAME"
                warned=true
            fi
            log_warn "   - $key"
        fi
    done
}

# ---------------------------------------------------------------------------
# load_project_config
# Layered config loading:
#   1. Global  (~/$GLOBAL_CONFIG_FILE_NAME)  — loaded first (baseline)
#   2. Project (./$CONFIG_FILE_NAME or ./.$CONFIG_FILE_NAME)
#              — overlays project-specific keys on top of global values
# Global-only keys set in a project file are warned about and effectively
# overridden back to the global value after the project file is sourced.
# ---------------------------------------------------------------------------
load_project_config() {
    # Prevent duplicate configuration loading within the same session
    if [[ "$CONFIG_LOADED" == "true" ]]; then
        log_debug "Configuration already loaded from: $CONFIG_SOURCE"
        return 0
    fi

    # ── Guard 1: Are we inside a Git repository? ──
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        if [[ "${SUPPRESS_CONFIG_ERRORS:-false}" != "true" ]]; then
            log_error "❌ Not inside a Git repository."
            log_error "   Git Trident only works inside a Git project."
            log_error "   Please navigate to a Git repository and try again."
        fi
        return 1
    fi

    local global_config="$HOME/$GLOBAL_CONFIG_FILE_NAME"
    local project_config_files=(
        "./$CONFIG_FILE_NAME"    # Project root (explicit, committed)
        "./.$CONFIG_FILE_NAME"   # Project root (hidden / git ignored)
    )

    # ------------------------------------------------------------------
    # Step 1 — Load the global config (provides machine-level defaults)
    # ------------------------------------------------------------------
    local global_loaded=false
    if [[ -f "$global_config" ]]; then
        log_debug "Loading global configuration from: $global_config"
        if _source_config_file "$global_config"; then
            global_loaded=true
            log_debug "✓ Global configuration loaded: $global_config"
        else
            log_warn "Failed to source global config: $global_config (continuing)"
        fi
    else
        log_debug "Global config not found: $global_config"
    fi

    # Snapshot global-only values so we can restore them after the project
    # file is sourced (project file must not override these).
    for _key in "${GLOBAL_ONLY_CONFIG_KEYS[@]}"; do
        eval "local _global_snapshot_$_key=\"\${!_key:-}\""
    done

    # ------------------------------------------------------------------
    # Step 2 — Overlay the project config (if present)
    # ------------------------------------------------------------------
    local project_file=""
    for candidate in "${project_config_files[@]}"; do
        if [[ -f "$candidate" ]]; then
            project_file="$candidate"
            break
        fi
    done

    local project_loaded=false
    if [[ -n "$project_file" ]]; then
        log_debug "Loading project configuration from: $project_file"

        # Warn if project file contains global-only keys
        _warn_global_only_keys_in_project_config "$project_file"

        if _source_config_file "$project_file"; then
            project_loaded=true
            log_debug "✓ Project configuration loaded: $project_file"
        else
            log_error "Failed to source project config: $project_file"
            return 1
        fi

        # Restore global-only values so project file cannot override them
        for _key in "${GLOBAL_ONLY_CONFIG_KEYS[@]}"; do
            eval "local _global_val=\"\${_global_snapshot_$_key:-}\""
            if [[ -n "$_global_val" ]]; then
                export "$_key"="$_global_val"
                log_debug "Restored global-only key: $_key=${_global_val}"
            fi
        done
    fi

    # ------------------------------------------------------------------
    # Step 3 — Must have at least one config file
    # ------------------------------------------------------------------
    if [[ "$global_loaded" == "false" && "$project_loaded" == "false" ]]; then
        if [[ "${SUPPRESS_CONFIG_ERRORS:-false}" != "true" ]]; then
            log_error "❌ No valid configuration files found!"
            log_error "   Git Trident requires a configuration file to operate."
            log_empty ""
            log_error "💡 Please create a configuration file:"
            log_error "   - Project-specific : ./$CONFIG_FILE_NAME"
            log_error "   - Global (machine) : ~/$GLOBAL_CONFIG_FILE_NAME  (installed automatically)"
            log_empty ""
            log_error "📝 Re-run the installer, or copy the templates manually:"
            log_error "   Global  : cp \"\$HOME/$PROJECT_DIR_NAME/templates/git-trident-global-config\" ~/$GLOBAL_CONFIG_FILE_NAME"
            log_error "   Project : cp \"\$HOME/$PROJECT_DIR_NAME/templates/git-trident-config\" ./$CONFIG_FILE_NAME"
        fi
        return 1
    fi

    # ── Guard 2: Does a project config exist? ──
    if [[ "$project_loaded" == "false" ]]; then
        if [[ "${SUPPRESS_CONFIG_ERRORS:-false}" != "true" ]]; then
            log_error "❌ No project configuration file found."
            log_error "   Git Trident requires a project config to operate in this repository."
            log_empty ""
            log_error "💡 Run the following command to initialize your project config:"
            log_error "     git trident config init"
            log_empty ""
            log_error "   This creates ./git-trident-config with your project's branch names,"
            log_error "   tag prefixes, and workflow settings."
        fi
        return 1
    fi

    # Record the primary source for diagnostics
    if [[ -n "$project_file" ]]; then
        export CONFIG_SOURCE="$project_file (+ $global_config)"
    else
        export CONFIG_SOURCE="$global_config"
    fi
    export CONFIG_LOADED=true

    # Set validation mode from whichever config set it, or default to strict
    export CONFIG_VALIDATION_MODE="${CONFIG_VALIDATION_MODE:-strict}"

    # ------------------------------------------------------------------
    # Step 4 — Validate & apply defaults
    # ------------------------------------------------------------------
    if validate_config; then
        log_debug "✓ Configuration validated successfully"
        setup_optional_config_defaults
        return 0
    else
        if [[ "$CONFIG_VALIDATION_MODE" == "strict" ]]; then
            if [[ "${SUPPRESS_CONFIG_ERRORS:-false}" != "true" ]]; then
                log_error "Configuration validation failed. Source: $CONFIG_SOURCE"
            fi
            return 1
        else
            if [[ "${SUPPRESS_CONFIG_ERRORS:-false}" != "true" ]]; then
                log_warn "Configuration has validation issues (relaxed mode). Source: $CONFIG_SOURCE"
            fi
            setup_optional_config_defaults
            return 0
        fi
    fi
}

# Validate configuration based on current mode
validate_config() {
    local errors=()

    # Validate required configuration for single-environment mode
    for var in "${REQUIRED_CONFIG_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            errors+=("Required configuration missing: $var")
        fi
    done

    # Validate multi-platform configuration if enabled
    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then
        validate_platform_classification "errors"
    fi

    # Show errors based on validation mode
    if [[ ${#errors[@]} -gt 0 ]]; then
        if [[ "${SUPPRESS_CONFIG_ERRORS:-false}" != "true" ]]; then
            log_error "Configuration validation failed:"
            for error in "${errors[@]}"; do
                log_error "  - $error"
            done
            log_empty ""
            log_info "Configuration source: $CONFIG_SOURCE"
            log_info "Please fix your configuration file."

            # Show configuration help from centralized help system
            if [ -f "$SCRIPT_DIR/git-trident-help.sh" ]; then
                source "$SCRIPT_DIR/git-trident-help.sh"
                show_config_help
            fi
        fi

        # Return non-zero only in strict mode
        if [[ "${CONFIG_VALIDATION_MODE:-strict}" == "strict" ]]; then
            return 1
        fi
    fi

    return 0
}

# Validate platform classification configuration
validate_platform_classification() {
    local errors_ref_name="$1"  # Name of the errors array

    log_debug "Validating platform classification..."

    # Check that PLATFORMS is set
    if [[ -z "${PLATFORMS:-}" ]]; then
        eval "$errors_ref_name+=(\"PLATFORMS cannot be empty when PLATFORM_SPECIFIC_TAGS=true\")"
        return
    fi

    # Check that COMMON_PLATFORMS is set
    if [[ -z "${COMMON_PLATFORMS:-}" ]]; then
        eval "$errors_ref_name+=(\"COMMON_PLATFORMS cannot be empty when PLATFORM_SPECIFIC_TAGS=true\")"
    fi

    # Check that INDEPENDENT_PLATFORMS is set
    if [[ -z "${INDEPENDENT_PLATFORMS:-}" ]]; then
        eval "$errors_ref_name+=(\"INDEPENDENT_PLATFORMS cannot be empty when PLATFORM_SPECIFIC_TAGS=true\")"
    fi

    # Validate no duplicates within COMMON_PLATFORMS
    validate_no_duplicates_within_list "$COMMON_PLATFORMS" "COMMON_PLATFORMS" "$errors_ref_name"

    # Validate no duplicates within INDEPENDENT_PLATFORMS
    validate_no_duplicates_within_list "$INDEPENDENT_PLATFORMS" "INDEPENDENT_PLATFORMS" "$errors_ref_name"

    # Validate no duplicates between COMMON and INDEPENDENT
    validate_no_cross_duplicates "$errors_ref_name"

    # Validate PLATFORMS contains exactly COMMON + INDEPENDENT
    validate_platforms_completeness "$errors_ref_name"

    # Validate all platform names
    validate_all_platform_names "$errors_ref_name"
}

# Helper: Validate no duplicates within a list
validate_no_duplicates_within_list() {
    local platforms="$1"
    local list_name="$2"
    local errors_ref_name="$3"

    # If empty list, nothing to check
    if [[ -z "$platforms" ]]; then
        return 0
    fi

    # Convert to array and check for duplicates
    local -a platform_array
    IFS=' ' read -r -a platform_array <<< "$platforms"

    local -a unique_array
    local -a duplicates

    for platform in "${platform_array[@]}"; do
        local found=false
        # Check if platform already exists in unique_array
        for unique_platform in "${unique_array[@]}"; do
            if [[ "$unique_platform" == "$platform" ]]; then
                found=true
                duplicates+=("$platform")
                break
            fi
        done

        if [[ "$found" == "false" ]]; then
            unique_array+=("$platform")
        fi
    done

    if [[ ${#duplicates[@]} -gt 0 ]]; then
        eval "$errors_ref_name+=(\"Duplicate platforms in $list_name: ${duplicates[*]}\")"
    fi
}

# Helper: Validate no duplicates between COMMON and INDEPENDENT
validate_no_cross_duplicates() {
    local errors_ref_name="$1"

    # Check for platforms that exist in both lists
    local -a duplicates_array=()

    for common_platform in $COMMON_PLATFORMS; do
        for independent_platform in $INDEPENDENT_PLATFORMS; do
            if [[ "$common_platform" == "$independent_platform" ]]; then
                duplicates_array+=("$common_platform")
            fi
        done
    done

    if [[ ${#duplicates_array[@]} -gt 0 ]]; then
        local duplicates_string="${duplicates_array[*]}"
        eval "$errors_ref_name+=(\"Platforms cannot be in both COMMON_PLATFORMS and INDEPENDENT_PLATFORMS: $duplicates_string\")"
    fi
}

# Helper: Validate PLATFORMS contains exactly COMMON + INDEPENDENT
validate_platforms_completeness() {
    local errors_ref_name="$1"

    # Combine COMMON and INDEPENDENT platforms
    local combined_platforms="$COMMON_PLATFORMS $INDEPENDENT_PLATFORMS"
    combined_platforms=$(echo "$combined_platforms" | xargs)  # Trim

    # Sort both lists for comparison
    local sorted_platforms=$(echo "$PLATFORMS" | tr ' ' '\n' | sort | xargs)
    local sorted_combined=$(echo "$combined_platforms" | tr ' ' '\n' | sort | xargs)

    # Check if they're equal
    if [[ "$sorted_platforms" != "$sorted_combined" ]]; then
        eval "$errors_ref_name+=(\"PLATFORMS must contain exactly COMMON_PLATFORMS + INDEPENDENT_PLATFORMS\")"
        eval "$errors_ref_name+=(\"  PLATFORMS: $PLATFORMS\")"
        eval "$errors_ref_name+=(\"  COMMON + INDEPENDENT: $combined_platforms\")"

        # Find specific differences
        local platforms_in_plf_only=$(comm -13 <(echo "$sorted_combined" | tr ' ' '\n') <(echo "$sorted_platforms" | tr ' ' '\n') | xargs)
        local platforms_in_combined_only=$(comm -23 <(echo "$sorted_combined" | tr ' ' '\n') <(echo "$sorted_platforms" | tr ' ' '\n') | xargs)

        if [[ -n "$platforms_in_plf_only" ]]; then
            eval "$errors_ref_name+=(\"  Platforms only in PLATFORMS: $platforms_in_plf_only\")"
        fi

        if [[ -n "$platforms_in_combined_only" ]]; then
            eval "$errors_ref_name+=(\"  Platforms missing from PLATFORMS: $platforms_in_combined_only\")"
        fi
    fi
}

# Helper: Validate all platform names
validate_all_platform_names() {
    local errors_ref_name="$1"

    local all_platforms="$COMMON_PLATFORMS $INDEPENDENT_PLATFORMS"

    for platform in $all_platforms; do
        if [[ ! "$platform" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
            eval "$errors_ref_name+=(\"Invalid platform name: '$platform'. Must start with letter and contain only letters, numbers, hyphens, or underscores.\")"
        fi
    done
}

# Validate platform-specific configuration
validate_platform_config() {
    local errors_ref_name="$1"  # Name of the errors array

    # Validate PLATFORMS is set and not empty
    if [[ -z "${PLATFORMS:-}" ]]; then
        eval "$errors_ref_name+=(\"PLATFORMS cannot be empty when PLATFORM_SPECIFIC_TAGS=true\")"
        return
    fi

    # Validate PLATFORMS is a space-separated list
    if [[ ! "$PLATFORMS" =~ ^[a-zA-Z0-9_-]+( [a-zA-Z0-9_-]+)*$ ]]; then
        eval "$errors_ref_name+=(\"PLATFORMS must be a space-separated list of platform names\")"
        eval "$errors_ref_name+=(\"Example: PLATFORMS=\\\"android ios web\\\"\")"
        return
    fi
    
    # Log platform configuration
    log_debug "Platform-specific mode enabled"
    log_debug "Supported platforms: $PLATFORMS"
    log_debug "Common platforms: $COMMON_PLATFORMS"
    log_debug "Independent platforms: $INDEPENDENT_PLATFORMS"

    # Validate each platform name
    for platform in $PLATFORMS; do
        if [[ ! "$platform" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
            eval "$errors_ref_name+=(\"Invalid platform name: '$platform'. Must start with letter and contain only letters, numbers, hyphens, or underscores.\")"
        fi
    done
}

# Setup optional configuration defaults
setup_optional_config_defaults() {
    for optional_var in "${OPTIONAL_CONFIG_VARS[@]}"; do
        local var_name="${optional_var%=*}"
        local default_value="${optional_var#*=}"
        
        if [[ -z "${!var_name:-}" ]]; then
            export "$var_name"="$default_value"
            log_debug "Set default for optional $var_name: $default_value"
        else
            export "$var_name"="${!var_name}"
        fi
    done
}

# Assert that configuration is loaded
assert_config_loaded() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        log_error "❌ Configuration not loaded. Git Trident cannot operate without a configuration file."
        log_error "   Please create a configuration file and try again."
        exit 1
    fi
}

# =============================================================================
# PLATFORM UTILITIES
# =============================================================================

# Check if platform-specific mode is enabled
is_platform_specific_mode() {
    [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]
}

# Get list of platforms as array
get_platforms_array() {
    if is_platform_specific_mode && [[ -n "${PLATFORMS:-}" ]]; then
        echo "$PLATFORMS"  # Return as space-separated string
    else
        echo ""
    fi
}

# Check if a platform is common/shared
is_common_platform() {
    local platform="$1"

    if ! is_platform_specific_mode; then
        log_error "Platform classification requested but not in platform-specific mode"
        return 1
    fi

    # Use regex pattern to check if platform is in COMMON_PLATFORMS
    [[ " $COMMON_PLATFORMS " =~ " $platform " ]]
}

# Check if a platform is independent
is_independent_platform() {
    local platform="$1"

    if ! is_platform_specific_mode; then
        log_error "Platform classification requested but not in platform-specific mode"
        return 1
    fi

    # Use regex pattern to check if platform is in INDEPENDENT_PLATFORMS
    [[ " $INDEPENDENT_PLATFORMS " =~ " $platform " ]]
}

# Get all dependent platforms for a common platform
# Returns all INDEPENDENT_PLATFORMS (since common → all independent)
get_dependent_platforms() {
    if ! is_platform_specific_mode; then
        log_error "Cannot get dependent platforms in single-environment mode"
        echo ""
        return 1
    fi

    echo "$INDEPENDENT_PLATFORMS"
}

# Get platform type (common or independent)
get_platform_type() {
    local platform="$1"

    if ! is_platform_specific_mode; then
        echo "legacy"
        return 0
    fi

    if is_common_platform "$platform"; then
        echo "common"
    elif is_independent_platform "$platform"; then
        echo "independent"
    else
        echo "unknown"
        return 1
    fi
}

# Validate a platform name
validate_platform() {
    local platform="$1"

    if ! is_platform_specific_mode; then
        log_error "Platform validation requested but PLATFORM_SPECIFIC_TAGS is false"
        return 1
    fi

    if [[ -z "$platform" ]]; then
        log_error "Platform cannot be empty in platform-specific mode"
        return 1
    fi

    # Check if platform exists in PLATFORMS
    for p in $PLATFORMS; do
        if [[ "$p" == "$platform" ]]; then
            return 0
        fi
    done

    return 1
}

validate_platform_parameter() {
    local platform="$1"
    local context="$2"

    if ! is_platform_specific_mode; then
        log_error "Platform parameter '$platform' provided but not in platform-specific mode"
        log_info "Set PLATFORM_SPECIFIC_TAGS=true in configuration to enable multi-platform mode"
        return 1
    fi

    if [ -z "$platform" ]; then
        log_error "Platform parameter is required for $context in platform-specific mode"
        log_info "Supported platforms: $PLATFORMS"
        return 1
    fi

    if ! validate_platform "$platform"; then
        log_error "Invalid platform for $context: $platform"
        return 1
    fi

    return 0
}

# =============================================================================
# GIT OPERATION CHECKS
# =============================================================================

# Run pre-operation checks
pre_operation_checks() {
    local operation="${1:-unknown}"

    log_info "🔍 Running pre-operation checks for: $operation"

    # Verify configuration is loaded
    assert_config_loaded

    # Verify we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        return 1
    fi

    # Verify remote exists
    if ! git remote get-url "$REMOTE" > /dev/null 2>&1; then
        log_error "Remote '$REMOTE' not configured"
        log_info "Available remotes: $(git remote | tr '\n' ' ')"
        return 1
    fi

    # Validate remote connectivity if enabled
    if [[ "${VALIDATE_REMOTE_CONNECTIVITY:-true}" == "true" ]]; then
        log_debug "Validating remote connectivity..."
        if ! git ls-remote "$REMOTE" > /dev/null 2>&1; then
            log_error "Cannot connect to remote: $REMOTE"
            return 1
        fi
    fi

    log_info "✓ All pre-operation checks passed"
    return 0
}

# Assert working tree is clean
assert_clean_working_tree() {
    if [[ "${REQUIRE_CLEAN_WORKING_TREE:-true}" == "true" ]]; then
        if ! git diff-index --quiet HEAD --; then
            log_error "Working tree has uncommitted changes. Please commit or stash them first."
            exit 1
        fi
    fi
}

# =============================================================================
# GIT LOG UTILITIES
# =============================================================================

# Count commits in range
git_log_count() {
    local range_spec="$1"
    git log --oneline "$range_spec" 2>/dev/null | wc -l | tr -d ' '
}

# Format git log output
git_log_formatted() {
    local range_spec="$1"
    local max_commits="${2:-10}"  # Default to 10 commits if not specified

    if [[ "$max_commits" -le 0 ]]; then
        return 0
    fi

    # Use colored format for better readability
    git log --pretty=format:"%C(red)%h %C(green)%s" "$range_spec" -n "$max_commits" 2>/dev/null
}

# =============================================================================
# BRANCH AND TAG UTILITIES
# =============================================================================

# Check if branch exists
check_branch_exists() {
    git show-ref --verify --quiet "refs/heads/$1"
}

# Get current branch
get_current_branch() {
    git branch --show-current 2>/dev/null || git symbolic-ref --short HEAD 2>/dev/null
}

# Check if it's a valid git reference (branch, tag, or commit)
is_valid_tag() {
    git rev-parse "$1" >/dev/null 2>&1
}

# Show available tags for environment
show_available_tags() {
    local environment="$1"

    case "$environment" in
        "staging")
            log_info "Available staging tags:"
            git tag -l "${STAGING_TAG_PREFIX}*" | sort -V
            ;;
        "production")
            log_info "Available production tags:"
            git tag -l "${PRODUCTION_TAG_PREFIX}*" | sort -V
            ;;
        *)
            log_error "Invalid environment: $environment (must be 'staging' or 'production')"
            return 1
            ;;
    esac
}

# =============================================================================
# USER INTERACTION UTILITIES
# =============================================================================

# Confirm action with user
confirm_action() {
    local message="$1"
    local default="${2:-false}"

    # Respect REQUIRE_CONFIRMATION (primary developer tool)
    if [[ "$REQUIRE_CONFIRMATION" == "false" ]]; then
        log_debug "Auto-confirming action due to REQUIRE_CONFIRMATION=false: $message"
        return 0
    fi

    while true; do
        if [[ "$default" == "true" ]]; then
            read -p "$message [Y/n]: " yn
            case "${yn:-Y}" in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) log_empty "Please answer yes or no.";;
            esac
        else
            read -p "$message [y/N]: " yn
            case "${yn:-N}" in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) log_empty "Please answer yes or no.";;
            esac
        fi
    done
}

# Force confirmation from user — always prompts even if REQUIRE_CONFIRMATION=false.
# Use this for safety-critical actions that MUST have human review,
# e.g. resolving merge conflicts when CONFLICT_STRATEGY=interactive.
force_confirm_action() {
    local message="$1"
    local default="${2:-false}"

    while true; do
        if [[ "$default" == "true" ]]; then
            read -p "$message [Y/n]: " yn
            case "${yn:-Y}" in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) log_empty "Please answer yes or no.";;
            esac
        else
            read -p "$message [y/N]: " yn
            case "${yn:-N}" in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) log_empty "Please answer yes or no.";;
            esac
        fi
    done
}

# Delete remote branch if it exists
delete_remote_branch_if_exists() {
    local branch_name="$1"
    local remote="${2:-$REMOTE}"

    if git ls-remote --heads "$remote" "$branch_name" | grep -q "$branch_name"; then
        log_info "🗑 Deleting remote branch: $remote/$branch_name"
        git push "$remote" --delete "$branch_name" >/dev/null 2>&1 || log_warn "Failed to delete remote branch $branch_name"
    fi
}

# Cleanup local and remote branch after completion
cleanup_branch() {
    local branch_name="$1"
    local branch_type="$2" # e.g., "release" or "hotfix"

    if [[ "$DELETE_BRANCH_ON_FINISH" == "true" ]]; then
        log_info "🧹 Cleaning up $branch_type branch: $branch_name"
        
        # Delete from remote if exists
        delete_remote_branch_if_exists "$branch_name"
        
        # Delete locally
        git branch -d "$branch_name" >/dev/null 2>&1 || log_warn "Could not delete local branch $branch_name (not fully merged?)"
    fi
}

# Auto push changes to remote
auto_push_if_enabled() {
    local version="$1"
    if [[ "$AUTO_PUSH_ON_FINISH" == "true" ]]; then
        log_info "🚀 Automatically pushing to $REMOTE..."

        # Build command array
        local cmd=(git trident push-all)

        # Only add platform argument if in platform-specific mode
        if is_platform_specific_mode; then
            cmd+=(-p "$(extract_platform_from_version "$version")")
        fi

        # Execute the command
        "${cmd[@]}"
    fi
}

# =============================================================================
# MERGE AND SYNC UTILITIES
# =============================================================================

# Show changes between branches
show_changes() {
    local source_ref="$1"  # Could be branch, tag, or commit
    local target_branch="$2"
    local max_commits="${3:-10}"  # Default to 10 commits for merge preview

    log_info "Changes that will be applied from $source_ref to $target_branch:"
    log_info "=========================================="

    if git merge-base --is-ancestor "$source_ref" "$target_branch" 2>/dev/null; then
        log_info "No changes to merge (source is already in target)"
    else
        local range_spec="$target_branch..$source_ref"
        local commit_count=$(git_log_count "$range_spec")

        if [[ "$commit_count" -gt 0 ]]; then
            log_info "📊 Total changes: $commit_count commits"

            if [[ "$commit_count" -gt "$max_commits" ]]; then
                log_info "📝 Showing last $max_commits commits:"
                git_log_formatted "$range_spec" "$max_commits"
                log_info "... and $((commit_count - max_commits)) more commits"
            else
                log_info "📝 All commits:"
                git_log_formatted "$range_spec" "$max_commits"
            fi
        else
            log_info "No changes to merge (branches are synchronized)"
        fi
    fi
    log_info "=========================================="
}

# Interactive merge with conflict resolution handling
interactive_merge() {
    local target_branch="$1"
    local source_ref="$2"
    local commit_message="$3"
    local context="${4:-}"  # Optional context for messages

    log_step "Merging $source_ref into $target_branch${context:+ ($context)}..."

    # Validate target branch exists
    if ! check_branch_exists "$target_branch"; then
        log_error "Target branch doesn't exist: $target_branch"
        return 1
    fi

    # Validate source exists (could be branch, tag, or commit)
    if ! is_valid_tag "$source_ref"; then
        log_error "Source reference doesn't exist: $source_ref"
        return 1
    fi

    # Show what will be merged
    show_changes "$source_ref" "$target_branch"

    if ! confirm_action "Proceed with merge?"; then
        log_info "Merge cancelled by user"
        return 1
    fi

    # Determine merge strategy based on CONFLICT_STRATEGY
    local merge_strategy_args=""
    case "${CONFLICT_STRATEGY:-interactive}" in
        "prefer-ours")
            merge_strategy_args="-X ours"
            log_info "Using merge strategy: prefer-ours"
            ;;
        "prefer-theirs")
            merge_strategy_args="-X theirs"
            log_info "Using merge strategy: prefer-theirs"
            ;;
        "interactive"|*)
            merge_strategy_args=""
            ;;
    esac

    # Build merge command as array to avoid empty argument issues
    local merge_cmd=(git merge --no-ff)
    if [ -n "$merge_strategy_args" ]; then
        merge_cmd+=("$merge_strategy_args")
    fi
    # Prepend bypass marker for tool-generated commits
    local message_with_marker="[flow]: $commit_message"
    merge_cmd+=("$source_ref" -m "$message_with_marker")

    # Perform merge
    if "${merge_cmd[@]}" 2>/dev/null; then
        log_info "✓ Successfully merged $source_ref into $target_branch"
        return 0
    else
        # Merge conflict detected - handle interactively
        handle_merge_conflict "$target_branch" "$source_ref" "$context"
        return $?
    fi
}

# Handle merge conflict with user interaction
handle_merge_conflict() {
    local target_branch="$1"
    local source_ref="$2"  # Could be branch, tag, or commit
    local context="${3:-}"

    log_error "❌ Merge conflict detected while merging $source_ref into $target_branch${context:+ ($context)}!"
    log_empty ""
    log_info "🚨 CONFLICT RESOLUTION REQUIRED for merging $source_ref into $target_branch${context:+ ($context)}:"
    log_info "📋 Conflicted files:"
    git diff --name-only --diff-filter=U
    log_empty ""
    log_info "🔧 To resolve:"
    log_info "   1. Edit the conflicted files (look for <<<<<<<, =======, >>>>>>> markers)"
    log_info "   2. Run: git add . (to mark conflicts as resolved)"
    log_info "   3. EITHER:"
    log_info "      a) Run: git commit (to complete the merge) - then answer YES when prompted"
    log_info "      b) OR: Just answer YES and let the script complete the merge"
    log_empty ""
    log_info "💡 After resolving conflicts, the operation will continue automatically."
    log_info "   Or run: git merge --abort to cancel the merge"

    # Wait for user to resolve conflicts
    # IMPORTANT: Always use force_confirm_action here regardless of REQUIRE_CONFIRMATION.
    # An interactive merge conflict *requires* human intervention and must never be auto-confirmed.
    log_empty ""
    if force_confirm_action "Have you resolved the conflicts for merging $source_ref into $target_branch${context:+ ($context)} and ready to continue?"; then
        # Check if we're still in a merge state
        if [ -f ".git/MERGE_HEAD" ]; then
            # Still in merge - check if conflicts are resolved
            if has_unresolved_conflicts; then
                log_error "Conflicts still exist! Please resolve all conflicts first."
                log_info "Unresolved files:"
                git diff --name-only --diff-filter=U
                return 1
            fi

            # Ensure resolved files are staged
            if git status --porcelain | grep -q "^[^?]"; then
                log_info "Staging resolved files..."
                git add .
            fi

            # Try to complete the merge
            if git commit --no-edit; then
                log_info "✓ Conflicts resolved and merge $source_ref into $target_branch completed"
                return 0
            else
                log_error "Failed to commit merge of $source_ref into $target_branch"
                log_info "Try: git commit -m 'Merge: $source_ref into $target_branch${context:+ ($context)}'"
                return 1
            fi
        else
            # Not in merge state - check if merge was completed
            if git status | grep -q "nothing to commit"; then
                log_info "✓ Merge of $source_ref into $target_branch already completed by user"
                return 0
            else
                log_error "Unexpected state after resolving merge of $source_ref into $target_branch"
                log_info "Current status:"
                git status
                return 1
            fi
        fi
    else
        log_warn "Merge of $source_ref into $target_branch paused. Resolve conflicts and run the command again to continue."
        return 1
    fi
}

# Check if there are unresolved conflicts
has_unresolved_conflicts() {
    [[ -n "$(git diff --name-only --diff-filter=U 2>/dev/null)" ]]
}

# Verify step with error handling
verify_step() {
    local step_name="$1"
    local command="$2"
    local success_message="$3"

    log_step "$step_name..."
    if eval "$command" >/dev/null 2>&1; then
        log_info "✓ $success_message"
        return 0
    else
        log_error "✗ Failed: $step_name"
        return 1
    fi
}

# =============================================================================
# SYNC UTILITIES
# =============================================================================

# Get latest RC per base version from list of tags
get_latest_rc_per_base_version() {
    local tags="$1"
    local suffix="$(get_rc_suffix)"

    # Get unique base versions from the tags
    local unique_base_versions=$(echo "$tags" | \
        sed "s|^${STAGING_TAG_PREFIX}||" | \
        sed "s|${suffix}[0-9]*$||" | \
        sort -V | \
        uniq)

    local latest_tags=""

    # For each base version, find the latest RC
    for base_version in $unique_base_versions; do
        # Use grep -F for fixed string matching to avoid regex issues with slashes
        local latest_tag_for_version=$(echo "$tags" | \
            grep -F "${STAGING_TAG_PREFIX}${base_version}${suffix}" | \
            sort -V | \
            tail -1)

        if [ -n "$latest_tag_for_version" ]; then
            latest_tags="${latest_tags}${latest_tag_for_version}"$'\n'
        fi
    done

    echo "$latest_tags" | sed '/^$/d'
}

# Sync staging changes to develop branch
sync_to_develop() {
    local context="${1:-}"

    log_info "🔄 Syncing ${context:+$context }changes to develop..."
    git checkout "$DEVELOP_BRANCH"

    # Only sync if staging has new commits not in develop
    local staging_to_develop_commits
    staging_to_develop_commits=$(git log --oneline "$DEVELOP_BRANCH..$STAGING_BRANCH" 2>/dev/null)

    if [ -z "$staging_to_develop_commits" ]; then
        log_info "✓ Staging and develop are already synchronized"
        return 0
    fi

    log_info "Staging has new commits to sync to develop:"
    log_info "$staging_to_develop_commits"
    log_empty ""

    if ! interactive_merge "$DEVELOP_BRANCH" "$STAGING_BRANCH" \
        "Sync: ${context:+$context }staging changes" \
        "syncing to develop"; then
        log_error "Develop sync failed due to unresolved conflicts"
        return 1
    fi

    log_info "✓ Develop branch updated"
    return 0
}

# =============================================================================
# ATOMIC LOCKING MECHANISM
# =============================================================================

# Cross-platform atomic locking
acquire_lock() {
    local lock_name="$1"
    local lock_dir=".git/git-trident-locks"
    local lock_path="$lock_dir/$lock_name"
    local max_wait=30
    local waited=0

    # Create lock directory if it doesn't exist
    mkdir -p "$lock_dir" 2>/dev/null || true

    # Atomic directory creation for locking (works on all platforms)
    while ! mkdir "$lock_path" 2>/dev/null && [[ $waited -lt $max_wait ]]; do
        sleep 0.5
        waited=$((waited + 1))
        log_debug "Waiting for lock: $lock_name (${waited}/${max_wait})"
    done

    if [[ $waited -ge $max_wait ]]; then
        log_error "Timeout waiting for lock: $lock_name"
        return 1
    fi

    # Store PID in lock file for debugging
    echo "$$" > "$lock_path/pid"
    log_debug "Acquired lock: $lock_name"
    return 0
}

# Release lock
release_lock() {
    local lock_name="$1"
    local lock_dir=".git/git-trident-locks"
    local lock_path="$lock_dir/$lock_name"

    if [[ -d "$lock_path" ]]; then
        rm -rf "$lock_path"
        log_debug "Released lock: $lock_name"
    fi
}

# =============================================================================
# CROSS-OS_PLATFORM COMPATIBILITY
# =============================================================================

# Detect os platform and set compatibility variables
detect_platform() {
    case "$(uname -s)" in
        Linux*)     OS_PLATFORM=linux ;;
        Darwin*)    OS_PLATFORM=macos ;;
        CYGWIN*|MINGW*|MSYS*) OS_PLATFORM=windows ;;
        *)          OS_PLATFORM=unknown ;;
    esac
    echo "$OS_PLATFORM"
}

# Initialize platform detection
OS_PLATFORM=$(detect_platform)

# Cross-platform path normalization
normalize_path() {
    local path="$1"
    if [[ "$OS_PLATFORM" == "windows" ]]; then
        # Convert to Windows-style path if needed, but keep POSIX for Git Bash
        echo "$path" | sed 's/\\/\//g'
    else
        echo "$path"
    fi
}

# Cross-platform stat command for cache age checking
get_file_age() {
    local file="$1"
    local current_time=$(date +%s)
    local file_mtime=0

    case "$OS_PLATFORM" in
        linux)
            file_mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
            ;;
        macos)
            file_mtime=$(stat -f %m "$file" 2>/dev/null || echo "0")
            ;;
        windows)
            # Git Bash on Windows typically uses Linux-style stat
            if command -v stat >/dev/null 2>&1; then
                file_mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
            else
                # Fallback for minimal Windows environments
                file_mtime=$(perl -e 'print +(stat($ARGV[0]))[9]' "$file" 2>/dev/null || echo "0")
            fi
            ;;
        *)
            file_mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
            ;;
    esac

    echo $((current_time - file_mtime))
}

# Cross-platform sed in-place editing
sed_in_place() {
    local file="$1"
    local script="$2"

    case "$OS_PLATFORM" in
        macos)
            sed -i '' "$script" "$file"
            ;;
        *)
            sed -i "$script" "$file"
            ;;
    esac
}

# Ensure consistent sorting across platforms
safe_sort() {
    LC_ALL=C sort "$@"
}

# Cross-platform temporary file creation
create_temp_file() {
    case "$OS_PLATFORM" in
        windows)
            # Use Windows-compatible temp file creation
            mktemp 2>/dev/null || echo "/tmp/git-trident-temp.$$"
            ;;
        *)
            mktemp
            ;;
    esac
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize configuration - only auto-load in CLI mode (not hook mode or library mode)
# Hooks set GIT_TRIDENT_HOOK_MODE=true and handle config loading themselves
if [[ "${GIT_TRIDENT_HOOK_MODE:-false}" != "true" && "$1" != "--no-init" ]]; then
    load_project_config || exit 1
fi