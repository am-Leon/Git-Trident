#!/bin/bash
# Git Trident Hooks - Shared utilities for git hooks
# Contains only shared functions used by multiple hooks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# LOADING GUARD
# =============================================================================

# Load dependencies once per process.
# NOTE: We do NOT guard this with CONFIG_LOADED because hook scripts run as
# separate subprocesses. Even if the parent exported CONFIG_LOADED=true, bash
# functions are NOT inherited by subprocesses, so we must always source the
# file to make functions like log_error, log_info, etc. available.
if [[ -z "${GIT_TRIDENT_HOOKS_LOADED:-}" ]]; then
    GIT_TRIDENT_HOOKS_LOADED=true
    # GIT_TRIDENT_HOOK_MODE=true prevents git-trident-common.sh from calling exit 1 at source time
    GIT_TRIDENT_HOOK_MODE=true
    source "$SCRIPT_DIR/git-trident-common.sh"
    load_project_config || true
    log_debug "Git Trident Hooks utilities loaded"
fi

# =============================================================================
# STRING UTILITIES (Shared)
# =============================================================================

# Trim whitespace from both ends
trim_string() {
    local str="$1"
    echo "$str" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Count words in string (cross-platform compatible)
count_words() {
    local str="$1"
    # Remove leading/trailing spaces, convert multiple spaces to single
    str=$(echo "$str" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\+/ /g')

    # Count words (works on all platforms)
    if [[ -z "$str" ]]; then
        echo "0"
    else
        # Use awk for consistent word counting
        echo "$str" | awk '{print NF}'
    fi
}

# Extract platform from string like "[platform] text"
extract_platform_from_brackets() {
    local str="$1"
    if [[ "$str" =~ ^\[([a-zA-Z0-9_-]+)\] ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# =============================================================================
# CONFIG PARSING (Shared)
# =============================================================================

# Parse COMMIT_PREFIXES and COMMIT_PREFIX_DESCRIPTIONS into arrays
# Sets: COMMIT_PREFIX_ARRAY and COMMIT_DESC_ARRAY
parse_commit_prefix_config() {
    local prefixes="${COMMIT_PREFIXES:-}"
    local descriptions="${COMMIT_PREFIX_DESCRIPTIONS:-}"

    # Reset arrays
    COMMIT_PREFIX_ARRAY=()
    COMMIT_DESC_ARRAY=()

    if [[ -z "$prefixes" ]] || [[ -z "$descriptions" ]]; then
        log_error "COMMIT_PREFIXES or COMMIT_PREFIX_DESCRIPTIONS not set in configuration"
        return 1
    fi

    # Split prefixes by pipe
    IFS='|' read -ra COMMIT_PREFIX_ARRAY <<< "$prefixes"

    # Split descriptions by pipe
    IFS='|' read -ra COMMIT_DESC_ARRAY <<< "$descriptions"

    # Validate arrays have same length
    if [[ ${#COMMIT_PREFIX_ARRAY[@]} -ne ${#COMMIT_DESC_ARRAY[@]} ]]; then
        log_error "COMMIT_PREFIXES and COMMIT_PREFIX_DESCRIPTIONS have different lengths"
        log_error "Prefixes: ${#COMMIT_PREFIX_ARRAY[@]}, Descriptions: ${#COMMIT_DESC_ARRAY[@]}"
        return 1
    fi

    # Add colon to each prefix
    for i in "${!COMMIT_PREFIX_ARRAY[@]}"; do
        COMMIT_PREFIX_ARRAY[$i]="${COMMIT_PREFIX_ARRAY[$i]}:"
        log_debug "Loaded prefix: ${COMMIT_PREFIX_ARRAY[$i]} → ${COMMIT_DESC_ARRAY[$i]}"
    done

    log_debug "Loaded ${#COMMIT_PREFIX_ARRAY[@]} commit prefixes"
    return 0
}

# Get space-separated list of valid commit prefixes
get_valid_commit_prefixes() {
    if ! parse_commit_prefix_config 2>/dev/null; then
        return 1
    fi

    local result=""
    for prefix in "${COMMIT_PREFIX_ARRAY[@]}"; do
        result="${result}${prefix} "
    done
    log_debug "Valid prefixes: ${result}"
    echo "${result% }"  # Remove trailing space
}

# Get description for a specific prefix
get_prefix_description() {
    local prefix="$1"
    local prefix_without_colon=$(echo "$prefix" | sed 's/:$//')

    if ! parse_commit_prefix_config 2>/dev/null; then
        return 1
    fi

    for i in "${!COMMIT_PREFIX_ARRAY[@]}"; do
        if [[ "${COMMIT_PREFIX_ARRAY[$i]}" == "$prefix" ]]; then
            log_debug "Description for $prefix: ${COMMIT_DESC_ARRAY[$i]}"
            echo "${COMMIT_DESC_ARRAY[$i]}"
            return 0
        fi
    done

    log_debug "No description found for prefix: $prefix"
    echo ""
}

# =============================================================================
# HOOK ENABLED CHECK (Shared)
# =============================================================================

# Check if hooks are enabled (for use in hook scripts)
# Usage: check_hooks_enabled [hook_name]
check_hooks_enabled() {
    local hook_name="${1:-}"

    # 1. Check for manual bypass
    if [[ "${GIT_TRIDENT_SKIP_HOOKS:-0}" == "1" ]] || [[ "${GIT_TRIDENT_SKIP_HOOKS:-false}" == "true" ]]; then
        log_debug "Hooks bypassed via GIT_TRIDENT_SKIP_HOOKS"
        return 1
    fi

    # 2. Check global kill switch
    if [[ "${HOOKS_ENABLED:-false}" != "true" ]]; then
        log_debug "Hooks disabled via HOOKS_ENABLED=false"
        return 1
    fi

    # 3. Check granular hook setting (if hook_name provided)
    if [[ -n "$hook_name" ]]; then
        # Convert hook-name to HOOK_HOOK_NAME_ENABLED
        local var_name="HOOK_$(echo "$hook_name" | tr 'a-z-' 'A-Z_')_ENABLED"
        local var_value="${!var_name:-true}" # Default to true if global is true, but granular is missing
        
        if [[ "$var_value" != "true" ]]; then
            log_debug "Hook $hook_name disabled via $var_name=false"
            return 1
        fi
    fi

    # Quick config validation when enabled
    if [[ -z "${COMMIT_PREFIXES:-}" ]] || [[ -z "${COMMIT_PREFIX_DESCRIPTIONS:-}" ]]; then
        log_error "Hook configuration incomplete. Set COMMIT_PREFIXES and COMMIT_PREFIX_DESCRIPTIONS"
        return 1
    fi

    return 0
}

# =============================================================================
# LOCAL HOOK CHAINING
# =============================================================================

# Run project-local hooks if they exist in .git/hooks/
run_local_project_hook() {
    local hook_name="$1"
    shift
    local args=("$@")

    local git_dir=""
    git_dir=$(git rev-parse --git-dir 2>/dev/null)
    
    if [[ -z "$git_dir" ]]; then
        return 0
    fi

    # Global core.hooksPath overrides local .git/hooks
    # If the user has project local hooks, they will be inside .git/hooks/<hook-name>
    local local_hook="$git_dir/hooks/$hook_name"

    # Important: Ensure the local hook is not an accidentally linked/copied git-trident hook
    if [[ -f "$local_hook" ]] && [[ -x "$local_hook" ]] && ! grep -q "Git Trident - " "$local_hook"; then
        log_debug "Executing local project hook: $local_hook"
        
        # Execute the local hook
        if "$local_hook" "${args[@]}"; then
            log_debug "Local project hook passed: $hook_name"
            return 0
        else
            log_error "Local project hook failed: $hook_name"
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# WIP COMMIT DETECTION (Shared with pre-push hook)
# =============================================================================

# Check if commit message is WIP
is_wip_commit() {
    local commit_msg="$1"

    # Check for wip: prefix (with or without platform)
    if [[ "$commit_msg" =~ ^(\[.*\][[:space:]]+)?wip: ]]; then
        return 0  # Is WIP
    fi

    return 1  # Not WIP
}

# Get WIP commits in range
get_wip_commits() {
    local from_ref="$1"
    local to_ref="$2"

    # Find commits with wip: in their message
    git log --oneline --grep="^wip:\|^\[.*\] wip:" "$from_ref..$to_ref" 2>/dev/null
}