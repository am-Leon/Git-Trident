#!/bin/bash
# Sync staging hotfix changes to newer staging versions
# Supports both single-environment and multi-platform modes with platform classification

# =============================================================================
# VALIDATION AND DETECTION FUNCTIONS (WITH PLATFORM SUPPORT)
# =============================================================================

validate_hotfix_version() {
    local hotfix_version="$1"

    # Auto-detect the latest RC for this version
    local latest_rc=$(get_latest_rc_for_version "$hotfix_version")
    if [ -z "$latest_rc" ]; then
        log_error "No staging releases found for version: $hotfix_version"
        log_info "Available staging versions:"
        git tag -l "${STAGING_TAG_PREFIX}*" | sed "s|^${STAGING_TAG_PREFIX}||" | sed "s|$(get_rc_suffix)[0-9]*$||" | sort -V | uniq
        return 1
    fi

    return 0
}

# Check if a tag should be included based on platform propagation rules
should_include_tag_for_propagation() {
    local source_version="$1"
    local target_tag="$2"

    local source_base=$(extract_base_version "$source_version")
    local target_version=$(extract_version_from_tag "$target_tag" "$STAGING_TAG_PREFIX")
    local target_base=$(extract_base_version "$target_version")

    # Legacy mode: only include if target has newer base version
    if ! is_platform_specific_mode; then
        if is_version_greater "$target_base" "$source_base"; then
            return 0  # Include
        else
            return 1  # Exclude
        fi
    fi

    # Platform-specific mode
    local source_type=$(get_platform_type_from_version "$source_version")
    local target_type=$(get_platform_type_from_version "$target_version")
    local source_platform=$(extract_platform_from_version "$source_version")
    local target_platform=$(extract_platform_from_version "$target_version")

    # Check if propagation is allowed between these platforms
    if ! is_propagation_allowed "$source_version" "$target_version"; then
        log_debug "Excluding $target_tag (propagation not allowed: $source_platform→$target_platform)"
        return 1
    fi

    # Common → Independent: always include (regardless of version)
    if [ "$source_type" = "common" ] && [ "$target_type" = "independent" ]; then
        log_debug "Including independent platform tag: $target_tag (common→independent propagation)"
        return 0
    fi

    # Same platform: only include if newer version
    if [ "$source_platform" = "$target_platform" ]; then
        if is_version_greater "$target_base" "$source_base"; then
            log_debug "Including newer same-platform tag: $target_tag ($target_base > $source_base)"
            return 0
        else
            log_debug "Excluding older same-platform tag: $target_tag ($target_base <= $source_base)"
            return 1
        fi
    fi

    # Common → Other Common (different common platform): not propagated
    if [ "$source_type" = "common" ] && [ "$target_type" = "common" ]; then
        log_debug "Excluding different common platform: $target_tag ($source_platform→$target_platform)"
        return 1
    fi

    # Should not reach here based on propagation rules
    log_debug "Excluding $target_tag (no matching propagation rule)"
    return 1
}

get_staging_tags_for_propagation() {
    local source_version="$1"

    local candidate_tags=""
    local staging_tags=$(get_all_staging_tags)

    for staging_tag in $staging_tags; do
        if should_include_tag_for_propagation "$source_version" "$staging_tag"; then
            candidate_tags="${candidate_tags}${staging_tag}"$'\n'
        fi
    done

    echo "$candidate_tags" | sed '/^$/d'
}

# Legacy function - kept for backward compatibility
get_staging_tags_newer_than_version() {
    local source_version="$1"
    get_staging_tags_for_propagation "$source_version"
}

find_affected_versions() {
    local hotfix_version="$1"
    local hotfix_tag="$2"

    # Get staging tags that should receive propagation
    local candidate_tags=$(get_staging_tags_for_propagation "$hotfix_version")

    if [ -z "$candidate_tags" ]; then
        echo ""  # Return empty string
        return 0
    fi

    # Get only the LATEST RC for each base version
    local latest_rcs_to_check=$(get_latest_rc_per_base_version "$candidate_tags")

    if [ -z "$latest_rcs_to_check" ]; then
        echo ""  # Return empty string
        return 0
    fi

    local affected_versions=""

    for tag in $latest_rcs_to_check; do
        # Check if this version already includes the hotfix
        if ! git merge-base --is-ancestor "$hotfix_tag" "$tag" 2>/dev/null; then
            affected_versions="${affected_versions}${tag}"$'\n'
        fi
    done

    # Return ONLY the affected versions (clean, no log messages)
    echo "$affected_versions" | sed '/^$/d'
}

