#!/bin/bash
# Git Trident Version Utilities - Comprehensive tag and version management
# Supports both single-environment and multi-platform modes

# This file is sourced on its own in several places (tests, and libs that pull in
# version utilities without common.sh), so it must satisfy its own dependency on
# the tag grammar rather than assume a caller already loaded it.
if ! declare -f gt_rc_suffix >/dev/null 2>&1; then
    if [[ -f "$(dirname "${BASH_SOURCE[0]}")/git-trident-tagspec.sh" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/git-trident-tagspec.sh"
    fi
fi

# =============================================================================
# VERSION PARSING AND VALIDATION
# =============================================================================

# Extract platform from platform-specific version
# Input: android-1.2.3-rc-01 or android-1.2.3
# Output: android or empty string
extract_platform_from_version() {
    local version="$1"

    if [[ "$version" =~ ^([a-zA-Z0-9_-]+)-([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Extract base version from any version format
# Input: android-1.2.3-rc-01 → Output: 1.2.3
# Input: 1.2.3-rc-01 → Output: 1.2.3
# Input: 1.2.3 → Output: 1.2.3
extract_base_version() {
    local version="$1"

    # Platform-specific format: platform-MAJOR.MINOR.PATCH
    if [[ "$version" =~ ^[a-zA-Z0-9_-]+-([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    # Legacy format: MAJOR.MINOR.PATCH
    elif [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    else
        echo ""
    fi
}

# Extract RC number from version/tag
# Input: android-1.2.3-rc-01 → Output: 01
# Input: 1.2.3-rc-02 → Output: 02
extract_rc_number() {
    local version="$1"
    # Escaped pattern: STAGING_TAG_SUFFIX is user-configurable and may contain
    # regex metacharacters (see git-trident-tagspec.sh).
    local re; re="$(gt_re_rc_tail)"

    if [[ "$version" =~ $re ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Validate platform name
is_valid_platform() {
    local platform="$1"

    if [ -z "$platform" ] || [ -z "${PLATFORMS:-}" ]; then
        return 1
    fi

    # Check if platform exists in PLATFORMS array
    for p in $PLATFORMS; do
        if [ "$p" = "$platform" ]; then
            return 0
        fi
    done

    return 1
}

# Validate version format based on current mode
validate_version_format() {
    local version="$1"
    local allow_same_version="${2:-false}"

    if [ -z "$version" ]; then
        log_error "Version cannot be empty"
        return 1
    fi

    # Check mode and validate accordingly
    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" = "true" ]; then
        validate_platform_specific_version "$version" "$allow_same_version"
    else
        validate_legacy_version "$version" "$allow_same_version"
    fi
}

# Validate platform-specific version format
validate_platform_specific_version() {
    local version="$1"
    local allow_same_version="$2"

    # Format: platform-MAJOR.MINOR.PATCH[SUFFIX-XX]
    local suffix="$(get_rc_suffix)"
    local re; re="^([a-zA-Z0-9_-]+)-([0-9]+)\.([0-9]+)\.([0-9]+)$(gt_re_rc_optional)\$"
    if [[ ! "$version" =~ $re ]]; then
        log_error "Invalid platform-specific version format: $version"
        log_info "Expected format: platform-MAJOR.MINOR.PATCH[${suffix}XX]"
        log_info "Example: android-1.2.3 or ios-2.0.1${suffix}01"
        log_info "Supported platforms: $PLATFORMS"
        return 1
    fi

    local platform="${BASH_REMATCH[1]}"
    local major="${BASH_REMATCH[2]}"
    local minor="${BASH_REMATCH[3]}"
    local patch="${BASH_REMATCH[4]}"

    # Validate platform
    if ! validate_platform "$platform"; then
        return 1
    fi

    # Validate version progression for production releases
    if [ "$allow_same_version" = "false" ]; then
        local latest_prod=$(get_latest_production_tag_for_platform "$platform")
        local base_version="$major.$minor.$patch"

        if [ -n "$latest_prod" ]; then
            if ! is_version_greater "$base_version" "$latest_prod"; then
                log_error "Version $base_version is not greater than latest production $latest_prod for platform $platform"
                log_info "Latest $platform production: $latest_prod"
                return 1
            fi
        fi
    fi

    return 0
}

# Validate legacy version format
validate_legacy_version() {
    local version="$1"
    local allow_same_version="$2"

    # Format: MAJOR.MINOR.PATCH[SUFFIX-XX]
    local suffix="$(get_rc_suffix)"
    local re; re="^([0-9]+)\.([0-9]+)\.([0-9]+)$(gt_re_rc_optional)\$"
    if [[ ! "$version" =~ $re ]]; then
        log_error "Invalid legacy version format: $version"
        log_info "Expected format: MAJOR.MINOR.PATCH[${suffix}XX]"
        log_info "Example: 1.2.3 or 2.0.1${suffix}01"
        return 1
    fi

    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    local base_version="$major.$minor.$patch"

    # Validate version progression for production releases
    if [ "$allow_same_version" = "false" ]; then
        local latest_prod=$(get_latest_production_tag)

        if [ -n "$latest_prod" ]; then
            if ! is_version_greater "$base_version" "$latest_prod"; then
                log_error "Version $base_version is not greater than latest production $latest_prod"
                return 1
            fi
        fi
    fi

    return 0
}

# Validate staging version format (for new releases)
validate_staging_version_format() {
    local version="$1"

    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" = "true" ]; then
        # Platform-specific: must have platform prefix
        if [[ ! "$version" =~ ^[a-zA-Z0-9_-]+-[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "Invalid staging version format: $version"
            log_info "For platform-specific mode, use: platform-MAJOR.MINOR.PATCH"
            log_info "Example: android-1.2.3 (do not include $(get_rc_suffix)XX suffix)"
            return 1
        fi

        local platform=$(extract_platform_from_version "$version")
        if ! is_valid_platform "$platform"; then
            log_error "Invalid platform: $platform"
            return 1
        fi
    else
        # Legacy: simple version format
        if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
            log_error "Invalid staging version format: $version"
            log_info "For legacy mode, use: MAJOR.MINOR.PATCH"
            log_info "Example: 1.2.3 (do not include $(get_rc_suffix)XX suffix)"
            return 1
        fi
    fi

    return 0
}

# Validate production version format
validate_production_version_format() {
    local version="$1"

    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" = "true" ]; then
        # Platform-specific: must have platform prefix
        if [[ ! "$version" =~ ^[a-zA-Z0-9_-]+-[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "Invalid production version format: $version"
            log_info "For platform-specific mode, use: platform-MAJOR.MINOR.PATCH"
            log_info "Example: android-1.2.3"
            return 1
        fi

        local platform=$(extract_platform_from_version "$version")
        if ! is_valid_platform "$platform"; then
            log_error "Invalid platform: $platform"
            return 1
        fi
    else
        # Legacy: simple version format
        if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
            log_error "Invalid production version format: $version"
            log_info "For legacy mode, use: MAJOR.MINOR.PATCH"
            log_info "Example: 1.2.3"
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# VERSION COMPARISON
# =============================================================================

# Compare two versions (supports both formats)
is_version_greater() {
    local version1="$1"
    local version2="$2"

    [[ -z "$version2" ]] && return 0  # No previous version

    # Extract base versions for comparison
    local v1_base=$(extract_base_version "$version1")
    local v2_base=$(extract_base_version "$version2")

    if [ -z "$v1_base" ] || [ -z "$v2_base" ]; then
        log_debug "Cannot compare versions: v1='$v1_base', v2='$v2_base'"
        return 1
    fi

    # Split versions into arrays
    IFS='.' read -ra v1_parts <<< "$v1_base"
    IFS='.' read -ra v2_parts <<< "$v2_base"

    # Compare each part
    for i in 0 1 2; do
        local v1_part=${v1_parts[i]:-0}
        local v2_part=${v2_parts[i]:-0}

        [[ "$v1_part" -gt "$v2_part" ]] && return 0
        [[ "$v1_part" -lt "$v2_part" ]] && return 1
    done

    return 1  # Versions are equal
}

# =============================================================================
# TAG MANAGEMENT
# =============================================================================

# Get latest production tag (all platforms or specific)
get_latest_production_tag() {
    local platform_filter="${1:-}"

    local tags
    local suffix="$(get_rc_suffix)"
    if [ -n "$platform_filter" ]; then
        tags=$(git tag -l "${PRODUCTION_TAG_PREFIX}${platform_filter}-*" | grep -v -E ".*${suffix}[0-9]+")
    else
        tags=$(git tag -l "${PRODUCTION_TAG_PREFIX}*" | grep -v -E ".*${suffix}[0-9]+")
    fi

    echo "$tags" | sort -V | tail -n1 | sed "s|^${PRODUCTION_TAG_PREFIX}||"
}

# Get latest production tag for specific platform
get_latest_production_tag_for_platform() {
    local platform="$1"
    get_latest_production_tag "$platform"
}

# Get all staging tags for a version (supports both formats)
get_staging_tags_for_version() {
    local version="$1"

    local suffix="$(get_rc_suffix)"
    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" = "true" ]; then
        # Platform-specific: version includes platform
        git tag -l "${STAGING_TAG_PREFIX}${version}${suffix}*" | sort -V
    else
        # Legacy: simple version
        git tag -l "${STAGING_TAG_PREFIX}${version}${suffix}*" | sort -V
    fi
}

# Get all staging tags (with optional platform filter)
get_all_staging_tags() {
    local platform_filter="${1:-}"

    if [ -n "$platform_filter" ]; then
        git tag -l "${STAGING_TAG_PREFIX}${platform_filter}-*" | sort -V
    else
        git tag -l "${STAGING_TAG_PREFIX}*" | sort -V
    fi
}

# Get all production tags (with optional platform filter)
get_all_production_tags() {
    local platform_filter="${1:-}"

    if [ -n "$platform_filter" ]; then
        git tag -l "${PRODUCTION_TAG_PREFIX}${platform_filter}-*" | sort -V
    else
        git tag -l "${PRODUCTION_TAG_PREFIX}*" | sort -V
    fi
}

# =============================================================================
# RC NUMBER MANAGEMENT
# =============================================================================

# Kept as the historical name; the grammar now lives in git-trident-tagspec.sh.
get_rc_suffix(){
  gt_rc_suffix
}

# Get next RC number for a version
get_next_rc_number() {
    local version="$1"

    # NOTE: this function only COMPUTES the next number; it does not reserve it.
    # The caller must hold the RC lock across "compute -> create tag", because
    # the value is stale the moment another process creates a tag.
    #
    # The previous implementation tried to lock here and got it wrong three ways:
    #   * `[ -f "$lock" ]` then `touch "$lock"` is a check-then-act race, not an
    #     atomic acquisition (mkdir is — see acquire_lock in common.sh);
    #   * after max_wait it proceeded WITHOUT the lock rather than failing;
    #   * it released the lock before returning, so the critical section — which
    #     ends when the tag is created, in the caller — was never covered.
    local latest_rc; latest_rc=$(get_latest_rc_for_version "$version")
    local next_rc="01"

    if [ -n "$latest_rc" ]; then
        local current_rc; current_rc=$(extract_rc_number "$latest_rc")
        if [ -n "$current_rc" ]; then
            # Strip leading zeros so 08/09 are not read as invalid octal.
            local current_num; current_num=$(echo "$current_rc" | sed 's/^0*//')
            : "${current_num:=0}"
            next_rc=$(printf "%02d" $((current_num + 1)))
        fi
    fi

    echo "$next_rc"
}

# Reserve the RC namespace for the duration of a release/hotfix completion.
#
# Wraps the atomic mkdir-based lock in common.sh. Callers MUST pair this with
# gt_release_rc_lock, and should install a trap so an interrupted command does
# not leave the lock behind.
gt_acquire_rc_lock() {
    if declare -f acquire_lock >/dev/null 2>&1; then
        acquire_lock "rc-allocation" || return 1
    fi
    return 0
}

gt_release_rc_lock() {
    if declare -f release_lock >/dev/null 2>&1; then
        release_lock "rc-allocation"
    fi
    return 0
}

# Get next RC number for version (for rebase operations)
get_next_rc_number_for_version() {
    local version="$1"
    local current_rc="$2"

    if [ -z "$current_rc" ]; then
        echo "01"
    else
        # Remove leading zeros for arithmetic
        local current_num=$(echo "$current_rc" | sed 's/^0*//')
        local next_num=$((current_num + 1))
        printf "%02d" $next_num
    fi
}

# Get the latest RC for a version
get_latest_rc_for_version() {
    local version="$1"

    local suffix="$(get_rc_suffix)"
    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" = "true" ]; then
        # Platform-specific: version includes platform
        git tag -l "${STAGING_TAG_PREFIX}${version}${suffix}*" | sort -V | tail -1
    else
        # Legacy: simple version
        git tag -l "${STAGING_TAG_PREFIX}${version}${suffix}*" | sort -V | tail -1
    fi
}

# =============================================================================
# TAG VALIDATION AND CREATION
# =============================================================================

# Check if production tag exists
is_production_tag_released() {
    local version="$1"
    local production_tag="${PRODUCTION_TAG_PREFIX}${version}"
    git rev-parse "$production_tag" >/dev/null 2>&1
}

# Check if tag exists
is_valid_tag() {
    local tag="$1"
    git rev-parse "$tag" >/dev/null 2>&1
}

# =============================================================================
# VERSION EXTRACTION FROM TAGS
# =============================================================================

# Extract base version from tag (without prefix)
extract_base_version_from_tag() {
    local tag="$1"
    local prefix="$2"

    # Extract version without prefix
    local version=$(echo "$tag" | sed "s|^${prefix}||")
    local suffix="$(get_rc_suffix)"

    # Remove RC suffix if present (escaped — see git-trident-tagspec.sh)
    echo "$version" | sed "$(gt_sed_strip_rc)"
}

# Extract full version from tag (without prefix)
extract_version_from_tag() {
    local tag="$1"
    local prefix="$2"

    # Use different sed delimiter to avoid issues with slashes
    echo "$tag" | sed "s|^${prefix}||"
}

# =============================================================================
# TAG PROMOTION VALIDATION
# =============================================================================

# Validate staging tag is promotable to production
# $2 (the target production version) is accepted for call-site symmetry with the
# other validate_* helpers but is not used: promotability is determined entirely
# by the staging tag's own lineage.
validate_staging_tag_promotable() {
    local staging_tag="$1"

    log_info "🔍 Validating staging tag: $staging_tag"

    # Check if tag exists
    if ! is_valid_tag "$staging_tag"; then
        log_error "Staging tag not found: $staging_tag"
        return 1
    fi

    # Extract base version
    local base_version=$(extract_base_version_from_tag "$staging_tag" "$STAGING_TAG_PREFIX")
    log_info "   Base version: $base_version"

    # Check if this is a deprecated tag (has a newer RC)
    local latest_rc=$(get_latest_rc_for_version "$base_version")
    log_info "   Latest RC: $latest_rc"
    log_info "   Current tag: $staging_tag"

    if [ -n "$latest_rc" ] && [ "$latest_rc" != "$staging_tag" ]; then
        log_error "Cannot promote deprecated staging tag: $staging_tag"
        log_info "A newer RC exists: $latest_rc"
        log_info "Always promote the LATEST RC for a version"
        return 1
    fi

    # Check if tag includes latest production changes
    local platform=$(extract_platform_from_version "$base_version")
    local latest_production=$(get_latest_production_tag_for_platform "$platform")

    if [ -n "$latest_production" ]; then
        local production_tag="${PRODUCTION_TAG_PREFIX}${latest_production}"
        if ! git merge-base --is-ancestor "$production_tag" "$staging_tag" 2>/dev/null; then
            log_error "Staging tag $staging_tag does not include production changes $latest_production"
            log_info "This tag is outdated and cannot be promoted to production"
            log_info "Run: git trident staging sync-tags $latest_production"
            return 1
        fi
    fi

    log_info "✅ Staging tag $staging_tag is promotable"
    return 0
}

# =============================================================================
# VERSION INCREMENTING
# =============================================================================

# Auto-increment patch version
increment_patch_version() {
    local version="$1"
    local major minor patch

    # Strip leading 'v' if present
    version="${version#v}"

    # Handle both platform-specific and legacy formats
    if [[ "$version" =~ ^([a-zA-Z0-9_-]+)-([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        # Platform-specific: platform-MAJOR.MINOR.PATCH
        local platform="${BASH_REMATCH[1]}"
        major="${BASH_REMATCH[2]}"
        minor="${BASH_REMATCH[3]}"
        patch="${BASH_REMATCH[4]}"
        patch=$((patch + 1))
        echo "${platform}-${major}.${minor}.${patch}"
    elif [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        # Legacy: MAJOR.MINOR.PATCH
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
        patch=$((patch + 1))
        echo "${major}.${minor}.${patch}"
    else
        log_error "Cannot increment version: $version"
        return 1
    fi
}

# Get next production version for hotfix
get_next_production_hotfix_version() {
    local platform_filter="${1:-}"
    local latest_production=$(get_latest_production_tag "$platform_filter")

    if [ -z "$latest_production" ]; then
        log_error "No production tags found. Cannot determine hotfix version."
        return 1
    fi

    increment_patch_version "$latest_production"
}

# =============================================================================
# PLATFORM CLASSIFICATION FUNCTIONS
# =============================================================================

# Get platform type from version string
# Uses COMMON_PLATFORMS and INDEPENDENT_PLATFORMS from configuration
get_platform_type_from_version() {
    local version="$1"

    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" != "true" ]; then
        echo "legacy"
        return 0
    fi

    local platform=$(extract_platform_from_version "$version")
    if [ -z "$platform" ]; then
        echo "unknown"
        return 1
    fi

    # Whole-word membership on a space-separated list. See the note in
    # git-trident-common.sh: a quoted right-hand side of =~ matches literally,
    # which reads as a regex match and is flagged by SC2076.
    case " $COMMON_PLATFORMS " in
        *" $platform "*) echo "common"; return 0 ;;
    esac

    case " $INDEPENDENT_PLATFORMS " in
        *" $platform "*) echo "independent"; return 0 ;;
    esac

    echo "unknown"
    return 1
}

# Check if propagation is allowed between two versions
# Based on platform classification rules
is_propagation_allowed() {
    local source_version="$1"
    local target_version="$2"

    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" != "true" ]; then
        return 0  # Always allow in legacy mode
    fi

    local source_platform=$(extract_platform_from_version "$source_version")
    local target_platform=$(extract_platform_from_version "$target_version")

    if [ -z "$source_platform" ] || [ -z "$target_platform" ]; then
        return 1
    fi

    # Same platform always allowed
    if [ "$source_platform" = "$target_platform" ]; then
        return 0
    fi

    local source_type=$(get_platform_type_from_version "$source_version")
    local target_type=$(get_platform_type_from_version "$target_version")

    # Common → Independent: allowed
    if [ "$source_type" = "common" ] && [ "$target_type" = "independent" ]; then
        return 0
    fi

    # All other combinations: not allowed
    return 1
}

# Get all dependent platforms for a source platform
# Returns empty if source is independent, all independent platforms if source is common
get_dependent_platforms_for_source() {
    local source_version="$1"

    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" != "true" ]; then
        echo ""
        return 0
    fi

    local source_type=$(get_platform_type_from_version "$source_version")

    if [ "$source_type" = "common" ]; then
        echo "$INDEPENDENT_PLATFORMS"
        return 0
    elif [ "$source_type" = "independent" ]; then
        local source_platform=$(extract_platform_from_version "$source_version")
        echo "$source_platform"  # Only self
        return 0
    fi

    echo ""
    return 1
}

# =============================================================================
# DEPRECATED/UNUSED FUNCTIONS
# =============================================================================
