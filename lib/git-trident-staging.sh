#!/bin/bash
# Git Trident Staging Operations - Release and Hotfix Management
# Supports both single-environment and multi-platform modes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Only source common utilities if not already sourced
if [[ -z "${CONFIG_LOADED:-}" ]] || [[ "$CONFIG_LOADED" != "true" ]]; then
    source "$SCRIPT_DIR/git-trident-common.sh"
fi

# Always source version utils (they don't have initialization side effects)
source "$SCRIPT_DIR/git-trident-version-utils.sh"

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_release_branch_exists() {
    local version="$1"
    local release_branch="${RELEASE_STAGING_PREFIX}${version}"

    if check_branch_exists "$release_branch"; then
        log_info "✓ Release branch exists: $release_branch"
        return 0
    else
        log_error "Release branch not found: $release_branch"
        log_info "You need to run: git trident staging release start $version"
        return 1
    fi
}

validate_hotfix_branch_exists() {
    local version="$1"
    local hotfix_branch="${HOTFIX_STAGING_PREFIX}${version}"

    if check_branch_exists "$hotfix_branch"; then
        log_info "✓ Hotfix branch exists: $hotfix_branch"
        return 0
    else
        log_error "Hotfix branch not found: $hotfix_branch"
        log_info "You need to run: git trident staging hotfix start $version"
        return 1
    fi
}

validate_version_not_in_production() {
    local version="$1"
    local context="${2:-staging}"  # "staging" or "production"

    local production_tag="${PRODUCTION_TAG_PREFIX}${version}"

    if is_valid_tag "$production_tag"; then
        if [ "$context" = "staging" ]; then
            log_error "❌ Version $version is already RELEASED TO PRODUCTION!"
            log_info "Production tag exists: $production_tag"
            log_empty ""
            log_info "You cannot perform STAGING operations on versions already in production."
            log_info "For production operations, use: git trident production <command>"
        else
            log_error "❌ Version $version is already in production!"
            log_info "Production tag exists: $production_tag"
            log_empty ""
            log_info "Cannot release the same version to production twice."
            log_info "Use a new version number for the next release."
        fi
        return 1
    fi

    return 0
}

# =============================================================================
# RELEASE VALIDATION AND PREPARATION (WITH PLATFORM SUPPORT)
# =============================================================================

validate_new_base_version() {
    local version="$1"

    # Validate: Must be pure base version for new releases
    if ! validate_staging_version_format "$version"; then
        exit 1
    fi

    # Check if this base version already has any RCs
    local existing_rcs=$(get_staging_tags_for_version "$version")
    if [ -n "$existing_rcs" ]; then
        log_error "Version $version already has RC releases:"
        log_info "$existing_rcs"
        log_empty ""
        log_info "Use 'staging hotfix' to create new RCs for existing versions"
        log_info "Use 'staging release' only for NEW base versions"
        exit 1
    fi

    return 0
}

get_release_starting_point() {
    local from_tag="${1:-}"
    
    if [ -n "$from_tag" ]; then
        # Validate the tag/commit exists
        if ! is_valid_tag "$from_tag" && ! git rev-parse "$from_tag" >/dev/null 2>&1; then
            log_error "Tag or commit not found: $from_tag"
            exit 1
        fi
        echo "$from_tag"
    else
        echo "$DEVELOP_BRANCH"
    fi
}

# =============================================================================
# STAGING RELEASE OPERATIONS (NEW BASE VERSION WITH PLATFORM SUPPORT)
# =============================================================================

create_staging_release_branch() {
    local version="$1"
    local starting_point="$2"
    
    local release_branch="${RELEASE_STAGING_PREFIX}${version}"
    local suffix="$(get_rc_suffix)"
    local rc_number="01"  # First RC for new base version
    local staging_tag="${STAGING_TAG_PREFIX}${version}${suffix}${rc_number}"

    log_info "🚀 STARTING NEW STAGING RELEASE: $version"
    
    # Show platform info if in platform-specific mode
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        log_info "Platform: $platform"
    fi
    
    log_info "This will create the FIRST RC for this base version"
    log_info "RC Number: $rc_number"
    log_info "Will create tag: $staging_tag"
    
    if [ "$starting_point" != "$DEVELOP_BRANCH" ]; then
        log_info "Starting from: $starting_point"
    else
        log_info "Starting from latest develop branch"
    fi
    
    log_info "=========================================="

    assert_clean_working_tree

    # Checkout starting point
    verify_step "Checking out: $starting_point" \
        "git checkout '$starting_point'" \
        "On: $starting_point"

    # Create staging release branch
    verify_step "Creating staging release branch" \
        "git checkout -b $release_branch" \
        "Created and switched to $release_branch"
}