# =============================================================================
# PROPAGATION OPERATIONS (WITH PLATFORM CLASSIFICATION)
# =============================================================================

create_propagation_temp_branch() {
    local base_version="$1"
    local latest_rc_tag="$2"

    local temp_branch="temp-propagate-${base_version//[^a-zA-Z0-9_-]/-}"

    # Create temp branch from the existing RC (not from staging branch)
    verify_step "Creating temporary branch from existing RC: $latest_rc_tag" \
        "git checkout -b '$temp_branch' '$latest_rc_tag'" \
        "On temporary branch: $temp_branch (from $latest_rc_tag)"

    echo "$temp_branch"
}

merge_hotfix_into_version() {
    local temp_branch="$1"
    local hotfix_tag="$2"
    local hotfix_version="$3"
    local hotfix_rc_number="$4"

    log_info "Merging hotfix: $hotfix_tag"

    if ! interactive_merge "$temp_branch" "$hotfix_tag" \
        "Propagate: Include staging hotfix $hotfix_version$(get_rc_suffix)$hotfix_rc_number" \
        "propagating hotfix to $hotfix_version"; then
        return 1
    fi

    return 0
}

create_propagated_tag() {
    local base_version="$1"
    local source_ref="$2"  # Branch, tag, or commit to tag from
    local next_rc_number="$3"
    local hotfix_version="$4"
    local hotfix_rc_number="$5"

    local new_tag="${STAGING_TAG_PREFIX}${base_version}$(get_rc_suffix)${next_rc_number}"

    # Check if new tag already exists
    if is_valid_tag "$new_tag"; then
        log_info "✓ Tag already exists: $new_tag (resume mode)"
        echo "$new_tag"
        return 0
    fi

    # Create tag from specific source reference (the temp branch with merged changes)
    verify_step "Creating new staging tag from $source_ref" \
        "git tag -a '$new_tag' '$source_ref' -m 'Updated staging release $base_version (includes hotfix $hotfix_version$(get_rc_suffix)$hotfix_rc_number)'" \
        "Created tag: $new_tag from $source_ref"

    echo "$new_tag"
}

integrate_propagated_changes() {
    local new_tag="$1"
    local base_version="$2"
    local hotfix_version="$3"
    local hotfix_rc_number="$4"

    log_info "🔄 Integrating propagated changes into staging..."
    git checkout "$STAGING_BRANCH"

    # Check if staging already has this tag
    if git merge-base --is-ancestor "$new_tag" "$STAGING_BRANCH" 2>/dev/null; then
        log_info "✓ Staging branch already includes propagated tag"
        return 0
    fi

    log_info "Merging $new_tag into $STAGING_BRANCH..."

    if ! interactive_merge "$STAGING_BRANCH" "$new_tag" \
        "Integrate: Propagated hotfix to $base_version" \
        "integrating $base_version into staging"; then
        log_error "Staging integration failed for $base_version"
        return 1
    fi

    log_info "✓ Staging branch updated with propagated changes"
    return 0
}

