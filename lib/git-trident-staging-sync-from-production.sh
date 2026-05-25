#!/bin/bash
# Sync staging releases from production changes
# Supports both single-environment and multi-platform modes with platform classification

# =============================================================================
# DEPRECATED TAG VALIDATION (WITH PLATFORM SUPPORT)
# =============================================================================

validate_production_tag_not_deprecated() {
    local version="$1"
    local production_tag="${PRODUCTION_TAG_PREFIX}${version}"

    log_debug "Validating production tag: $production_tag"

    # Check if tag exists
    if ! is_valid_tag "$production_tag"; then
        log_error "Production tag not found: $production_tag"
        return 1
    fi

    # Extract base version
    local base_version=$(extract_base_version_from_tag "$production_tag" "$PRODUCTION_TAG_PREFIX")

    # In platform-specific mode, scope the "latest production" check to the SAME platform only.
    # Without this, android-1.2.0 would be flagged as deprecated when shared-1.2.1 exists,
    # even though they are independent platforms with independent version sequences.
    local latest_production
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        if [ -n "$platform" ]; then
            latest_production=$(get_latest_production_tag_for_platform "$platform")
            log_debug "Scoping deprecation check to platform: $platform (latest: $latest_production)"
        else
            latest_production=$(get_latest_production_tag)
        fi
    else
        latest_production=$(get_latest_production_tag)
    fi

    local latest_base=$(extract_base_version_from_tag "${PRODUCTION_TAG_PREFIX}${latest_production}" "$PRODUCTION_TAG_PREFIX")

    # Compare versions within the same platform scope
    if is_version_greater "$latest_base" "$base_version"; then
        log_error "❌ Production tag $production_tag is DEPRECATED!"
        log_info "A newer production version exists: $latest_production"
        log_info "Cannot sync from deprecated production versions."
        return 1
    fi

    log_info "✅ Production tag $production_tag is current (not deprecated)"
    return 0
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_production_sync_prerequisites() {
    local production_version="$1"
    local production_tag="${PRODUCTION_TAG_PREFIX}${production_version}"

    log_info "🔍 Validating production sync prerequisites..."

    # Validate production tag exists
    if ! is_valid_tag "$production_tag"; then
        log_error "Production tag not found: $production_tag"
        log_info "Available production tags:"
        show_available_tags "production"
        return 1
    fi

    # Validate version format
    if ! validate_production_version_format "$production_version"; then
        return 1
    fi

    # Validate production tag is not deprecated (not older than latest production)
    if ! validate_production_tag_not_deprecated "$production_version"; then
        return 1
    fi

    log_info "✓ Production sync prerequisites validated"
    return 0
}

# =============================================================================
# TAG ANALYSIS FUNCTIONS (WITH PLATFORM CLASSIFICATION)
# =============================================================================

# Check if a staging tag should receive production changes based on platform rules
should_include_tag_for_production_sync() {
    local production_version="$1"
    local staging_tag="$2"

    local production_base=$(extract_base_version "$production_version")
    local staging_version=$(extract_version_from_tag "$staging_tag" "$STAGING_TAG_PREFIX")
    local staging_base=$(extract_base_version "$staging_version")

    # Legacy mode: only include if staging has newer base version than production
    if ! is_platform_specific_mode; then
        if is_version_greater "$staging_base" "$production_base"; then
            return 0  # Include
        else
            return 1  # Exclude
        fi
    fi

    # Platform-specific mode
    local production_type=$(get_platform_type_from_version "$production_version")
    local staging_type=$(get_platform_type_from_version "$staging_version")
    local production_platform=$(extract_platform_from_version "$production_version")
    local staging_platform=$(extract_platform_from_version "$staging_version")

    # Check if propagation is allowed between these platforms
    if ! is_propagation_allowed "$production_version" "$staging_version"; then
        log_debug "Excluding $staging_tag (propagation not allowed: $production_platform→$staging_platform)"
        return 1
    fi

    # Common → Independent: always include (regardless of version)
    if [ "$production_type" = "common" ] && [ "$staging_type" = "independent" ]; then
        log_debug "Including independent platform tag: $staging_tag (common→independent propagation)"
        return 0
    fi

    # Same platform: only include if staging version is newer than production
    if [ "$production_platform" = "$staging_platform" ]; then
        if is_version_greater "$staging_base" "$production_base"; then
            log_debug "Including newer same-platform tag: $staging_tag ($staging_base > $production_base)"
            return 0
        else
            log_debug "Excluding older same-platform tag: $staging_tag ($staging_base <= $production_base)"
            return 1
        fi
    fi

    # Common → Other Common (different common platform): not propagated
    if [ "$production_type" = "common" ] && [ "$staging_type" = "common" ]; then
        log_debug "Excluding different common platform: $staging_tag ($production_platform→$staging_platform)"
        return 1
    fi

    # Should not reach here based on propagation rules
    log_debug "Excluding $staging_tag (no matching propagation rule)"
    return 1
}

get_staging_tags_for_production_sync() {
    local production_version="$1"

    local candidate_tags=""
    local staging_tags=$(get_all_staging_tags)

    for staging_tag in $staging_tags; do
        if should_include_tag_for_production_sync "$production_version" "$staging_tag"; then
            candidate_tags="${candidate_tags}${staging_tag}"$'\n'
        fi
    done

    echo "$candidate_tags" | sed '/^$/d'
}

find_outdated_staging_tags() {
    local production_version="$1"
    local production_tag="${PRODUCTION_TAG_PREFIX}${production_version}"

    log_debug "Finding staging tags outdated by production $production_version..."

    # Get ALL staging tags that should receive production changes
    local all_candidate_tags=$(get_staging_tags_for_production_sync "$production_version")

    if [ -z "$all_candidate_tags" ]; then
        echo ""  # Return empty string
        return 0
    fi

    # Get only the LATEST RC for each base version
    local latest_rcs=$(get_latest_rc_per_base_version "$all_candidate_tags")

    if [ -z "$latest_rcs" ]; then
        echo ""  # Return empty string
        return 0
    fi

    # Find which latest RCs don't include production changes
    local outdated_latest_tags=""
    local production_commit=$(git rev-parse "$production_tag")

    for staging_tag in $latest_rcs; do
        # Check if this latest version includes the production changes
        if ! git merge-base --is-ancestor "$production_commit" "$staging_tag" 2>/dev/null; then
            outdated_latest_tags="${outdated_latest_tags}${staging_tag}"$'\n'
            log_debug "Found outdated latest RC: $staging_tag"
        else
            log_debug "Latest RC is up-to-date: $staging_tag"
        fi
    done

    echo "$outdated_latest_tags" | sed '/^$/d'
}

# =============================================================================
# SINGLE VERSION PROCESSING (WITH PLATFORM SUPPORT)
# =============================================================================

create_rebase_temp_branch() {
    local base_version="$1"
    local latest_rc_tag="$2"

    # Create temp branch from the outdated RC tag (not from staging branch)
    local temp_branch="temp-rebase-${base_version//[^a-zA-Z0-9_-]/-}"

    verify_step "Creating temporary branch from outdated RC: $latest_rc_tag" \
        "git checkout -b '$temp_branch' '$latest_rc_tag'" \
        "On temporary branch: $temp_branch (from $latest_rc_tag)"

    echo "$temp_branch"
}

merge_production_changes_into_temp() {
    local temp_branch="$1"
    local production_commit="$2"
    local production_version="$3"
    local base_version="$4"

    log_info "Merging production $production_version into $base_version..."

    if ! interactive_merge "$temp_branch" "$production_commit" \
        "Rebase: Include production $production_version changes in $base_version" \
        "rebasing $base_version with production changes"; then
        return 1
    fi

    return 0
}

verify_production_changes_included() {
    local temp_branch="$1"
    local production_commit="$2"

    if git merge-base --is-ancestor "$production_commit" "$temp_branch" 2>/dev/null; then
        log_info "✓ Production changes successfully included"
        return 0
    else
        log_error "✗ Production changes NOT included in merge"
        return 1
    fi
}

create_rebased_tag() {
    local base_version="$1"
    local source_ref="$2"  # Branch, tag, or commit to tag from
    local next_rc_number="$3"
    local production_version="$4"

    local new_tag="${STAGING_TAG_PREFIX}${base_version}$(get_rc_suffix)${next_rc_number}"

    # Check if new tag already exists
    if git rev-parse "$new_tag" >/dev/null 2>&1; then
        log_info "✓ Tag already exists: $new_tag (resume mode)"
        echo "$new_tag"
        return 0
    fi

    # Create tag from specific source reference
    verify_step "Creating new staging tag from $source_ref" \
        "git tag -a '$new_tag' '$source_ref' -m 'Rebased staging release $base_version (includes production $production_version)'" \
        "Created tag: $new_tag from $source_ref"

    echo "$new_tag"
}

integrate_into_staging_branch() {
    local new_tag="$1"
    local base_version="$2"
    local production_version="$3"

    log_info "🔄 Integrating rebased changes into staging..."
    git checkout "$STAGING_BRANCH"

    # Check if staging already has this tag
    if git merge-base --is-ancestor "$new_tag" "$STAGING_BRANCH" 2>/dev/null; then
        log_info "✓ Staging branch already includes rebased tag"
        return 0
    fi

    # Merge new tag into staging
    if ! interactive_merge "$STAGING_BRANCH" "$new_tag" \
        "Update: Rebased $base_version with production $production_version" \
        "integrating $base_version into staging"; then
        log_error "Staging integration failed for $base_version"
        return 1
    fi

    log_info "✓ Staging branch updated"
    return 0
}

process_single_staging_version() {
    local latest_rc_tag="$1"
    local production_version="$2"
    local production_commit="$3"

    local base_version=$(extract_base_version_from_tag "$latest_rc_tag" "$STAGING_TAG_PREFIX")
    local rc_number=$(extract_rc_number "$latest_rc_tag")
    local next_rc_number=$(get_next_rc_number_for_version "$base_version" "$rc_number")
    local new_tag="${STAGING_TAG_PREFIX}${base_version}$(get_rc_suffix)${next_rc_number}"

    # Extract platform info for logging
    local platform_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$base_version")
        local platform_type=$(get_platform_type_from_version "$base_version")
        platform_info=" (platform: $platform, type: $platform_type)"
    fi

    log_info "🔄 Processing: $latest_rc_tag$platform_info"
    log_info "   Current RC: $rc_number"
    log_info "   Next RC: $next_rc_number"
    log_info "   New tag: $new_tag"

    # Check if new tag already exists
    if git rev-parse "$new_tag" >/dev/null 2>&1; then
        log_info "   ✓ Tag already exists: $new_tag (resume mode)"
    else
        # Create temporary branch from the OUTDATED RC TAG (not from staging)
        local temp_branch=$(create_rebase_temp_branch "$base_version" "$latest_rc_tag")

        # Merge production changes into the temp branch
        if ! merge_production_changes_into_temp "$temp_branch" "$production_commit" \
            "$production_version" "$base_version"; then
            # Clean up temp branch on failure
            git checkout "$STAGING_BRANCH" >/dev/null 2>&1
            git branch -D "$temp_branch" >/dev/null 2>&1
            return 1
        fi

        # Verify that production changes are included
        if ! verify_production_changes_included "$temp_branch" "$production_commit"; then
            git checkout "$STAGING_BRANCH" >/dev/null 2>&1
            git branch -D "$temp_branch" >/dev/null 2>&1
            return 1
        fi

        # Create new tag from the temp branch
        create_rebased_tag "$base_version" "$temp_branch" "$next_rc_number" "$production_version" > /dev/null

        # Clean up temp branch
        git checkout "$STAGING_BRANCH" >/dev/null 2>&1
        git branch -D "$temp_branch" >/dev/null 2>&1
    fi

    # Update staging branch with the new tag
    if ! integrate_into_staging_branch "$new_tag" "$base_version" "$production_version"; then
        return 1
    fi

    log_info "✓ Successfully rebased $latest_rc_tag → $new_tag"
    log_info "   ⚠️  Old tag $latest_rc_tag is now DEPRECATED and should not be promoted"
    return 0
}

# =============================================================================
# MAIN REBASE OPERATIONS (WITH PLATFORM CLASSIFICATION)
# =============================================================================

show_rebase_summary() {
    local production_version="$1"
    shift
    local latest_rcs_to_rebase=("$@")

    log_info "🔄 Staging releases that need rebase (latest RC per base version only):"
    for tag in "${latest_rcs_to_rebase[@]}"; do
        local platform_info=""
        if is_platform_specific_mode; then
            local version=$(extract_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
            local platform=$(extract_platform_from_version "$version")
            local platform_type=$(get_platform_type_from_version "$version")
            platform_info=" ($platform_type)"
        fi
        log_info "  - $tag$platform_info"
    done
    log_empty ""

    # Extract platform info if in platform-specific mode
    local platform_info=""
    local propagation_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$production_version")
        local platform_type=$(get_platform_type_from_version "$production_version")
        platform_info=" (platform: $platform, type: $platform_type)"

        if [ "$platform_type" = "common" ]; then
            propagation_info="\n \t - Common platform → Propagating to ALL dependent independent platforms"
        elif [ "$platform_type" = "independent" ]; then
            propagation_info="\n   - Independent platform → Propagating ONLY within same platform"
        fi
    fi

    log_info "📝 Rebase Strategy:"
    log_info "  - Production version: $production_version$platform_info$propagation_info"

    # Extract base versions from tags
    local base_versions_list=""
    for tag in "${latest_rcs_to_rebase[@]}"; do
        local base_version=$(extract_base_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
        base_versions_list="$base_versions_list$base_version "
    done

    log_info "  - Newer base versions than production: $base_versions_list"
    log_info "  - Latest RC per base version only"
    log_info "  - Each new RC includes: previous RC + production changes"
    log_info "  - Base versions are independent (no cross-version merging)"
    log_info "  - Clean workflow:"
    log_info "    1. Tag-X + production → Tag-X+1"
    log_info "    2. Tag-Y + Tag-X+1 → Tag-Y+1"
    log_empty ""
}

process_rebase_versions() {
    local production_version="$1"
    local production_commit="$2"
    shift 2
    local latest_rcs_to_rebase=("$@")

    local rebased_count=0
    local total_count=${#latest_rcs_to_rebase[@]}

    # Process each base version's latest RC
    for latest_rc_tag in "${latest_rcs_to_rebase[@]}"; do
        if process_single_staging_version "$latest_rc_tag" "$production_version" "$production_commit"; then
            rebased_count=$((rebased_count + 1))
        fi
        echo ""
    done

    # Use array approach: return space-separated values
    echo "$rebased_count $total_count"
}

show_rebase_completion_summary() {
    local rebased_count="$1"
    local total_count="$2"
    local production_version="$3"

    # Ensure counts are integers (strip any non-digit characters)
    rebased_count=$(echo "$rebased_count" | tr -cd '0-9')
    total_count=$(echo "$total_count" | tr -cd '0-9')

    # Default to 0 if empty
    rebased_count=${rebased_count:-0}
    total_count=${total_count:-0}

    # Platform info
    local platform_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$production_version")
        local platform_type=$(get_platform_type_from_version "$production_version")
        platform_info=" (platform: $platform, type: $platform_type)"
    fi

    log_info "🎉 Successfully rebased $rebased_count out of $total_count staging version(s)"
    log_info "📝 Summary:"
    log_info "   - Production version: $production_version$platform_info"
    log_info "   - Created new RC releases for outdated staging versions"
    log_info "   - Only newer base versions than production were processed"
    log_info "   - Only latest RC per base version was rebased"
    log_info "   - Each new RC includes: previous RC + production changes"
    log_info "   - Clean merge chain maintained"
    log_info "   - OLD TAGS ARE NOW DEPRECATED and should NOT be promoted"

    if [ "$rebased_count" -gt 0 ]; then
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

rebase_staging_releases() {
    local production_version="$1"

    log_info "🔄 Rebasing staging releases after production $production_version"
    log_info "=========================================="

    # Validate prerequisites
    if ! validate_production_sync_prerequisites "$production_version"; then
        return 1
    fi

    local production_tag="${PRODUCTION_TAG_PREFIX}${production_version}"
    local production_commit=$(git rev-parse "$production_tag")

    # Get ALL staging tags that should receive production changes
    local all_candidate_tags=$(get_staging_tags_for_production_sync "$production_version")

    if [ -z "$all_candidate_tags" ]; then
        log_info "✅ No staging releases need rebase"
        return 0
    fi

    # Get only the LATEST RC for each base version
    local latest_rcs_to_rebase=$(get_latest_rc_per_base_version "$all_candidate_tags")

    if [ -z "$latest_rcs_to_rebase" ]; then
        log_info "✅ No staging releases need rebase after filtering latest RCs per version"
        return 0
    fi

    # Filter to only those that don't include production changes
    local latest_rcs_needing_rebase=""
    for tag in $latest_rcs_to_rebase; do
        if ! git merge-base --is-ancestor "$production_commit" "$tag" 2>/dev/null; then
            latest_rcs_needing_rebase="${latest_rcs_needing_rebase}${tag}"$'\n'
        fi
    done

    latest_rcs_needing_rebase=$(echo "$latest_rcs_needing_rebase" | sed '/^$/d')

    if [ -z "$latest_rcs_needing_rebase" ]; then
        log_info "✅ All latest staging releases already include production changes"
        return 0
    fi

    # Convert to array for processing
    IFS=$'\n' read -d '' -ra latest_rcs_array <<< "$latest_rcs_needing_rebase"

    # Show what will be rebased
    log_info "Latest staging releases that need to include production $production_version:"
    for tag in "${latest_rcs_array[@]}"; do
        local platform_info=""
        if is_platform_specific_mode; then
            local version=$(extract_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
            local platform=$(extract_platform_from_version "$version")
            local platform_type=$(get_platform_type_from_version "$version")
            platform_info=" ($platform_type)"
        fi
        log_info "  - $tag$platform_info"
    done
    log_empty ""

    # Build arguments array
    local summary_args=("$production_version" "${latest_rcs_array[@]}")
    show_rebase_summary "${summary_args[@]}"

    if ! confirm_action "Rebase these staging releases to include production changes $production_version?"; then
        log_info "Rebase cancelled"
        return 0
    fi

    # Process versions directly and track counts
    local rebased_count=0
    local total_count=${#latest_rcs_array[@]}

    for latest_rc_tag in "${latest_rcs_array[@]}"; do
        if process_single_staging_version "$latest_rc_tag" "$production_version" "$production_commit"; then
            rebased_count=$((rebased_count + 1))
        fi
        echo ""
    done

    # Sync staging to develop
    if [ "$rebased_count" -gt 0 ]; then
        if ! sync_to_develop "rebased"; then
            log_warn "⚠️  Rebase completed but develop sync has conflicts"
            log_info "Please resolve develop conflicts manually"
        fi
    fi

    show_rebase_completion_summary "$rebased_count" "$total_count" "$production_version"

    return "$([ "$rebased_count" -gt 0 ] && echo 0 || echo 1)"
}

# =============================================================================
# DETECTION OPERATIONS (CHECK-ONLY MODE) WITH PLATFORM SUPPORT
# =============================================================================

show_detection_analysis() {
    local latest_rcs_to_check="$1"
    local production_version="$2"
    local production_tag="$3"

    local affected_versions_array=()
    local affected_count=0
    local total_count=0

    log_info "Analyzing latest RC for each base version:"
    for tag in $latest_rcs_to_check; do
        total_count=$((total_count + 1))

        # Check if this newer version includes the production changes
        if ! git merge-base --is-ancestor "$production_tag" "$tag" 2>/dev/null; then
            local platform_info=""
            if is_platform_specific_mode; then
                local version=$(extract_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
                local platform=$(extract_platform_from_version "$version")
                local platform_type=$(get_platform_type_from_version "$version")
                platform_info=" ($platform_type)"
            fi
            log_warn "   ❌ $tag$platform_info is MISSING production changes $production_tag"
            affected_versions_array+=("$tag")
            affected_count=$((affected_count + 1))
        else
            log_info "   ✅ $tag includes production changes"
        fi
    done

    # Return as: "affected_count total_count production_version production_tag tag1 tag2 tag3..."
    echo "$affected_count $total_count $production_version $production_tag ${affected_versions_array[*]}"
}

show_detection_summary() {
    local affected_count="$1"
    local total_count="$2"
    shift 2  # Remove affected_count and total_count from arguments
    local all_values=("$@")
    local production_version="${all_values[0]}"
    local production_tag="${all_values[1]}"

    # Remove production_version and production_tag from array
    shift 2
    local affected_versions_array=("$@")

    if [ "$affected_count" -gt 0 ]; then
        # Extract platform info if in platform-specific mode
        local platform_info=""
        local propagation_info=""
        if is_platform_specific_mode; then
            local platform=$(extract_platform_from_version "$production_version")
            local platform_type=$(get_platform_type_from_version "$production_version")
            platform_info=" (platform: $platform, type: $platform_type)"

            if [ "$platform_type" = "common" ]; then
                propagation_info="\n   - Common platform changes will propagate to ALL dependent independent platforms"
            elif [ "$platform_type" = "independent" ]; then
                propagation_info="\n   - Independent platform changes will stay WITHIN same platform"
            fi
        fi

        log_warn "⚠️  STAGING RELEASES NEED REBASE:"
        log_info "The following staging releases are based on commits before production $production_version$platform_info:"

        for tag in "${affected_versions_array[@]}"; do
            local tag_platform_info=""
            if is_platform_specific_mode; then
                local version=$(extract_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
                local platform=$(extract_platform_from_version "$version")
                local platform_type=$(get_platform_type_from_version "$version")
                tag_platform_info=" ($platform_type)"
            fi
            log_info "   - $tag$tag_platform_info"
        done
        log_empty ""

        log_info "🔄 Rebase would create:$propagation_info"
        for tag in "${affected_versions_array[@]}"; do
            local base_version=$(extract_base_version_from_tag "$tag" "$STAGING_TAG_PREFIX")
            local current_rc=$(extract_rc_number "$tag")
            local next_rc=$(get_next_rc_number_for_version "$base_version" "$current_rc")
            log_info "   - $tag → ${STAGING_TAG_PREFIX}${base_version}$(get_rc_suffix)${next_rc}"
        done
        log_empty ""

        log_info "💡 Recommended action:"
        log_info "   Run: git trident staging sync-tags $production_version"
    fi
}

check_staging_releases_need_rebase() {
    local production_version="$1"
    local production_tag="${PRODUCTION_TAG_PREFIX}${production_version}"

    log_info "🔍 Checking if staging releases need rebase after production $production_version..."

    # Validate prerequisites
    if ! validate_production_sync_prerequisites "$production_version"; then
        return 1
    fi

    # Get ALL staging tags that should receive production changes (based on platform rules)
    local all_candidate_tags=$(get_staging_tags_for_production_sync "$production_version")

    if [ -z "$all_candidate_tags" ]; then
        log_info "✅ No staging releases need rebase"
        return 0
    fi

    # Get only the LATEST RC for each base version
    local latest_rcs_to_check=$(get_latest_rc_per_base_version "$all_candidate_tags")

    if [ -z "$latest_rcs_to_check" ]; then
        log_info "✅ No staging releases need rebase after filtering latest RCs per version"
        return 0
    fi

    # Find which of the latest RCs don't include production changes
    local outdated_latest_tags=""
    local production_commit=$(git rev-parse "$production_tag")

    for tag in $latest_rcs_to_check; do
        # Check if this latest RC already includes the production changes
        if ! git merge-base --is-ancestor "$production_commit" "$tag" 2>/dev/null; then
            outdated_latest_tags="${outdated_latest_tags}${tag}"$'\n'
            log_debug "Latest RC is outdated: $tag"
        else
            log_debug "Latest RC is up-to-date: $tag"
        fi
    done

    outdated_latest_tags=$(echo "$outdated_latest_tags" | sed '/^$/d')

    if [ -z "$outdated_latest_tags" ]; then
        log_info "✅ All latest staging releases include production changes"
        return 0
    fi

    # Analyze and get results
    local analysis_result
    analysis_result=$(show_detection_analysis "$outdated_latest_tags" "$production_version" "$production_tag")

    # Parse the result: first two values are counts, next two are production info, rest are tags
    IFS=' ' read -r affected_count total_count prod_version prod_tag remaining <<< "$analysis_result"

    # Build array with all values
    local all_values=("$prod_version" "$prod_tag")

    # Parse remaining tags into array
    IFS=' ' read -ra tag_array <<< "$remaining"
    all_values+=("${tag_array[@]}")

    # Build arguments array for show_detection_summary
    local summary_args=("$affected_count" "$total_count" "${all_values[@]}")
    show_detection_summary "${summary_args[@]}"

    # Return 1 if action needed, 0 if no action needed
    return "$([ "$affected_count" -gt 0 ] && echo 1 || echo 0)"
}