#!/bin/bash
# Git Trident Production Operations - Release and Hotfix Management
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
    local release_branch="${RELEASE_PRODUCTION_PREFIX}${version}"

    if check_branch_exists "$release_branch"; then
        log_info "✓ Release branch exists: $release_branch"
        return 0
    else
        log_error "Release branch not found: $release_branch"
        log_info "You need to run: git trident production release start $version"
        return 1
    fi
}

validate_hotfix_branch_exists() {
    local version="$1"
    local hotfix_branch="${HOTFIX_PRODUCTION_PREFIX}${version}"

    if check_branch_exists "$hotfix_branch"; then
        log_info "✓ Hotfix branch exists: $hotfix_branch"
        return 0
    else
        log_error "Hotfix branch not found: $hotfix_branch"
        log_info "You need to run: git trident production hotfix start $version"
        return 1
    fi
}

# =============================================================================
# RELEASE VALIDATION AND PREPARATION (WITH PLATFORM SUPPORT)
# =============================================================================

validate_release_version() {
    local version="$1"

    # Validate version format
    if ! validate_production_version_format "$version"; then
        exit 1
    fi

    # Check if version is already released
    if is_production_tag_released "$version"; then
        log_error "Version $version is already released to production!"
        show_available_tags "production"
        exit 1
    fi

    return 0
}

get_latest_staging_rc_for_version() {
    local version="$1"
    local latest_staging_rc=$(get_latest_rc_for_version "$version")
    
    local suffix="$(get_rc_suffix)"
    if [ -z "$latest_staging_rc" ]; then
        log_error "No staging releases found for version: $version"
        log_empty ""
        log_info "Available staging versions:"
        git tag -l "${STAGING_TAG_PREFIX}*" | sed "s|^${STAGING_TAG_PREFIX}||" | sed "s|${suffix}[0-9]*$||" | sort -V | uniq
        exit 1
    fi
    
    echo "$latest_staging_rc"
}

validate_staging_tag_for_promotion() {
    local staging_tag="$1"
    local production_version="$2"

    if ! validate_staging_tag_promotable "$staging_tag" "$production_version"; then
        exit 1
    fi
}

# =============================================================================
# PRODUCTION RELEASE OPERATIONS (FROM STAGING)
# =============================================================================

create_production_release_branch() {
    local version="$1"
    local staging_tag="$2"
    
    local release_branch="${RELEASE_PRODUCTION_PREFIX}${version}"
    
    log_info "🚀 STARTING PRODUCTION RELEASE: $version"
    
    # Show platform info if in platform-specific mode
    if is_platform_specific_mode; then
        local platform=$(extract_platform_from_version "$version")
        log_info "Platform: $platform"
    fi
    
    log_info "Automatically using latest staging RC: $staging_tag"
    log_info "=========================================="

    assert_clean_working_tree

    # Checkout the staging RC
    verify_step "Checking out staging RC: $staging_tag" \
        "git checkout '$staging_tag'" \
        "On staging RC: $staging_tag"

    # Create production release branch
    verify_step "Creating production release branch" \
        "git checkout -b $release_branch" \
        "Created and switched to $release_branch"

    echo "$release_branch"
}

show_release_preparation_summary() {
    local release_branch="$1"
    local staging_tag="$2"
    
    log_info "🎉 Production release branch ready: $release_branch"
    log_empty ""
    log_info "📝 Next steps:"
    log_info "   1. Make any final production adjustments if needed"
    log_info "   2. Commit your changes: git commit -m 'chore: production release preparation'"
    log_info "   3. Finish the release: git trident production release finish $version"
    log_empty ""
    log_info "💡 Automatically started from latest staging RC: $staging_tag"
}

production_release_start() {
    local version="$1"

    # Validate release version
    validate_release_version "$version"

    # Get latest staging RC
    local latest_staging_rc=$(get_latest_staging_rc_for_version "$version")
    
    # Validate staging tag is promotable
    validate_staging_tag_for_promotion "$latest_staging_rc" "$version"

    # Create release branch
    local release_branch=$(create_production_release_branch "$version" "$latest_staging_rc")
    
    # Show summary
    show_release_preparation_summary "$release_branch" "$latest_staging_rc"
}