show_release_preparation_summary() {
    local release_branch="$1"
    local version="$2"
    local starting_point="$3"
    
    log_info "🎉 Staging release branch ready: $release_branch"
    log_empty ""
    log_info "📝 Next steps:"
    log_info "   1. Make any final adjustments if needed"
    log_info "   2. Commit your changes: git commit -m 'chore: release preparation'"
    log_info "   3. Finish the release: git trident staging release finish $version"
    log_empty ""
    log_info "💡 This is a NEW base version release"
    if [ "$starting_point" != "$DEVELOP_BRANCH" ]; then
        log_info "   Starting from: $starting_point"
    fi
}

staging_release_start() {
    local version="$1"
    local from_tag="$2"  # Optional: start from specific tag or commit

    # Validate this is a NEW base version
    validate_new_base_version "$version"

    # Get starting point
    local starting_point=$(get_release_starting_point "$from_tag")

    # Create release branch
    create_staging_release_branch "$version" "$starting_point"

    # Show summary
    local release_branch="${RELEASE_STAGING_PREFIX}${version}"
    show_release_preparation_summary "$release_branch" "$version" "$starting_point"
}

# =============================================================================
# RELEASE COMPLETION OPERATIONS (WITH CLEAN MERGE CHAIN)
# =============================================================================

create_first_rc_tag() {
    local version="$1"
    local rc_number="$2"
    local source_ref="$3"  # Branch, tag, or commit to tag from

    local suffix="$(get_rc_suffix)"
    local tag_name="${STAGING_TAG_PREFIX}${version}${suffix}${rc_number}"

    # Check if this RC already exists
    if git rev-parse "$tag_name" >/dev/null 2>&1; then
        log_error "Staging tag already exists: $tag_name"
        log_info "This suggests the release was already finished or there's a conflict"
        exit 1
    fi

    # Create the RC tag from specific source reference
    verify_step "Creating staging tag from $source_ref" \
        "git tag -a '$tag_name' '$source_ref' -m 'Staging release $version${suffix}${rc_number}'" \
        "Created tag: $tag_name from $source_ref"
    
    echo "$tag_name"
}

deploy_to_staging() {
    local release_branch="$1"
    local version="$2"
    local rc_number="$3"
    
    # Checkout staging branch
    verify_step "Checking out staging branch ($STAGING_BRANCH)" \
        "git checkout $STAGING_BRANCH" \
        "On staging branch: $STAGING_BRANCH"

    # Merge release into staging (DEPLOY TO STAGING)
    log_info "Merging $release_branch into $STAGING_BRANCH..."
    
    local suffix="$(get_rc_suffix)"
    if ! interactive_merge "$STAGING_BRANCH" "$release_branch" \
        "Release(staging): $version${suffix}${rc_number}" \
        "deploying to staging"; then
        return 1
    fi
    
    log_info "✓ Staging branch updated with release"
    return 0
}

sync_staging_to_develop_after_release() {
    local version="$1"
    local rc_number="$2"
    
    log_info "🔄 Synchronizing staging changes to develop..."
    verify_step "Checking out develop branch ($DEVELOP_BRANCH)" \
        "git checkout $DEVELOP_BRANCH" \
        "On develop branch: $DEVELOP_BRANCH"

    local suffix="$(get_rc_suffix)"
    if ! interactive_merge "$DEVELOP_BRANCH" "$STAGING_BRANCH" \
        "Sync: Staging changes $version${suffix}${rc_number}" \
        "syncing to develop"; then
        log_warn "⚠️  Release deployed to staging but develop sync incomplete"
        log_info "Run 'git trident verify-sync' to check branch status"
        return 1
    fi
    
    log_info "✓ Develop branch synchronized with staging"
    return 0
}

show_release_completion_summary() {
    local version="$1"
    local rc_number="$2"
    local tag_name="$3"
    
    # Show platform info if in platform-specific mode
    local platform_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        platform_info=" (platform: $platform)"
    fi
    
    local suffix="$(get_rc_suffix)"
    log_info "🎉 NEW STAGING RELEASE COMPLETED: $version${suffix}${rc_number}$platform_info"
    log_info "📝 Summary:"
    log_info "   - Created FIRST RC for new base version $version"
    log_info "   - $STAGING_BRANCH deployed release $version${suffix}${rc_number}"
    log_info "   - Tag created: $tag_name"
    log_info "   - Staging changes synced to $DEVELOP_BRANCH"
    if [ "${AUTO_PUSH_ON_FINISH:-false}" = "false" ]; then
      log_info "   - Run 'git trident push-all' to push to $REMOTE"
    fi
}