propagate_to_single_version() {
    local latest_rc_tag="$1"
    local hotfix_tag="$2"
    local hotfix_version="$3"
    local hotfix_rc_number="$4"

    local base_version=$(extract_base_version_from_tag "$latest_rc_tag" "$STAGING_TAG_PREFIX")
    local current_rc_number=$(extract_rc_number "$latest_rc_tag")
    local next_rc_number=$(get_next_rc_number_for_version "$base_version" "$current_rc_number")
    local new_tag="${STAGING_TAG_PREFIX}${base_version}$(get_rc_suffix)${next_rc_number}"

    # Extract platform info for logging
    local platform_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$base_version")
        local platform_type=$(get_platform_type_from_version "$base_version")
        platform_info=" (platform: $platform, type: $platform_type)"
    fi

    log_info "🔄 Processing: $latest_rc_tag$platform_info"
    log_info "   Current RC: $current_rc_number"
    log_info "   Next RC: $next_rc_number"
    log_info "   New tag: $new_tag"

    # Check if new tag already exists
    if git rev-parse "$new_tag" >/dev/null 2>&1; then
        log_info "   ✓ Tag already exists: $new_tag (resume mode)"
    else
        # Create temporary branch from the EXISTING RC (not from staging)
        local temp_branch=$(create_propagation_temp_branch "$base_version" "$latest_rc_tag")

        # Merge hotfix into the temp branch
        if ! merge_hotfix_into_version "$temp_branch" "$hotfix_tag" \
            "$hotfix_version" "$hotfix_rc_number"; then
            # Clean up temp branch on failure
            git checkout "$STAGING_BRANCH" >/dev/null 2>&1
            git branch -D "$temp_branch" >/dev/null 2>&1
            return 1
        fi

        # Create new tag from the temp branch (which has both old RC + hotfix)
        create_propagated_tag "$base_version" "$temp_branch" "$next_rc_number" \
            "$hotfix_version" "$hotfix_rc_number" > /dev/null

        # Clean up temp branch
        git checkout "$STAGING_BRANCH" >/dev/null 2>&1
        git branch -D "$temp_branch" >/dev/null 2>&1
    fi

    # Update staging branch with the new tag
    if ! integrate_propagated_changes "$new_tag" "$base_version" \
        "$hotfix_version" "$hotfix_rc_number"; then
        return 1
    fi

    # Sync to develop
    log_info "   🔄 Syncing to develop branch..."
    if ! sync_to_develop; then
        log_error "   ❌ Failed to sync develop branch for $base_version"
        return 1
    fi

    log_info "✓ Successfully propagated hotfix to $latest_rc_tag → $new_tag"
    return 0
}

# =============================================================================
# MAIN PROPAGATION FLOW (WITH PLATFORM CLASSIFICATION)
# =============================================================================