# =============================================================================
# RELEASE COMPLETION OPERATIONS
# =============================================================================

deploy_to_production() {
    local release_branch="$1"
    local version="$2"
    
    log_info "Merging $release_branch into $PRODUCTION_BRANCH..."
    
    if ! interactive_merge "$PRODUCTION_BRANCH" "$release_branch" \
        "Release(production): $version" \
        "production release"; then
        log_error "Production release deployment failed"
        return 1
    fi
    
    log_info "✓ Production release deployed successfully"
    return 0
}

create_production_release_tag() {
    local version="$1"
    local source_ref="$2"  # Can be branch, tag, or commit to tag from
    
    local tag_name="${PRODUCTION_TAG_PREFIX}${version}"
    
    # Check if tag already exists
    if is_production_tag_released "$version"; then
        log_error "Production tag already exists: $tag_name"
        return 1
    fi
    
    # Create tag from specific source reference
    verify_step "Creating production tag from $source_ref" \
        "git tag -a '$tag_name' '$source_ref' -m 'Production release $version'" \
        "Created tag: $tag_name from $source_ref"
    
    echo "$tag_name"
}

sync_production_to_staging() {
    local version="$1"
    
    log_info "🔄 Synchronizing production changes to staging..."
    verify_step "Checking out staging branch ($STAGING_BRANCH)" \
        "git checkout $STAGING_BRANCH" \
        "On staging branch: $STAGING_BRANCH"

    if ! interactive_merge "$STAGING_BRANCH" "$PRODUCTION_BRANCH" \
        "Sync: Production changes $version" \
        "syncing to staging"; then
        log_warn "⚠️  Production release completed but staging sync incomplete"
        log_info "Please resolve staging conflicts manually"
        return 1
    fi
    
    log_info "✓ Staging branch synchronized with production"
    return 0
}

sync_staging_to_develop() {
    local version="$1"
    
    log_info "🔄 Syncing staging changes to develop..."
    verify_step "Checking out develop branch ($DEVELOP_BRANCH)" \
        "git checkout $DEVELOP_BRANCH" \
        "On develop branch: $DEVELOP_BRANCH"

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
        "Sync: Staging changes (includes production $version)" \
        "syncing to develop"; then
        log_warn "⚠️  Staging sync completed but develop sync incomplete"
        log_info "Please resolve develop conflicts manually"
        return 1
    fi
    
    log_info "✓ Staging and develop synchronized"
    return 0
}

check_staging_synchronization() {
    local version="$1"
    
    log_info "🔍 Checking staging release synchronization..."
    
    # Source the production sync script for the check function
    source "$SCRIPT_DIR/git-trident-staging-sync-from-production.sh"
    
    if ! check_staging_releases_need_rebase "$version"; then
        log_warn "⚠️  Some staging releases are based on outdated commits"
        log_info "Consider running: git trident staging sync-tags $version"
    fi
}

show_release_completion_summary() {
    local version="$1"
    local tag_name="$2"
    
    log_info "🎉 PRODUCTION RELEASE COMPLETED: $version"
    log_info "📝 Summary:"
    log_info "   - $PRODUCTION_BRANCH deployed release $version"
    log_info "   - Tag created: $tag_name"
    log_info "   - Branches synchronized: production → staging → develop"
    log_info "   - Staging synchronization checked"
    if [ "${AUTO_PUSH_ON_FINISH:-false}" = "false" ]; then
      log_info "   - Run 'git trident push-all' to push to $REMOTE"
    fi
}