staging_release_finish() {
    local version="$1"
    local release_branch="${RELEASE_STAGING_PREFIX}${version}"
    local rc_number="01" # Always 01 for the first release finish

    local suffix="$(get_rc_suffix)"
    local tag_name="${STAGING_TAG_PREFIX}${version}${suffix}${rc_number}"

    log_info "🏁 FINISHING NEW STAGING RELEASE: $version"
    
    # Show platform info if in platform-specific mode
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        log_info "Platform: $platform"
    fi
    
    log_info "Using branch: $release_branch"
    log_info "RC Number: $rc_number (FIRST RC for this version)"
    log_info "Will create tag: $tag_name"
    log_info "=========================================="

    assert_clean_working_tree

    # Validate release branch exists
    if ! validate_release_branch_exists "$version"; then
        log_error "Cannot finish staging release - branch not found"
        log_info "Please run: git trident staging release start $version first"
        exit 1
    fi

    # Ensure we're on release branch
    local current_branch=$(get_current_branch)
    if [ "$current_branch" != "$release_branch" ]; then
        verify_step "Switching to release branch" \
            "git checkout $release_branch" \
            "On release branch: $release_branch"
    fi

    # Step 1: Create the RC tag from release branch
    create_first_rc_tag "$version" "$rc_number" "$release_branch" > /dev/null

    # Step 2: Deploy to staging
    if ! deploy_to_staging "$release_branch" "$version" "$rc_number"; then
        return 1
    fi

    # Step 3: Sync staging → develop
    sync_staging_to_develop_after_release "$version" "$rc_number"

    # Step 4: Delete release branch
    cleanup_branch "$release_branch" "release"

    # Step 5: Auto-push if enabled
    auto_push_if_enabled "$version"

    # Step 6: Show summary
    show_release_completion_summary "$version" "$rc_number" "$tag_name"

    return 0
}

# =============================================================================
# HOTFIX VALIDATION AND PREPARATION (WITH PLATFORM SUPPORT)
# =============================================================================

validate_existing_base_version() {
    local version="$1"

    # Validate: Must be existing base version for hotfix
    if ! validate_staging_version_format "$version"; then
        exit 1
    fi

    # Check if this base version exists and has RCs
    local existing_rcs=$(get_staging_tags_for_version "$version")
    if [ -z "$existing_rcs" ]; then
        log_error "Version $version has no existing RC releases"
        log_empty ""
        log_info "Use 'staging release' to create the FIRST RC for new base versions"
        log_info "Use 'staging hotfix' only for EXISTING base versions"
        log_empty ""
        log_info "Available staging versions:"
        git tag -l "${STAGING_TAG_PREFIX}*" | sed "s|^${STAGING_TAG_PREFIX}||" | sed "s|$(get_rc_suffix)[0-9]*$||" | sort -V | uniq
        exit 1
    fi

    # Check if version is already in production
    if ! validate_version_not_in_production "$version" "staging"; then
        exit 1
    fi

    return 0
}

get_latest_staging_rc() {
    local version="$1"
    local latest_rc=$(get_latest_rc_for_version "$version")
    
    if [ -z "$latest_rc" ]; then
        log_error "No staging releases found for version: $version"
        log_empty ""
        log_info "Available staging versions:"
        git tag -l "${STAGING_TAG_PREFIX}*" | sed "s|^${STAGING_TAG_PREFIX}||" | sed "s|$(get_rc_suffix)[0-9]*$||" | sort -V | uniq
        exit 1
    fi
    
    echo "$latest_rc"
}

# =============================================================================
# STAGING HOTFIX OPERATIONS (NEW RC FOR EXISTING BASE VERSION)
# =============================================================================