show_propagation_summary() {
    local affected_versions_array=("$@")
    local hotfix_version="${affected_versions_array[0]}"
    local hotfix_tag="${affected_versions_array[1]}"

    # Shift out the first two elements (hotfix_version and hotfix_tag)
    shift 2
    local affected_tags=("$@")

    # Extract platform info if in platform-specific mode
    local platform_info=""
    local propagation_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$hotfix_version")
        local platform_type=$(get_platform_type_from_version "$hotfix_version")
        platform_info=" (platform: $platform, type: $platform_type)"

        if [ "$platform_type" = "common" ]; then
            propagation_info="\n   - Common platform → Propagating to ALL dependent independent platforms"
        elif [ "$platform_type" = "independent" ]; then
            propagation_info="\n   - Independent platform → Propagating ONLY within same platform"
        fi
    fi

    log_info "🔄 Staging releases that need hotfix propagation:"
    for tag in "${affected_tags[@]}"; do
        local tag_platform_info=""
        if is_platform_specific_mode; then
            local tag_version=$(extract_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
            local tag_platform=$(extract_platform_from_version "$tag_version")
            local tag_platform_type=$(get_platform_type_from_version "$tag_version")
            tag_platform_info=" ($tag_platform_type)"
        fi
        log_info "  - $tag$tag_platform_info"
    done
    log_empty ""

    log_info "📝 Propagation Strategy:$propagation_info"
    log_info "   - Hotfix version: $hotfix_version$platform_info"
    log_info "   - Hotfix tag: $hotfix_tag"

    # Extract base versions from affected tags
    local base_versions_list=""
    for tag in "${affected_tags[@]}"; do
        local base_version=$(extract_base_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
        base_versions_list="$base_versions_list$base_version "
    done

    log_info "   - Newer base versions: $base_versions_list"
    log_info "   - Clean workflow:"
    log_info "     1. Tag-X + hotfix → Tag-X+1"
    log_info "     2. Tag-Y + Tag-X+1 → Tag-Y+1"
    log_empty ""
}

process_propagation_versions() {
    local affected_versions_array=("$@")
    local hotfix_tag="${affected_versions_array[0]}"
    local hotfix_version="${affected_versions_array[1]}"
    local hotfix_rc_number="${affected_versions_array[2]}"

    # Shift out the first three elements
    shift 3
    local affected_tags=("$@")

    local updated_count=0
    local total_count=${#affected_tags[@]}

    # Process each base version's latest RC
    for latest_rc_tag in "${affected_tags[@]}"; do
        if propagate_to_single_version "$latest_rc_tag" "$hotfix_tag" \
            "$hotfix_version" "$hotfix_rc_number"; then
            updated_count=$((updated_count + 1))
        else
            log_error "Failed to propagate to $latest_rc_tag"
            # Continue with other versions even if one fails
        fi
        echo ""
    done

    # Return as array: updated_count total_count
    echo "$updated_count $total_count"
}

show_propagation_completion_summary() {
    local updated_count="$1"
    local total_count="$2"
    local hotfix_version="$3"
    local hotfix_tag="$4"

    # Ensure counts are integers (strip any non-digit characters)
    updated_count=$(echo "$updated_count" | tr -cd '0-9')
    total_count=$(echo "$total_count" | tr -cd '0-9')

    # Default to 0 if empty
    updated_count=${updated_count:-0}
    total_count=${total_count:-0}

    # Platform info
    local platform_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$hotfix_version")
        local platform_type=$(get_platform_type_from_version "$hotfix_version")
        platform_info=" (platform: $platform, type: $platform_type)"
    fi

    log_info "🎉 Successfully propagated hotfix to $updated_count out of $total_count staging version(s)"

    if [ "$updated_count" -gt 0 ]; then
        log_info "📝 Summary:"
        log_info "   - Hotfix version: $hotfix_version$platform_info (using $hotfix_tag)"
        log_info "   - Created new RC releases for affected staging versions"
        log_info "   - Maintained clean merge chain"
        # Smart Auto Push
        if [ "${AUTO_PUSH_ON_FINISH:-false}" = "true" ]; then
            log_info "   - Auto-pushing changes..."
            if ! "$SCRIPT_DIR/../bin/git-trident-push-all" "$REMOTE"; then
                log_error "Auto-push failed or was incomplete. Run 'git trident push-all' manually."
            fi
        else
            log_info "   - Run 'git trident push-all' to push changes"
        fi
    fi
}

propagate_staging_hotfix() {
    local hotfix_version="$1"

    log_info "🔄 Propagating staging hotfix for version $hotfix_version to newer versions"
    log_info "=========================================="

    # Auto-detect the latest RC for this version
    local hotfix_tag=$(get_latest_rc_for_version "$hotfix_version")
    if [ -z "$hotfix_tag" ]; then
        log_error "No staging releases found for version: $hotfix_version"
        log_info "Available staging versions:"
        git tag -l "${STAGING_TAG_PREFIX}*" | sed "s|^${STAGING_TAG_PREFIX}||" | sed "s|$(get_rc_suffix)[0-9]*$||" | sort -V | uniq
        return 1
    fi

    local hotfix_rc_number=$(extract_rc_number "$hotfix_tag")
    log_info "Auto-detected latest hotfix: $hotfix_tag"

    # Validate hotfix tag exists
    if ! is_valid_tag "$hotfix_tag"; then
        log_error "Staging hotfix tag not found: $hotfix_tag"
        return 1
    fi

    # Get ALL staging tags that should receive propagation
    local all_candidate_tags=$(get_staging_tags_for_propagation "$hotfix_version")

    if [ -z "$all_candidate_tags" ]; then
        log_info "✅ No propagation needed - no candidate versions found"
        return 0
    fi

    # Get only the LATEST RC for each base version
    local latest_rcs_to_propagate=$(get_latest_rc_per_base_version "$all_candidate_tags")

    if [ -z "$latest_rcs_to_propagate" ]; then
        log_info "✅ No propagation needed after filtering latest RCs per version"
        return 0
    fi

    # Filter to only those that don't include the hotfix
    local latest_rcs_needing_hotfix=""
    for tag in $latest_rcs_to_propagate; do
        if ! git merge-base --is-ancestor "$hotfix_tag" "$tag" 2>/dev/null; then
            latest_rcs_needing_hotfix="${latest_rcs_needing_hotfix}${tag}"$'\n'
        fi
    done

    latest_rcs_needing_hotfix=$(echo "$latest_rcs_needing_hotfix" | sed '/^$/d')

    if [ -z "$latest_rcs_needing_hotfix" ]; then
        log_info "✅ No propagation needed - all latest versions include the hotfix"
        return 0
    fi

    # Convert affected versions to array
    IFS=$'\n' read -d '' -ra affected_tags <<< "$latest_rcs_needing_hotfix"

    # Build array for show_propagation_summary
    local summary_args=("$hotfix_version" "$hotfix_tag" "${affected_tags[@]}")
    show_propagation_summary "${summary_args[@]}"

    if ! confirm_action "Propagate staging hotfix $hotfix_tag to these newer versions?"; then
        log_info "Propagation cancelled"
        return 0
    fi

    # Initialize counters
    local updated_count=0
    local total_count=${#affected_tags[@]}

    # Process each version
    for latest_rc_tag in "${affected_tags[@]}"; do
        if propagate_to_single_version "$latest_rc_tag" "$hotfix_tag" \
            "$hotfix_version" "$hotfix_rc_number"; then
            updated_count=$((updated_count + 1))
        else
            log_error "Failed to propagate to $latest_rc_tag"
            # Continue with other versions even if one fails
        fi
        echo ""
    done

    show_propagation_completion_summary "$updated_count" "$total_count" "$hotfix_version" "$hotfix_tag"

    return "$([ "$updated_count" -gt 0 ] && echo 0 || echo 1)"
}

# =============================================================================
# DETECTION FUNCTION (--dry-run MODE WITH PLATFORM CLASSIFICATION)
# =============================================================================

show_detection_analysis() {
    local latest_rcs_to_check="$1"
    local hotfix_tag="$2"
    local hotfix_version="$3"

    local affected_versions_array=()
    local affected_count=0
    local total_count=0

    log_info "Analyzing latest RC for each base version:"
    for tag in $latest_rcs_to_check; do
        total_count=$((total_count + 1))
        local base_version=$(extract_base_version_from_tag "$tag" "$STAGING_TAG_PREFIX")

        # Check if this newer version includes the hotfix
        if ! git merge-base --is-ancestor "$hotfix_tag" "$tag" 2>/dev/null; then
            local platform_info=""
            if is_platform_specific_mode; then
                local platform=$(extract_platform_from_version "$base_version")
                local platform_type=$(get_platform_type_from_version "$base_version")
                platform_info=" ($platform_type)"
            fi
            log_warn "   ❌ $tag$platform_info is MISSING hotfix $hotfix_tag"
            affected_versions_array+=("$tag")
            affected_count=$((affected_count + 1))
        else
            log_info "   ✅ $tag includes the hotfix"
        fi
    done

    # Return as: "affected_count total_count hotfix_tag hotfix_version tag1 tag2 tag3..."
    echo "$affected_count $total_count $hotfix_tag $hotfix_version ${affected_versions_array[*]}"
}

show_detection_results() {
    local affected_count="$1"
    local total_count="$2"
    shift 2  # Remove affected_count and total_count from arguments
    local all_values=("$@")
    local hotfix_tag="${all_values[0]}"
    local hotfix_version="${all_values[1]}"

    # Remove hotfix_tag and hotfix_version from array
    shift 2
    local affected_versions_array=("$@")

    if [ "$affected_count" -gt 0 ]; then
        # Extract platform info if in platform-specific mode
        local platform_info=""
        local propagation_info=""
        if is_platform_specific_mode; then
            local platform=$(extract_platform_from_version "$hotfix_version")
            local platform_type=$(get_platform_type_from_version "$hotfix_version")
            platform_info=" (platform: $platform, type: $platform_type)"

            if [ "$platform_type" = "common" ]; then
                propagation_info="\n   - Common platform changes will propagate to ALL dependent independent platforms"
            elif [ "$platform_type" = "independent" ]; then
                propagation_info="\n   - Independent platform changes will stay WITHIN same platform"
            fi
        fi

        log_warn "📢 STAGING HOTFIX IMPACT DETECTED"
        log_info "The hotfix $hotfix_tag$platform_info is NOT included in $affected_count out of $total_count newer version(s):"

        for tag in "${affected_versions_array[@]}"; do
            local tag_platform_info=""
            if is_platform_specific_mode; then
                local tag_version=$(extract_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
                local tag_platform=$(extract_platform_from_version "$tag_version")
                local tag_platform_type=$(get_platform_type_from_version "$tag_version")
                tag_platform_info=" ($tag_platform_type)"
            fi
            log_info "   - $tag$tag_platform_info"
        done
        log_empty ""

        # Show which base versions need updates
        local affected_base_versions_list=""
        for tag in "${affected_versions_array[@]}"; do
            local base_version=$(extract_base_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
            affected_base_versions_list="$affected_base_versions_list$base_version "
        done

        log_info "Affected base versions: $affected_base_versions_list$propagation_info"
        log_empty ""
        log_info "🔄 Propagation would create:"
        for tag in "${affected_versions_array[@]}"; do
            local base_version=$(extract_base_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
            local current_rc=$(extract_rc_number "$tag")
            local next_rc=$(get_next_rc_number_for_version "$base_version" "$current_rc")
            log_info "   - $tag → ${STAGING_TAG_PREFIX}${base_version}$(get_rc_suffix)${next_rc}"
        done
        log_empty ""
        return 1  # Indicates action needed
    else
        log_info "✅ All $total_count newer staging versions include the hotfix $hotfix_tag"
        log_empty ""
        return 0
    fi
}

detect_staging_hotfix_impact() {
    local hotfix_version="$1"

    log_info "🔍 Checking impact of hotfix $hotfix_version on newer staging versions"
    log_info "=========================================="

    if ! validate_hotfix_version "$hotfix_version"; then
        return 1
    fi

    local hotfix_tag=$(get_latest_rc_for_version "$hotfix_version")
    local hotfix_rc_number=$(extract_rc_number "$hotfix_tag")

    log_info "Auto-detected latest hotfix: $hotfix_tag"
    log_empty ""

    # Get ALL staging tags that should receive propagation
    local all_candidate_tags=$(get_staging_tags_for_propagation "$hotfix_version")

    if [ -z "$all_candidate_tags" ]; then
        log_info "✅ No staging releases need propagation for $hotfix_version"
        return 0
    fi

    # Get only the LATEST RC for each base version
    local latest_rcs_to_check=$(get_latest_rc_per_base_version "$all_candidate_tags")

    if [ -z "$latest_rcs_to_check" ]; then
        log_info "✅ No staging releases need update after filtering latest RCs per version"
        return 0
    fi

    # Filter to only those that don't include the hotfix
    local latest_rcs_needing_hotfix=""
    for tag in $latest_rcs_to_check; do
        if ! git merge-base --is-ancestor "$hotfix_tag" "$tag" 2>/dev/null; then
            latest_rcs_needing_hotfix="${latest_rcs_needing_hotfix}${tag}"$'\n'
        fi
    done

    latest_rcs_needing_hotfix=$(echo "$latest_rcs_needing_hotfix" | sed '/^$/d')

    if [ -z "$latest_rcs_needing_hotfix" ]; then
        log_info "✅ All latest staging releases include the hotfix"
        return 0
    fi

    # Analyze and get results as array
    local analysis_result
    analysis_result=$(show_detection_analysis "$latest_rcs_needing_hotfix" "$hotfix_tag" "$hotfix_version")

    # Parse the result: first two values are counts, next two are hotfix info, rest are tags
    IFS=' ' read -r affected_count total_count hf_tag hf_version remaining <<< "$analysis_result"

    # Build array with all values
    local all_values=("$hf_tag" "$hf_version")

    # Parse remaining tags into array
    IFS=' ' read -ra tag_array <<< "$remaining"
    all_values+=("${tag_array[@]}")
    
    # Show results
    show_detection_results "$affected_count" "$total_count" "${all_values[@]}"
}