production_release_finish() {
    local version="$1"
    local release_branch="${RELEASE_PRODUCTION_PREFIX}${version}"
    local tag_name="${PRODUCTION_TAG_PREFIX}${version}"

    log_info "🏁 FINISHING PRODUCTION RELEASE: $version"
    log_info "Using branch: $release_branch"
    log_info "Will create tag: $tag_name"
    log_info "=========================================="

    assert_clean_working_tree

    # Validate release branch exists
    if ! validate_release_branch_exists "$version"; then
        log_error "Cannot finish production release - branch not found"
        log_info "Please run: git trident production release start $version first"
        exit 1
    fi

    # Validate version is not already released
    validate_release_version "$version"

    # Ensure we're on release branch
    local current_branch=$(get_current_branch)
    if [ "$current_branch" != "$release_branch" ]; then
        verify_step "Switching to release branch" \
            "git checkout $release_branch" \
            "On release branch: $release_branch"
    fi

    # Step 1: Checkout production branch
    verify_step "Checking out production branch ($PRODUCTION_BRANCH)" \
        "git checkout $PRODUCTION_BRANCH" \
        "On production branch: $PRODUCTION_BRANCH"

    # Step 2: Deploy to production
    if ! deploy_to_production "$release_branch" "$version"; then
        return 1
    fi

    # Step 3: Create production tag from PRODUCTION_BRANCH (not release branch)
    create_production_release_tag "$version" "$PRODUCTION_BRANCH" > /dev/null

    # Step 4: Sync production → staging
    sync_production_to_staging "$version"

    # Step 5: Sync staging → develop
    sync_staging_to_develop "$version"

    # Step 6: Check staging synchronization
    check_staging_synchronization "$version"

    # Step 7: Cleanup
    cleanup_branch "$release_branch" "release"

    # Step 8: Auto-push if enabled
    auto_push_if_enabled "$version"

    # Step 9: Show summary
    show_release_completion_summary "$version" "$tag_name"

    return 0
}

# =============================================================================
# HOTFIX VALIDATION AND PREPARATION (WITH PLATFORM SUPPORT)
# =============================================================================

validate_hotfix_branch() {
    local current_branch="$1"
    local version="$2"

    if [ -z "$version" ] || [ "$current_branch" = "$version" ]; then
        log_error "Not on a production hotfix branch"
        log_info "Please run this command from a production hotfix branch"
        exit 1
    fi

    # Validate version format
    if ! validate_production_version_format "$version"; then
        exit 1
    fi
}

verify_hotfix_base() {
    local hotfix_branch="$1"
    
    # CRITICAL: Verify hotfix is based on latest production, not staging
    local production_commit=$(git rev-parse "$PRODUCTION_BRANCH")
    local hotfix_base_commit=$(git merge-base "$hotfix_branch" "$PRODUCTION_BRANCH")

    if [ "$production_commit" != "$hotfix_base_commit" ]; then
        log_error "❌ Production hotfix is not based on latest production branch!"
        log_info "Hotfix should be based on: $PRODUCTION_BRANCH ($production_commit)"
        log_info "But is based on: $hotfix_base_commit"
        log_empty ""
        log_info "💡 To fix:"
        log_info "   1. Ensure your hotfix branch was created from $PRODUCTION_BRANCH"
        log_info "   2. Or rebase: git rebase $PRODUCTION_BRANCH"
        exit 1
    fi
}

show_hotfix_changes() {
    local hotfix_branch="$1"
    local version="$2"
    
    log_info "Hotfix changes to be applied for version: $version"
    git_log_formatted "$PRODUCTION_BRANCH..$hotfix_branch"

    if ! confirm_action "Apply this production hotfix as version $version?"; then
        log_info "Hotfix cancelled by user"
        return 1
    fi
    
    return 0
}

# =============================================================================
# PRODUCTION HOTFIX OPERATIONS (AUTO-PATCH INCREMENT WITH PLATFORM SUPPORT)
# =============================================================================

get_next_hotfix_version_for_platform() {
    local platform="${1:-}"

    if [ -n "$platform" ] && is_platform_specific_mode; then
        # Get latest production tag for specific platform
        local latest_production=$(get_latest_production_tag_for_platform "$platform")
        if [ -z "$latest_production" ]; then
            log_error "No existing production releases for platform: $platform"
            log_empty "       Available platforms: $PLATFORMS"
            return 1
        fi

        increment_patch_version "$latest_production"
    else
        # Legacy mode or no platform specified
        get_next_production_hotfix_version
    fi
}