create_staging_hotfix_branch() {
    local version="$1"
    local latest_rc="$2"
    
    local hotfix_branch="${HOTFIX_STAGING_PREFIX}${version}"
    local rc_number=$(get_next_rc_number "$version")
    local suffix="$(get_rc_suffix)"
    local staging_tag="${STAGING_TAG_PREFIX}${version}${suffix}${rc_number}"

    log_info "🔧 STARTING STAGING HOTFIX: $version"
    
    # Show platform info if in platform-specific mode
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        log_info "Platform: $platform"
    fi
    
    log_info "This will create a new RC for an EXISTING base version"
    log_info "Latest existing RC: $latest_rc"
    log_info "New RC Number: $rc_number"
    log_info "Will create tag: $staging_tag"
    log_info "=========================================="

    assert_clean_working_tree

    # Checkout the latest RC for this version
    verify_step "Checking out latest RC: $latest_rc" \
        "git checkout '$latest_rc'" \
        "On latest RC: $latest_rc"

    # Create staging hotfix branch
    verify_step "Creating staging hotfix branch" \
        "git checkout -b $hotfix_branch" \
        "Created and switched to $hotfix_branch"
}

show_hotfix_preparation_summary() {
    local hotfix_branch="$1"
    local version="$2"
    local latest_rc="$3"
    
    log_info "🎉 Staging hotfix branch ready: $hotfix_branch"
    log_empty ""
    log_info "📝 Next steps:"
    log_info "   1. Fix the staging issue"
    log_info "   2. Commit your changes: git commit -m 'fix: staging issue'"
    log_info "   3. Finish the hotfix: git trident staging hotfix finish $version"
    log_empty ""
    log_info "💡 This is a hotfix for EXISTING base version $version"
    log_info "   Starting from latest RC: $latest_rc"
}

staging_hotfix_start() {
    local version="$1"

    # Validate this is an EXISTING base version
    validate_existing_base_version "$version"

    # Get latest RC
    local latest_rc=$(get_latest_staging_rc "$version")

    # Create hotfix branch
    create_staging_hotfix_branch "$version" "$latest_rc"

    # Show summary
    local hotfix_branch="${HOTFIX_STAGING_PREFIX}${version}"
    show_hotfix_preparation_summary "$hotfix_branch" "$version" "$latest_rc"
}

# =============================================================================
# HOTFIX COMPLETION OPERATIONS (WITH CLEAN MERGE CHAIN)
# =============================================================================

show_hotfix_changes() {
    local hotfix_branch="$1"
    local latest_rc="$2"
    local tag_name="$3"
    
    log_info "Hotfix changes to be applied:"
    git_log_formatted "$latest_rc..$hotfix_branch"

    if ! confirm_action "Apply this staging hotfix to create $tag_name?"; then
        log_info "Hotfix cancelled by user"
        return 1
    fi
    
    return 0
}

create_hotfix_rc_tag() {
    local version="$1"
    local rc_number="$2"
    local source_ref="$3"  # Branch, tag, or commit to tag from

    local suffix="$(get_rc_suffix)"
    local tag_name="${STAGING_TAG_PREFIX}${version}${suffix}${rc_number}"

    # Create the new RC tag from specific source reference
    verify_step "Creating staging tag from $source_ref" \
        "git tag -a '$tag_name' '$source_ref' -m 'Staging hotfix $version${suffix}${rc_number}'" \
        "Created tag: $tag_name from $source_ref"
    
    echo "$tag_name"
}

integrate_hotfix_into_staging() {
    local hotfix_branch="$1"
    local version="$2"
    local rc_number="$3"
    
    log_info "🔄 Integrating hotfix into staging branch..."
    git checkout "$STAGING_BRANCH"

    # Check if staging already has this tag
    if git merge-base --is-ancestor "$hotfix_branch" "$STAGING_BRANCH" 2>/dev/null; then
        log_info "✓ Staging branch already includes hotfix tag"
        return 0
    fi

    log_info "Merging $hotfix_branch into $STAGING_BRANCH..."
    
    local suffix="$(get_rc_suffix)"
    if ! interactive_merge "$STAGING_BRANCH" "$hotfix_branch" \
        "Integrate: Staging hotfix $version${suffix}${rc_number}" \
        "integrating hotfix into staging"; then
        log_info "Hotfix paused. Resolve conflicts and run the command again to continue."
        return 1
    fi
    
    log_info "✓ Staging branch updated with hotfix"
    return 0
}

sync_staging_to_develop_after_hotfix() {
    local version="$1"
    local rc_number="$2"
    
    log_info "🔄 Synchronizing develop branch with staging..."
    git checkout "$DEVELOP_BRANCH"

    # Check if develop already has these changes
    if git merge-base --is-ancestor "$STAGING_BRANCH" "$DEVELOP_BRANCH" 2>/dev/null; then
        log_info "✓ Develop branch already includes staging changes"
        return 0
    fi

    log_info "Merging $STAGING_BRANCH into $DEVELOP_BRANCH..."
    
    local suffix="$(get_rc_suffix)"
    if ! interactive_merge "$DEVELOP_BRANCH" "$STAGING_BRANCH" \
        "Sync: Staging changes (includes hotfix $version${suffix}${rc_number})" \
        "syncing to develop"; then
        log_warn "⚠️  Hotfix applied to staging but develop sync incomplete."
        log_info "Run 'git trident verify-sync' to check branch status."
        return 1
    fi
    
    log_info "✓ Develop branch synchronized with staging"
    return 0
}

