#!/bin/bash
# Git Trident Version Utilities - Comprehensive tag and version management
# Supports both single-environment and multi-platform modes

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
    local suffix="$(get_rc_suffix)"

    if [[ "$version" =~ .*${suffix}([0-9][0-9]*)$ ]]; then
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
    if [[ ! "$version" =~ ^([a-zA-Z0-9_-]+)-([0-9]+)\.([0-9]+)\.([0-9]+)(${suffix}[0-9]+)?$ ]]; then
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
    if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(${suffix}[0-9]+)?$ ]]; then
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

get_rc_suffix(){
  echo "${STAGING_TAG_SUFFIX:--rc-}"
}

# Get next RC number for a version
get_next_rc_number() {
    local version="$1"
    local lock_file=".git/git-trident-rc-lock"

    # Simple locking mechanism to prevent race conditions
    local max_wait=10
    local waited=0
    while [ -f "$lock_file" ] && [ $waited -lt $max_wait ]; do
        sleep 0.5
        waited=$((waited + 1))
    done
    touch "$lock_file"

    local latest_rc=$(get_latest_rc_for_version "$version")
    local next_rc="01"

    if [ -n "$latest_rc" ]; then
        local current_rc=$(extract_rc_number "$latest_rc")
        if [ -n "$current_rc" ]; then
            # Remove leading zeros for arithmetic
            local current_num=$(echo "$current_rc" | sed 's/^0*//')
            next_rc=$(printf "%02d" $((current_num + 1)))
        fi
    fi

    # Release lock
    rm -f "$lock_file"
    echo "$next_rc"
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

    # Remove RC suffix if present
    echo "$version" | sed "s|${suffix}[0-9]*$||"
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
validate_staging_tag_promotable() {
    local staging_tag="$1"
    local production_version="$2"

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

    # Check if platform is common
    if [[ " $COMMON_PLATFORMS " =~ " $platform " ]]; then
        echo "common"
        return 0
    fi

    # Check if platform is independent
    if [[ " $INDEPENDENT_PLATFORMS " =~ " $platform " ]]; then
        echo "independent"
        return 0
    fi

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

# Extract full version without RC suffix
# Input: android-1.2.3-rc-01 → Output: android-1.2.3
# Input: 1.2.3-rc-01 → Output: 1.2.3
extract_version_without_rc() {
    local version="$1"
    local suffix="$(get_rc_suffix)"

    if [[ "$version" =~ ^(.+)${suffix}[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$version"
    fi
}

# Get latest staging base version
get_latest_staging_base_version() {
    local platform_filter="${1:-}"

    # Get all staging tags and extract unique base versions
    local tags=$(get_all_staging_tags "$platform_filter")
    local suffix="$(get_rc_suffix)"

    echo "$tags" | \
    sed "s|^${STAGING_TAG_PREFIX}||" | \
    sed "s|${suffix}[0-9]*$||" | \
    sort -V | \
    uniq | \
    tail -1
}

# Filter tags by propagation rules
# Returns only tags that should receive changes from source version
filter_tags_by_propagation_rules() {
    local source_version="$1"
    local target_tags="$2"

    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" != "true" ]; then
        echo "$target_tags"  # Return all in legacy mode
        return 0
    fi

    local filtered_tags=""

    for target_tag in $target_tags; do
        local target_version=$(extract_version_from_tag "$target_tag" "$STAGING_TAG_PREFIX")

        if is_propagation_allowed "$source_version" "$target_version"; then
            filtered_tags="${filtered_tags}${target_tag}"$'\n'
        fi
    done

    echo "$filtered_tags" | sed '/^$/d'
}

# Enhanced version validation with classification info (optional)
validate_version_with_classification() {
    local version="$1"
    local context="$2"  # "production", "staging", or empty

    # Use existing validation functions
    local result=0
    if [ "$context" = "production" ]; then
        validate_production_version_format "$version"
        result=$?
    elif [ "$context" = "staging" ]; then
        validate_staging_version_format "$version"
        result=$?
    else
        validate_version_format "$version"
        result=$?
    fi

    # If validation failed and we're in platform-specific mode, show classification info
    if [ $result -ne 0 ] && [ "${PLATFORM_SPECIFIC_TAGS:-false}" = "true" ]; then
        if [ -n "$COMMON_PLATFORMS" ] || [ -n "$INDEPENDENT_PLATFORMS" ]; then
            log_info "Common platforms: $COMMON_PLATFORMS"
            log_info "Independent platforms: $INDEPENDENT_PLATFORMS"
            log_info "Propagation rules:"
            log_info "  • Common → Independent: Always propagate"
            log_info "  • Independent → Other: Never propagate"
        fi
    fi

    return $result
}

# Show platform classification summary
show_platform_classification_summary() {
    local version="$1"

    if [ "${PLATFORM_SPECIFIC_TAGS:-false}" != "true" ]; then
        return 0
    fi

    local platform=$(extract_platform_from_version "$version")
    if [ -z "$platform" ]; then
        return 1
    fi

    local platform_type=$(get_platform_type_from_version "$version")

    case "$platform_type" in
        "common")
            log_info "📋 Platform classification: $platform (COMMON)"
            log_info "   → Propagates to: $INDEPENDENT_PLATFORMS"
            ;;
        "independent")
            log_info "📋 Platform classification: $platform (INDEPENDENT)"
            log_info "   → Propagates to: $platform only"
            ;;
        "legacy")
            log_info "📋 Platform classification: Single-environment mode"
            ;;
        *)
            log_warn "Platform classification unknown for: $platform"
            ;;
    esac
}