create_production_hotfix_branch() {
    local platform="${1:-}"

    # Auto-determine the next patch version for hotfix
    local next_version
    next_version=$(get_next_hotfix_version_for_platform "$platform")
    if [ $? -ne 0 ] || [ -z "$next_version" ]; then
        return 1
    fi

    local hotfix_branch="${HOTFIX_PRODUCTION_PREFIX}${next_version}"

    log_info "🔧 STARTING PRODUCTION HOTFIX"
    
    # Show platform info if in platform-specific mode
    if is_platform_specific_mode && [ -n "$platform" ]; then
        log_info "Platform: $platform"
    fi
    
    log_info "Auto-detected next version: $next_version"
    log_info "Starting from latest production branch"
    log_info "=========================================="

    assert_clean_working_tree

    # Checkout production branch
    verify_step "Checking out production branch ($PRODUCTION_BRANCH)" \
        "git checkout $PRODUCTION_BRANCH" \
        "On production branch: $PRODUCTION_BRANCH"

    # Create production hotfix branch
    verify_step "Creating production hotfix branch" \
        "git checkout -b $hotfix_branch" \
        "Created and switched to $hotfix_branch"

    echo "$hotfix_branch $next_version"
}

show_hotfix_preparation_summary() {
    local hotfix_branch="$1"
    local next_version="$2"
    local platform="${3:-}"

    log_info "🎉 Production hotfix branch ready: $hotfix_branch"
    log_empty ""
    log_info "📝 Next steps:"
    log_info "   1. Fix the critical production issue"
    log_info "   2. Commit your changes: git commit -m 'fix: critical production issue'"
    log_info "   3. Finish the hotfix: git trident production hotfix finish"
    log_empty ""
    log_info "💡 Auto-incremented version: $next_version"
    log_info "   Starting from current production state"
    if [ -n "$platform" ]; then
        log_info "   Platform: $platform"
    fi
}

production_hotfix_start() {
    local platform="${1:-}"

    # Validate platform if provided
    if [ -n "$platform" ] && is_platform_specific_mode; then
        if ! validate_platform "$platform"; then
            return 1
        fi
    fi

    local result
    result=$(create_production_hotfix_branch "$platform")

    # Check if create_production_hotfix_branch succeeded
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        log_error "Failed to create production hotfix branch"
        return 1
    fi

    # Use array approach instead of cut
    IFS=' ' read -r hotfix_branch next_version <<< "$result"

    # Validate the parsed values
    if [ -z "$hotfix_branch" ] || [ -z "$next_version" ]; then
        log_error "Failed to parse hotfix branch and version from result: '$result'"
        return 1
    fi

    show_hotfix_preparation_summary "$hotfix_branch" "$next_version" "$platform"
    return 0
}

# =============================================================================
# HOTFIX COMPLETION OPERATIONS
# =============================================================================

apply_hotfix_to_production() {
    local hotfix_branch="$1"
    local version="$2"
    
    log_info "Merging $hotfix_branch into $PRODUCTION_BRANCH..."
    
    if ! interactive_merge "$PRODUCTION_BRANCH" "$hotfix_branch" \
        "Hotfix(production): $version" \
        "production hotfix"; then
        log_error "Production hotfix application failed"
        return 1
    fi
    
    log_info "✓ Production hotfix applied successfully"
    return 0
}

create_production_hotfix_tag() {
    local version="$1"
    local source_ref="$2"  # Branch, tag, or commit to tag from
    
    local tag_name="${PRODUCTION_TAG_PREFIX}${version}"
    
    # Check if tag already exists
    if is_production_tag_released "$version"; then
        log_error "Production tag already exists: $tag_name"
        return 1
    fi
    
    # Create tag from specific source reference
    verify_step "Creating production hotfix tag from $source_ref" \
        "git tag -a '$tag_name' '$source_ref' -m 'Production hotfix $version'" \
        "Created tag: $tag_name from $source_ref"
    
    echo "$tag_name"
}