check_hotfix_impact() {
    local version="$1"
    
    log_empty ""
    log_info "🔍 Analyzing hotfix impact on newer staging versions..."

    local sync_script="$SCRIPT_DIR/../bin/git-trident-staging-sync-tags"
    if [ -f "$sync_script" ]; then
        # Source the sync script for detection function
        source "$SCRIPT_DIR/git-trident-staging-sync-from-staging.sh"
        
        if ! detect_staging_hotfix_impact "$version"; then
            log_warn "📢 ACTION RECOMMENDED: Newer staging versions need synchronization"
            log_info "Run: git trident staging sync-tags $version"
        else
            log_info "✅ All newer staging versions include this hotfix"
        fi
    fi
}

show_hotfix_completion_summary() {
    local version="$1"
    local rc_number="$2"
    local tag_name="$3"
    
    # Show platform info if in platform-specific mode
    local platform_info=""
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        platform_info=" (platform: $platform)"
    fi
    
    local suffix="$(get_rc_suffix)"
    log_info "🎉 STAGING HOTFIX COMPLETED: $version${suffix}${rc_number}$platform_info"
    log_info "📝 Summary:"
    log_info "   - Created RC $rc_number: $tag_name"
    log_info "   - Staging branch updated with hotfix"
    log_info "   - Develop branch synchronized with staging"
    if [ "${AUTO_PUSH_ON_FINISH:-false}" = "false" ]; then
      log_info "   - Run 'git trident push-all' to push to $REMOTE"
    fi
}

staging_hotfix_finish() {
    local version="$1"
    local hotfix_branch="${HOTFIX_STAGING_PREFIX}${version}"
    local rc_number=$(get_next_rc_number "$version")
    
    local suffix="$(get_rc_suffix)"
    local tag_name="${STAGING_TAG_PREFIX}${version}${suffix}${rc_number}"
    local latest_rc=$(get_latest_rc_for_version "$version")

    log_info "🏁 FINISHING STAGING HOTFIX: $version"
    
    # Show platform info if in platform-specific mode
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        log_info "Platform: $platform"
    fi
    
    log_info "Using branch: $hotfix_branch"
    log_info "Previous RC: $latest_rc"
    log_info "New RC Number: $rc_number"
    log_info "Will create tag: $tag_name"
    log_info "=========================================="

    assert_clean_working_tree

    # Validate hotfix branch exists
    if ! validate_hotfix_branch_exists "$version"; then
        log_error "Cannot finish staging hotfix - branch not found"
        log_info "Please run: git trident staging hotfix start $version first"
        exit 1
    fi

    # NEW: Validate version is not already in production
    if ! validate_version_not_in_production "$version" "staging"; then
        exit 1
    fi

    # Ensure we're on hotfix branch
    local current_branch=$(get_current_branch)
    if [ "$current_branch" != "$hotfix_branch" ]; then
        verify_step "Switching to hotfix branch" \
            "git checkout $hotfix_branch" \
            "On hotfix branch: $hotfix_branch"
    fi

    # Show and confirm hotfix changes
    if ! show_hotfix_changes "$hotfix_branch" "$latest_rc" "$tag_name"; then
        return 1
    fi

    # Step 1: Create the new RC tag from hotfix branch
    create_hotfix_rc_tag "$version" "$rc_number" "$hotfix_branch" > /dev/null

    # Step 2: Update staging branch with the new tag
    if ! integrate_hotfix_into_staging "$hotfix_branch" "$version" "$rc_number"; then
        return 1
    fi

    # Step 3: Sync staging to develop
    sync_staging_to_develop_after_hotfix "$version" "$rc_number"

    # Step 4: Clean up
    cleanup_branch "$hotfix_branch" "hotfix"

    # Step 5: Auto-push if enabled
    auto_push_if_enabled "$version"

    # Step 6: Check impact on newer staging versions
    check_hotfix_impact "$version"

    # Step 7: Show summary
    show_hotfix_completion_summary "$version" "$rc_number" "$tag_name"

    return 0
}