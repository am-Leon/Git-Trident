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

# Load the tag grammar (gt_regex_escape, gt_rc_suffix, gt_tag_*, gt_re_*).
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/git-trident-tagspec.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/git-trident-tagspec.sh"
fi

# Load repository context helpers (GT_REPO_ROOT / GT_GIT_DIR, gt_repo_path,
# gt_git_path). Sourcing only DEFINES them; resolution happens in
# load_project_config, because utility commands run outside a repository.
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/git-trident-context.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/git-trident-context.sh"
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
    "CONFIG_PARSER=strict"
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
    "CONFIG_PARSER"
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
# Is this a key Git Trident recognises?
gt_config_key_is_known() {
    local key="$1" entry
    for entry in "${REQUIRED_CONFIG_VARS[@]}"; do
        [[ "$entry" == "$key" ]] && return 0
    done
    for entry in "${OPTIONAL_CONFIG_VARS[@]}"; do
        [[ "${entry%%=*}" == "$key" ]] && return 0
    done
    return 1
}

gt_config_key_is_global_only() {
    local key="$1" entry
    for entry in "${GLOBAL_ONLY_CONFIG_KEYS[@]}"; do
        [[ "$entry" == "$key" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# _parse_config_file  — strict KEY=VALUE reader (CONFIG_PARSER=strict)
# ---------------------------------------------------------------------------
# Reads a config file WITHOUT executing it.
#
# The alternative, `set -a; source "$file"; set +a`, has two real problems:
#
#   1. git-trident-config is COMMITTED to the repository, so cloning a project
#      and running any Git Trident command executes whatever that file contains.
#      For a tool designed to be shared across a team, that is a hole.
#   2. `set -a` exports every assignment. That is how CONFIG_LOADED=true leaked
#      into child processes and made them skip validation, and it lets a stray
#      variable in the user's shell silently override project settings.
#
# It also removes the need for the snapshot/restore workaround around
# GLOBAL_ONLY_CONFIG_KEYS: a global-only key found in a project file is simply
# never read, instead of being read and then undone with eval.
#
# Arguments: <file> <scope: global|project>
_parse_config_file() {
    local config_file="$1" scope="$2"
    local line key val

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip blanks and comments
        case "$line" in
            ''|'#'*) continue ;;
        esac
        # Accept:  KEY=value  /  export KEY=value  (leading whitespace allowed)
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue

        key="${BASH_REMATCH[2]}"
        val="${BASH_REMATCH[3]}"

        # Trim leading whitespace
        val="${val#"${val%%[![:space:]]*}"}"

        # A quoted value runs to its closing quote; anything after it (such as
        # an inline comment) is discarded. An unquoted value ends at the first
        # whitespace-then-# sequence. Handling quotes FIRST matters: a value
        # like  "-rc-"   # comment  starts with a quote but does not end with
        # one, so a naive "is it quoted?" test leaves the comment attached.
        case "$val" in
            \"*) val="${val#\"}"; val="${val%%\"*}" ;;
            \'*) val="${val#\'}"; val="${val%%\'*}" ;;
            *)
                case "$val" in
                    *[[:space:]]#*) val="${val%%[[:space:]]#*}" ;;
                esac
                # Trim trailing whitespace
                val="${val%"${val##*[![:space:]]}"}"
                ;;
        esac

        if ! gt_config_key_is_known "$key"; then
            log_warn "Unknown configuration key ignored: $key ($config_file)"
            continue
        fi

        if [[ "$scope" == "project" ]] && gt_config_key_is_global_only "$key"; then
            # Warned about separately by _warn_global_only_keys_in_project_config
            log_debug "Ignoring global-only key in project config: $key"
            continue
        fi

        printf -v "$key" '%s' "$val"
    done < "$config_file"

    return 0
}

# ---------------------------------------------------------------------------
# _source_config_file — legacy loader (CONFIG_PARSER=legacy)
# ---------------------------------------------------------------------------
# Kept for one minor version so projects using shell expressions inside their
# config have a migration path. Set CONFIG_PARSER=legacy to opt back in.
_source_config_file_legacy() {
    local config_file="$1"
    set -a
    # shellcheck source=/dev/null
    source "$config_file"
    local status=$?
    set +a
    return $status
}

# Dispatcher used by load_project_config.
_source_config_file() {
    local config_file="$1" scope="${2:-project}"
    if [[ "${CONFIG_PARSER:-strict}" == "legacy" ]]; then
        _source_config_file_legacy "$config_file"
    else
        _parse_config_file "$config_file" "$scope"
    fi
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
    # Prevent duplicate configuration loading within the same session.
    #
    # The flag alone is not sufficient evidence. CONFIG_LOADED can arrive from
    # the ENVIRONMENT — inherited from a parent process, or exported by a user
    # or a test fixture — in which case the values it claims to vouch for may
    # not be set at all. Short-circuiting then yields an empty configuration
    # and nonsense results (branch desynchronisation reported on a synchronised
    # repository). Require a required key to actually be present.
    if [[ "$CONFIG_LOADED" == "true" ]]; then
        # Trust the flag only if SOMETHING was actually configured. Callers that
        # set CONFIG_LOADED deliberately (hook fixtures, tests) also set the keys
        # they care about; an inherited flag from a parent process comes with
        # nothing, because configuration values are no longer exported.
        if [[ -n "${PRODUCTION_BRANCH:-}" || -n "${STAGING_TAG_PREFIX:-}" || -n "${COMMIT_PREFIXES:-}" ]]; then
            log_debug "Configuration already loaded from: ${CONFIG_SOURCE:-caller}"
            return 0
        fi
        log_debug "CONFIG_LOADED was set but no configuration is present; reloading."
        CONFIG_LOADED=false
    fi

    # ── Guard 1: Are we inside a Git repository? ──
    # gt_resolve_repo_context also establishes GT_REPO_ROOT / GT_GIT_DIR, which
    # every path below depends on.
    if ! gt_resolve_repo_context; then
        if [[ "${SUPPRESS_CONFIG_ERRORS:-false}" != "true" ]]; then
            log_error "❌ Not inside a Git repository."
            log_error "   Git Trident only works inside a Git project."
            log_error "   Please navigate to a Git repository and try again."
        fi
        return 1
    fi

    local global_config="$HOME/$GLOBAL_CONFIG_FILE_NAME"
    # Anchored to the REPOSITORY ROOT, not the current directory, so every
    # command works from anywhere inside the working tree.
    local project_config_files=(
        "$(gt_repo_path "$CONFIG_FILE_NAME")"    # Project root (explicit, committed)
        "$(gt_repo_path ".$CONFIG_FILE_NAME")"   # Project root (hidden / git ignored)
    )

    # ------------------------------------------------------------------
    # Step 1 — Load the global config (provides machine-level defaults)
    # ------------------------------------------------------------------
    local global_loaded=false
    if [[ -f "$global_config" ]]; then
        log_debug "Loading global configuration from: $global_config"
        if _source_config_file "$global_config" "global"; then
            global_loaded=true
            log_debug "✓ Global configuration loaded: $global_config"
        else
            log_warn "Failed to source global config: $global_config (continuing)"
        fi
    else
        log_debug "Global config not found: $global_config"
    fi

    # NOTE: the strict parser never reads a global-only key out of a project
    # file, so there is nothing to undo afterwards. This used to snapshot every
    # global-only value into dynamically-named locals via eval, source the
    # project file, then eval them back — a workaround that only existed because
    # `source` could not be told which keys to ignore.
    #
    # Under CONFIG_PARSER=legacy the project file is still sourced wholesale, so
    # the restore below is kept for that path only.
    local _using_legacy_parser=false
    if [[ "${CONFIG_PARSER:-strict}" == "legacy" ]]; then
        _using_legacy_parser=true
        for _key in "${GLOBAL_ONLY_CONFIG_KEYS[@]}"; do
            eval "local _global_snapshot_$_key=\"\${!_key:-}\""
        done
    fi

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

        if _source_config_file "$project_file" "project"; then
            project_loaded=true
            log_debug "✓ Project configuration loaded: $project_file"
        else
            log_error "Failed to source project config: $project_file"
            return 1
        fi

        # Legacy path only: `source` cannot be told which keys to skip, so the
        # global-only values are put back after the fact.
        if [[ "$_using_legacy_parser" == "true" ]]; then
            for _key in "${GLOBAL_ONLY_CONFIG_KEYS[@]}"; do
                eval "local _global_val=\"\${_global_snapshot_$_key:-}\""
                if [[ -n "$_global_val" ]]; then
                    export "$_key"="$_global_val"
                    log_debug "Restored global-only key: $_key=${_global_val}"
                fi
            done
        fi
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
        CONFIG_SOURCE="$project_file (+ $global_config)"
    else
        CONFIG_SOURCE="$global_config"
    fi
    # NOT exported. Under the strict parser the values are set with `printf -v`
    # rather than `set -a`, so they do not cross a process boundary. Exporting
    # only the FLAG made child processes short-circuit load_project_config and
    # then find every setting empty — `git trident status` reported branch
    # desynchronisation on a perfectly synchronised repository, while running
    # git-trident-verify-sync directly worked.
    #
    # Each process loads its own configuration. That is a file read, and it
    # keeps configuration out of the environment entirely.
    CONFIG_LOADED=true

    # Set validation mode from whichever config set it, or default to strict
    CONFIG_VALIDATION_MODE="${CONFIG_VALIDATION_MODE:-strict}"

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

# Setup optional configuration defaults
setup_optional_config_defaults() {
    for optional_var in "${OPTIONAL_CONFIG_VARS[@]}"; do
        local var_name="${optional_var%=*}"
        local default_value="${optional_var#*=}"
        
        if [[ -z "${!var_name:-}" ]]; then
            # Plain assignment, not export: see the note on CONFIG_LOADED above.
            printf -v "$var_name" '%s' "$default_value"
            log_debug "Set default for optional $var_name: $default_value"
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
# GIT COMMAND WRAPPER
# =============================================================================

# Run a git command, capture BOTH streams, and surface the error when it fails.
#
# The codebase had ~160 sites sending git's stderr to /dev/null. For read-only
# probes (`rev-parse`, `show-ref`) that is a legitimate existence test, but for
# mutating commands it meant real failures were invisible or — worse —
# misattributed. interactive_merge reported "merge conflict" for an invalid
# strategy flag, and `cleanup prune` reported success while deleting nothing.
#
# Output is echoed on stdout so callers can inspect it; the exit status is git's.
#
# Usage:
#   output=$(gt_git tag -a "$name" "$ref" -m "$msg") || { log_error "$output"; return 1; }
gt_git() {
    local output rc
    output=$(git "$@" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        log_debug "git $* -> exit $rc: $output"
    fi
    printf '%s' "$output"
    return $rc
}

# Run a git command and, on failure, log the error with a caller-supplied
# context line. Returns git's exit status.
gt_git_checked() {
    local context="$1"; shift
    local output rc
    output=$(git "$@" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        log_error "$context"
        while IFS= read -r _gt_line; do
            [ -n "$_gt_line" ] && log_empty "   $_gt_line"
        done <<< "$output"
    fi
    return $rc
}

# =============================================================================
# GIT LOG UTILITIES
# =============================================================================

# Count non-empty lines in a string.
#
# `echo "" | wc -l` returns 1, not 0, because echo emits a newline. Counting a
# possibly-empty list that way reports one phantom item, which in platform mode
# made push-all iterate once over an empty string and fail with
# "Failed to push 1 tags:" when there was nothing to push.
#
# `grep -c .` counts lines containing at least one character, so an empty or
# whitespace-only string correctly yields 0.
count_lines() {
    local value="$1"
    if [[ -z "$value" ]]; then
        echo 0
        return 0
    fi
    printf '%s\n' "$value" | grep -c . | tr -d ' '
}

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

# NOTE: is_valid_tag lives in git-trident-version-utils.sh, which owns tag
# concerns. An identical copy used to be defined here too; whichever file was
# sourced last silently won.

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

    # Determine merge strategy based on CONFLICT_STRATEGY.
    #
    # Each flag must be a SEPARATE argv element. Previously this was built as a
    # single string "-X ours", which git received as one argument:
    #     git merge --no-ff "-X ours" <src> -m <msg>
    #     fatal: unknown strategy option: -X ours
    # so prefer-ours / prefer-theirs never worked at all.
    local strategy_args=()
    case "${CONFLICT_STRATEGY:-interactive}" in
        "prefer-ours")
            strategy_args=(-X ours)
            log_info "Using merge strategy: prefer-ours"
            ;;
        "prefer-theirs")
            strategy_args=(-X theirs)
            log_info "Using merge strategy: prefer-theirs"
            ;;
        "interactive"|*)
            strategy_args=()
            ;;
    esac

    # Prepend bypass marker for tool-generated commits
    local message_with_marker="[flow]: $commit_message"

    # NOTE: ${arr[@]+"${arr[@]}"} rather than "${arr[@]}". `interactive` is the
    # default, so strategy_args is EMPTY on the common path, and on Bash 3.2
    # expanding an empty array under `set -u` raises "unbound variable".
    local merge_output merge_rc
    merge_output=$(git merge --no-ff ${strategy_args[@]+"${strategy_args[@]}"} \
                             "$source_ref" -m "$message_with_marker" 2>&1)
    merge_rc=$?

    if [ $merge_rc -eq 0 ]; then
        log_info "✓ Successfully merged $source_ref into $target_branch"
        return 0
    fi

    # A non-zero exit is NOT necessarily a conflict. git's stderr used to be sent
    # to /dev/null, so an invalid option, a missing ref or a dirty tree were all
    # reported to the user as "merge conflict detected" and they were dropped into
    # a conflict-resolution prompt with no conflict to resolve. Distinguish them.
    if has_unresolved_conflicts; then
        handle_merge_conflict "$target_branch" "$source_ref" "$context"
        return $?
    fi

    log_error "❌ Merge of $source_ref into $target_branch failed (not a conflict):"
    while IFS= read -r _line; do
        [ -n "$_line" ] && log_empty "   $_line"
    done <<< "$merge_output"
    return 1
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
        if [ -f "$(gt_git_path MERGE_HEAD)" ]; then
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

    # Capture the output instead of discarding it. Every checkout, tag and
    # branch creation in the release flows goes through here, and a bare
    # "✗ Failed: Creating staging tag" with no reason is close to useless.
    local output rc
    output=$(eval "$command" 2>&1)
    rc=$?

    if [ $rc -eq 0 ]; then
        log_info "✓ $success_message"
        return 0
    fi

    log_error "✗ Failed: $step_name"
    while IFS= read -r _line; do
        [ -n "$_line" ] && log_empty "   $_line"
    done <<< "$output"
    return 1
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
    local lock_dir="$(gt_git_path git-trident-locks)"
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
    local lock_dir="$(gt_git_path git-trident-locks)"
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

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize configuration - only auto-load in CLI mode (not hook mode or library mode)
# Hooks set GIT_TRIDENT_HOOK_MODE=true and handle config loading themselves
if [[ "${GIT_TRIDENT_HOOK_MODE:-false}" != "true" && "$1" != "--no-init" ]]; then
    load_project_config || exit 1
fi