sync_hotfix_downstream() {
    local version="$1"
    
    # Sync production → staging
    log_info "🔄 Synchronizing production changes to staging..."
    verify_step "Checking out staging branch ($STAGING_BRANCH)" \
        "git checkout $STAGING_BRANCH" \
        "On staging branch: $STAGING_BRANCH"

    if ! interactive_merge "$STAGING_BRANCH" "$PRODUCTION_BRANCH" \
        "Sync: Production hotfix $version" \
        "syncing to staging"; then
        log_warn "⚠️  Production hotfix applied but staging sync incomplete"
        return 1
    fi
    
    log_info "✓ Staging branch synchronized with production"
    
    # Sync staging → develop
    log_info "🔄 Synchronizing staging changes to develop..."
    verify_step "Checking out develop branch ($DEVELOP_BRANCH)" \
        "git checkout $DEVELOP_BRANCH" \
        "On develop branch: $DEVELOP_BRANCH"

    if ! interactive_merge "$DEVELOP_BRANCH" "$STAGING_BRANCH" \
        "Sync: Staging changes (includes hotfix $version)" \
        "syncing to develop"; then
        log_warn "⚠️  Staging sync completed but develop sync incomplete"
        return 1
    fi
    
    log_info "✓ Develop branch synchronized with staging"
    return 0
}

show_hotfix_completion_summary() {
    local version="$1"
    local tag_name="$2"
    
    log_info "🎉 PRODUCTION HOTFIX COMPLETED: $version"
    log_info "📝 Summary:"
    log_info "   - $PRODUCTION_BRANCH hotfix applied: $version"
    log_info "   - Tag created: $tag_name"
    log_info "   - Branches synchronized: production → staging → develop"
    if [ "${AUTO_PUSH_ON_FINISH:-false}" = "false" ]; then
      log_info "   - Run 'git trident push-all' to push to $REMOTE"
    fi
}

production_hotfix_finish() {
    # Auto-determine the hotfix version from current branch
    local current_branch=$(get_current_branch)
    local version=$(echo "$current_branch" | sed "s|^${HOTFIX_PRODUCTION_PREFIX}||")

    validate_hotfix_branch "$current_branch" "$version"

    local hotfix_branch="$current_branch"
    local tag_name="${PRODUCTION_TAG_PREFIX}${version}"

    log_info "🏁 FINISHING PRODUCTION HOTFIX: $version"
    log_info "Using branch: $hotfix_branch"
    log_info "Will create tag: $tag_name"
    log_info "=========================================="

    assert_clean_working_tree

    # Verify hotfix is based on latest production
    verify_hotfix_base "$hotfix_branch"

    # Show and confirm hotfix changes
    if ! show_hotfix_changes "$hotfix_branch" "$version"; then
        return 1
    fi

    # Step 1: Checkout production branch
    verify_step "Checking out production branch ($PRODUCTION_BRANCH)" \
        "git checkout $PRODUCTION_BRANCH" \
        "On production branch: $PRODUCTION_BRANCH"

    # Step 2: Apply hotfix to production
    if ! apply_hotfix_to_production "$hotfix_branch" "$version"; then
        return 1
    fi

    # Step 3: Create production tag from PRODUCTION_BRANCH
    create_production_hotfix_tag "$version" "$PRODUCTION_BRANCH" > /dev/null

    # Step 4: Cleanup hotfix branch
    cleanup_branch "$hotfix_branch" "hotfix"

    # Step 5: Sync downstream
    sync_hotfix_downstream "$version"

    # Return to staging branch
    git checkout "$STAGING_BRANCH"

    # Step 6: Auto-push if enabled
    auto_push_if_enabled "$version"

    # Step 7: Show summary
    show_hotfix_completion_summary "$version" "$tag_name"

    return 0
}