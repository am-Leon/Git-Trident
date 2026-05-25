#!/bin/bash
# Git Trident Help System - Centralized help documentation
# Centralizes all help functions from across the codebase

# =============================================================================
# CONFIGURATION AND UTILITY FUNCTIONS
# =============================================================================

# Get version format based on mode
get_version_format_example() {
    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        echo "platform-MAJOR.MINOR.PATCH (e.g., android-1.2.0, ios-2.0.0)"
    else
        echo "MAJOR.MINOR.PATCH (e.g., 1.2.0)"
    fi
}

# Get platform info if in platform-specific mode
get_platform_info() {
    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        echo "🌐 Platform-Specific Mode Active"
        echo "   Supported platforms: $PLATFORMS"
        echo "   Version format: platform-MAJOR.MINOR.PATCH"
        echo ""
    fi
}

# Get platform parameter documentation
get_platform_param_doc() {
    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  <platform>    Target platform (e.g., android, ios, shared)
                Required in platform-specific mode
                Supported: $PLATFORMS

EOF
    fi
}

# =============================================================================
# MAIN HELP DISPLAY
# =============================================================================

show_main_help() {
    cat <<EOF
Git Trident v${TRIDENT_VERSION} - Staging/Production Workflow Management

Usage:
  git trident <command> [args...]

$(get_platform_info)
Core Workflow Commands:
  production release start <version>    Promote staging to production
  production release finish <version>   Complete production release
  production hotfix start [platform]    Start production hotfix (auto-version)
  production hotfix finish              Complete production hotfix
  production changelog [version]        Generate public release notes
  staging release start <version>       Create NEW base version (first RC)
  staging release finish <version>      Complete new staging release
  staging hotfix start <version>        Create new RC for EXISTING version
  staging hotfix finish <version>       Complete staging hotfix
  staging sync-tags <version>           Sync tags after releases/hotfixes
  staging changelog <version>           Generate developer changelog

Utility Commands:
  config [init|show]             Manage and view configuration
  push-all [remote]              Push all changes to remote
  verify-sync [--brief]          Verify branch synchronization
  cleanup [command]              Cleanup/Pruning for old staging tags & branches
  status                         Quick sync status
  tags <env>                     Show available tags for environment
  version [command]              Show version and system info
  help                           Show this help message

Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  # Platform-specific workflow (KMP project)
  git trident staging release start android-1.2.0
  git trident production release start android-1.2.0
  git trident staging hotfix start shared-1.1.0
  git trident staging sync-tags ios-2.0.0
EOF
    else
        cat <<EOF
  # Single-environment workflow
  git trident staging release start 2.1.0
  git trident production release start 2.1.0
  git trident staging hotfix start 1.2.0
  git trident staging sync-tags 2.3.0
EOF
    fi

    cat <<EOF

Run 'git trident <command> --help' for command-specific help
EOF
}

# =============================================================================
# PRODUCTION HELP
# =============================================================================

show_production_main_help() {
    cat <<EOF
🚀 PRODUCTION ENVIRONMENT
=========================

Production releases promote tested staging releases to production.
Production hotfixes address critical issues in live environment.

$(get_platform_info)
Commands:
  release start <version>    Promote staging RC to production
  release finish <version>   Complete production release
  hotfix start [platform]    Start hotfix (auto-version)
  hotfix finish              Complete hotfix
  changelog [version]        Generate public release notes

Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  git trident production release start android-1.2.0
  git trident production release finish android-1.2.0
  git trident production hotfix start ios
  git trident production hotfix finish
EOF
    else
        cat <<EOF
  git trident production release start 2.5.0
  git trident production release finish 2.5.0
  git trident production hotfix start
  git trident production hotfix finish
EOF
    fi

    cat <<EOF

Run 'git trident production <command> --help' for detailed help
EOF
}

show_production_release_help() {
    cat <<EOF
Production Release Commands
===========================

Usage:
  git trident production release start <version>
  git trident production release finish <version>

Description:
  Promote tested staging releases to production environment.
  Automatically uses the latest staging RC for the specified version.

Arguments:
  version    Base version to release
             Format: $(get_version_format_example)

Workflow:
  1. git trident production release start <version>
     - Promotes the LATEST staging RC of <version> to production
     - Validates staging tag is promotable
     - Creates production release branch

  2. git trident production release finish <version>
     - Completes the production release
     - Creates production tag: $(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then echo "production/platform-x.x.x"; else echo "production/x.x.x"; fi)
     - Syncs changes to staging and develop

$(get_platform_info)
Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  git trident production release start android-1.2.0
  git trident production release finish android-1.2.0
  git trident production release start ios-2.0.0
  git trident production release finish ios-2.0.0
EOF
    else
        cat <<EOF
  git trident production release start 2.5.0
  git trident production release finish 2.5.0
EOF
    fi

    cat <<EOF

Note: Version must be base version only (no RC suffixes)
EOF
}

show_production_hotfix_help() {
    cat <<EOF
Production Hotfix Commands
==========================

Usage:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        echo "  git trident production hotfix start <platform>"
    else
        echo "  git trident production hotfix start"
    fi

    cat <<EOF
  git trident production hotfix finish

Description:
  Address critical issues in production environment.
  Automatically increments patch version for hotfix.

$(get_platform_param_doc)
Workflow:
  1. git trident production hotfix start$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then echo " <platform>"; fi)
     - Auto-increments patch version (e.g., 1.2.3 → 1.2.4)
     - Creates hotfix branch from production
     $(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then echo "- Platform parameter required"; else echo "- No version parameter needed"; fi)

  2. git trident production hotfix finish
     - Must be run from hotfix branch
     - Auto-detects version from branch
     - Merges to production and creates tag
     - Syncs changes to staging and develop

Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  git trident production hotfix start android
  # ... fix the issue ...
  git trident production hotfix finish

  git trident production hotfix start ios
  # ... fix the issue ...
  git trident production hotfix finish
EOF
    else
        cat <<EOF
  git trident production hotfix start
  # ... fix the issue ...
  git trident production hotfix finish
EOF
    fi

    cat <<EOF

Note: Hotfix version is auto-determined from latest production
EOF
}

# =============================================================================
# STAGING HELP
# =============================================================================

show_staging_main_help() {
    cat <<EOF
🔄 STAGING ENVIRONMENT
======================

Staging releases deploy new features for testing.
Staging hotfixes address issues in staging environment.
Staging sync propagates changes to newer versions.

$(get_platform_info)
Commands:
  release start <version> [commit]   Create NEW base version
  release finish <version>           Complete new release
  hotfix start <version>             Create RC for EXISTING version
  hotfix finish <version>            Complete hotfix
  sync-tags <version>                Sync tags after releases/hotfixes
  changelog <version>                Generate developer changelog

Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  git trident staging release start android-2.5.0     # New version
  git trident staging hotfix start shared-1.2.0       # Existing version
  git trident staging sync-tags ios-2.3.0             # After production release
  git trident staging sync-tags android-1.2.0         # After staging hotfix
EOF
    else
        cat <<EOF
  git trident staging release start 2.5.0     # New version
  git trident staging hotfix start 2.5.0      # Existing version
  git trident staging sync-tags 2.3.0         # After production release
  git trident staging sync-tags 1.2.0         # After staging hotfix
EOF
    fi

    cat <<EOF

Run 'git trident staging <command> --help' for detailed help
EOF
}

show_staging_release_help() {
    cat <<EOF
Staging Release Commands
========================

Usage:
  git trident staging release start <version> [from_commit]
  git trident staging release finish <version>

Description:
  Create FIRST release candidate for a NEW base version.
  Starts from develop branch or specified commit.

Arguments:
  version       New base version
                Format: $(get_version_format_example)
  from_commit   Optional: start from specific commit/tag/branch

Workflow:
  1. git trident staging release start <version>
     - Creates first RC (staging/$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then echo "platform-"; fi)x.x.x-rc-01)
     - Starts from develop branch
     - Validates version is new (no existing RCs)

  2. git trident staging release finish <version>
     - Merges to staging branch
     - Creates staging/$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then echo "platform-"; fi)x.x.x-rc-01 tag
     - Syncs changes to develop

Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  git trident staging release start android-2.5.0
  git trident staging release start ios-2.5.0 develop~3
  git trident staging release finish android-2.5.0
EOF
    else
        cat <<EOF
  git trident staging release start 2.5.0
  git trident staging release start 2.5.0 develop~3
  git trident staging release finish 2.5.0
EOF
    fi

    cat <<EOF

Note: Use for NEW base versions only. Version must not have existing RCs.
EOF
}

show_staging_hotfix_help() {
    cat <<EOF
Staging Hotfix Commands
=======================

Usage:
  git trident staging hotfix start <version>
  git trident staging hotfix finish <version>

Description:
  Create new release candidate for EXISTING base version.
  Increments RC number and starts from latest RC.

Arguments:
  version    Existing base version with RCs
             Format: $(get_version_format_example)

Workflow:
  1. git trident staging hotfix start <version>
     - Finds latest staging/$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then echo "platform-"; fi)x.x.x${STAGING_TAG_SUFFIX:--rc-}XX
     - Increments RC number (rc-01 → rc-02)
     - Creates hotfix branch from latest RC

  2. git trident staging hotfix finish <version>
     - Merges to staging branch
     - Creates new RC tag
     - Syncs changes to develop
     - Checks impact on newer versions

Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  git trident staging hotfix start android-2.5.0
  git trident staging hotfix finish android-2.5.0
  git trident staging hotfix start shared-1.2.0
EOF
    else
        cat <<EOF
  git trident staging hotfix start 2.5.0
  git trident staging hotfix finish 2.5.0
EOF
    fi

    cat <<EOF

Note: Use for EXISTING base versions only. Version must have existing RCs.
EOF
}

show_staging_sync_tags_help() {
    cat <<EOF
Staging Sync Tags Command
=========================

Usage: git trident staging sync-tags <version>

Synchronize staging tags after production releases or staging hotfixes.
Automatically detects context based on the version provided.

Arguments:
  version    Production or staging base version
             Format: $(get_version_format_example)

Options:
  --dry-run, --check-only   Only detect impact without making changes
  --help, -h                Show this help message

Automatic Detection:
  • Production version → Sync production changes to staging
  • Staging version   → Sync staging hotfix to newer versions

$(get_platform_info)
Behavior:
  - For production versions: Updates newer staging versions with production changes
  - For staging versions: Propagates hotfixes to newer staging versions
  - Creates new RC releases for affected versions
  - Maintains base version independence
  - Marks old tags as deprecated

$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then
cat <<EOF2
Platform-Specific Behavior:
  • Sync only affects same-platform versions
  • Example: android-1.2.0 only syncs other android versions
  • Cross-platform versions remain independent

EOF2
fi)

Examples:
EOF

    if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]] && [[ -n "${PLATFORMS:-}" ]]; then
        cat <<EOF
  # After production release android-2.3.0:
  git trident staging sync-tags android-2.3.0

  # After staging hotfix for ios-1.2.0:
  git trident staging sync-tags ios-1.2.0

  # Check impact only:
  git trident staging sync-tags shared-1.2.0 --dry-run
EOF
    else
        cat <<EOF
  # After production release 2.3.0:
  git trident staging sync-tags 2.3.0

  # After staging hotfix for 1.2.0:
  git trident staging sync-tags 1.2.0

  # Check impact only:
  git trident staging sync-tags 1.2.0 --dry-run
EOF
    fi

    cat <<EOF

Note: Version must exist in either production or staging environment.
EOF
}

# =============================================================================
# UTILITY COMMAND HELP
# =============================================================================

show_utility_main_help() {
    cat <<EOF
🛠️  UTILITY COMMANDS
===================

$(get_platform_info)
push-all [remote]              Push all changes to remote
verify-sync [--brief]          Verify branch synchronization
status                         Quick sync status
tags <env>                     Show available tags for environment
version [command]              Show version and system info
cleanup [command]              Cleanup/Pruning for old staging tags
config                         Show configuration information

Run 'git trident <command> --help' for detailed help
EOF
}

show_push_all_help() {
    cat <<EOF
Push All Command
================

Usage: git trident push-all [OPTIONS] [REMOTE]

Push all local Git Trident changes to remote repository.

Arguments:
  REMOTE    Remote repository name (default: ${REMOTE:-origin})

Options:
  -p, --platform NAME  Push only changes for specific platform"
  -h, --help           Show this help message"

Examples:
  git trident push-all              # Push to default remote (${REMOTE:-origin})
  git trident push-all origin       # Push to origin
  git trident push-all -p android   # Only push android platform tags
  git trident push-all -p shared    # Only push shared/common platform tags

This command will:
  1. Show all un-pushed changes across all branches
  2. Perform platform-specific impact analysis (in Multi-Platform mode)
  3. Ask for confirmation before pushing
  4. Push all main branches (develop, staging, production)
  5. Push all un-pushed tags (filtered by platform if specified)
  6. Run sync verification

Platform Filtering (-p, --platform):
  Allows you to push changes belonging to a specific platform only.
  Useful for isolating releases in multi-platform (KMP) projects.
EOF
}

show_verify_sync_help() {
    cat <<EOF
Verify Sync Command
===================

Usage: git trident verify-sync [OPTIONS]

Verify that Git Trident branches are properly synchronized.

$(get_platform_info)
Options:
  -b, --brief               Show brief status summary
  -B, --check-branches      Check branch synchronization only
  -T, --check-tags          Check tag patterns and deprecated tags
  -P, --check-platform      Check platform consistency only
  -S, --check-sync          Check sync status after operations
  -e, --env BRANCH          Check specific branch
  -p, --platform NAME       Filter by specific platform
  -d, --deprecated          Show details of deprecated tags
  -r, --report              Generate detailed report file
  -h, --help                Show this help message

Examples:
  git trident verify-sync                             # Comprehensive check
  git trident verify-sync --brief                     # Quick status
  git trident verify-sync --env "$STAGING_BRANCH"     # Check staging
  git trident verify-sync --env "$PRODUCTION_BRANCH"  # Check production
  git trident verify-sync --env feature/new-ui        # Check custom branch
  git trident verify-sync --platform android          # Android platform only
  git trident verify-sync --deprecated                # Show deprecated tags
EOF
}

show_status_help() {
    cat <<EOF
Status Command
==============

Usage: git trident status

Quick synchronization status (alias for verify-sync --brief).

Shows:
  - Branch synchronization status
  - Commit counts per branch
  - Tag counts per environment
  $(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then echo "- Platform release summary"; fi)

Example:
  git trident status
EOF
}


show_version_help() {
    cat <<EOF
Version Command
===============

Usage: git trident version [COMMAND] [OPTIONS]

Show version information and system status.

Commands:
  version                   Show version information (default)
  version config            Show configuration details
  version env               Show environment information
  version health            Perform system health check
  version check-update      Check for updates
  version config-help       Show configuration help

Options:
  --verbose, -v             Enable debug output
  --help, -h                Show this help message

Examples:
  git trident version                # Full version info
  git trident version config         # Configuration details
  git trident version health         # System health check
EOF
}

show_cleanup_help() {
    cat <<EOF
Cleanup Command
===============

Usage: git trident cleanup [subcommand] [target]

Manage deprecated staging releases (RCs) and stale local branches.

Subcommands:
  prune [tags]          Delete deprecated staging tags (already in production).
                        (Deletes from both LOCAL and REMOTE)
  sync [tags|branches]  Sync local state with remote.
                        - tags: Prune local tags gone from remote.
                        - branches: Remove local branches whose remote is gone.
                        - (no target): Sync BOTH tags and branches.

Examples:
  # Manager: Clean up deprecated RC tags
  git trident cleanup prune

  # Teammate: Refresh local tags and branches after prune/merges
  git trident cleanup sync

  # Developer: Remove stale local branches ONLY
  git trident cleanup sync branches
EOF
}

show_config_help() {
    cat <<EOF
Configuration Help
==================

Usage: 
  git trident config init    Interactively setup ./git-trident-config for a new project
  git trident config show    View active configuration (alias for 'version config')

Git Trident uses a TWO-TIER configuration system:

GLOBAL CONFIG  (~/.git-trident-config)
  Machine-level settings — never committed to git.
  Controls automation, security, and debug behavior.

  Keys that belong here (GLOBAL ONLY):
    AUTO_PUSH_ON_FINISH          Push to remote after finish?
    DELETE_BRANCH_ON_FINISH      Delete branch after finish?
    REQUIRE_CONFIRMATION         Ask before critical actions?
    REQUIRE_CLEAN_WORKING_TREE   Reject dirty working tree?
    VALIDATE_REMOTE_CONNECTIVITY Check remote before ops?
    REMOTE_TAG_CACHE_DURATION    Tag cache TTL (seconds)
    CONFIG_VALIDATION_MODE       strict | relaxed
    DEBUG                        Verbose diagnostic output
    HOOKS_ENABLED                Master on/off for hooks
    GIT_TRIDENT_SKIP_HOOKS          Bypass git-trident hooks

PROJECT CONFIG  (./git-trident-config)
  Project-specific settings — COMMIT THIS FILE to git.
  Every developer on the team gets the same workflow automatically.

  Keys that belong here:
    PRODUCTION_BRANCH / STAGING_BRANCH / DEVELOP_BRANCH
    STAGING_TAG_PREFIX / PRODUCTION_TAG_PREFIX / STAGING_TAG_SUFFIX
    REMOTE
    RELEASE_* / HOTFIX_* branch prefixes
    PLATFORM_SPECIFIC_TAGS / PLATFORMS / COMMON_PLATFORMS / INDEPENDENT_PLATFORMS
    CONFLICT_STRATEGY
    HOOK_COMMIT_MSG_ENABLED / COMMIT_PREFIXES / ...
    CHANGELOG_* settings

Load order (highest priority first):
  1. ./git-trident-config          (project — committed)
  2. ./.git-trident-config         (project — hidden/git ignored)
  3. ~/.git-trident-config         (global  — machine)

NOTE: Global-only keys found in a project config are IGNORED with a warning.
      Move them to ~/.git-trident-config.

Quick setup for a new project:
  cp ~/.git-trident-global-config ./git-trident-config
  # Edit branch names, tag prefixes, platform settings...
  git add git-trident-config
  git commit -m "cmd: Add git-trident project config"

$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then
cat <<EOF2
Multi-platform Mode:
  PLATFORM_SPECIFIC_TAGS=true
  PLATFORMS="platform1 platform2 ..."
  Version format: platform-MAJOR.MINOR.PATCH[${STAGING_TAG_SUFFIX:--rc-}XX]
  Example: android-1.2.3-rc-01

EOF2
else
cat <<EOF2
Single-environment Mode (default):
  Version format: MAJOR.MINOR.PATCH[${STAGING_TAG_SUFFIX:--rc-}XX]
  Example: 1.2.3-rc-01

EOF2
fi)

View current config:
  git trident version config
EOF
}

show_tags_help() {
    cat <<EOF
Tags Command
============

Usage: git trident tags <environment>

Show available tags for specified environment.

Arguments:
  environment    Target environment (staging or production)

Examples:
  git trident tags staging
  git trident tags production

$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then
cat <<EOF2
Platform-Specific Output:
  Shows tags grouped by platform
  Example output:
    android-1.2.0-rc-01
    ios-2.0.0-rc-01
    shared-1.1.0-rc-02

EOF2
fi)
EOF
}

show_hooks_help() {
    cat <<EOF
Git Trident Hooks Management
===============================

Usage: git trident hooks <command> [target]

Commands:
  install-global          Configure git to use hooks for ALL repositories
  uninstall-global        Remove global hook configuration
  install-local           Configure current repository to use hooks
  uninstall-local         Remove hook configuration from current repository

  enable [global|project] Enable hooks in configuration (set HOOKS_ENABLED=true)
  disable [global|project] Disable hooks in configuration (set HOOKS_ENABLED=false)

  status                  Show installation and configuration status
  help                    Show this help message

Targets for enable/disable:
  global                  Modify global configuration (~/.git-trident-config)
  project                 Modify project configuration (./git-trident-config)
  (auto)                  Auto-detect (prefers project config if exists)

Examples:
  git trident hooks install-global
  git trident hooks enable project
  git trident hooks status

Note: Hooks are DISABLED by default for safety.
EOF
}

# =============================================================================
# CHANGELOG HELP
# =============================================================================

show_changelog_help() {
    cat <<EOF

📋 Git Trident Changelog Generator
==================================

Usage:
  git trident staging   changelog <version>
  git trident production changelog <version>

Description:
  Generates changelog and release note files based on commits since the
  previous tag of the same environment. Must be run from a release or hotfix branch.

Version Format:
  $(get_version_format_example)

Output Files:
  Staging Environment:
    release_notes/CHANGELOG.md    All commits (historical truth)
    release_notes/QA_NOTES.md     QA guidance (excludes: CHANGELOG_QA_EXCLUDED_PREFIXES)

  Production Environment:
    release_notes/CHANGELOG.md    All commits (historical truth)
    release_notes/RELEASE_NOTES.md User communication (excludes: CHANGELOG_RELEASE_EXCLUDED_PREFIXES)
$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then
    echo ""
    echo "  Platform-specific mode: files are stored in release_notes/<platform>/"
fi)

Commit Collection:
  Staging    → Collects commits from previous staging tag to HEAD
  Production → Collects commits from previous production tag to HEAD
               (aggregates all staging RCs into one entry for new releases)

Configuration Keys:
  CHANGELOG_QA_EXCLUDED_PREFIXES       Excluded from QA_NOTES (default: empty)
  CHANGELOG_RELEASE_EXCLUDED_PREFIXES  Excluded from RELEASE_NOTES (default: wip|cmd)
  CHANGELOG_WEBHOOK_URL (DEPRECATED/DISABLED)                Webhook URL for QA_NOTES delivery (optional)
  CHANGELOG_WEBHOOK_AUTH (DEPRECATED/DISABLED)               Webhook auth header (optional)
  CHANGELOG_WEBHOOK_FORMAT (DEPRECATED/DISABLED)             Webhook format: slack|json|raw (default: slack)

Examples:
$(if [[ "${PLATFORM_SPECIFIC_TAGS:-false}" == "true" ]]; then
    echo "  git trident staging   changelog android-1.2.3"
    echo "  git trident production changelog android-1.2.3"
else
    echo "  git trident staging   changelog 1.2.3"
    echo "  git trident production changelog 1.2.3"
fi)

EOF
}

# =============================================================================
# DISPATCHER FUNCTION (FOR BACKWARD COMPATIBILITY)
# =============================================================================

show_production_help() {
    case "${1:-}" in
        "release")
            show_production_release_help
            ;;
        "hotfix")
            show_production_hotfix_help
            ;;
        "changelog")
            show_changelog_help
            ;;
        *)
            show_production_main_help
            ;;
    esac
}

show_staging_help() {
    case "${1:-}" in
        "release")
            show_staging_release_help
            ;;
        "hotfix")
            show_staging_hotfix_help
            ;;
        "sync-tags")
            show_staging_sync_tags_help
            ;;
        "changelog")
            show_changelog_help
            ;;
        *)
            show_staging_main_help
            ;;
    esac
}

show_utility_help() {
    case "${1:-}" in
        "push-all")
            show_push_all_help
            ;;
        "verify-sync")
            show_verify_sync_help
            ;;
        "version")
            show_version_help
            ;;
        "tags")
            show_tags_help
            ;;
        "status")
            show_status_help
            ;;
        "config")
            show_config_help
            ;;
        "cleanup")
            show_cleanup_help
            ;;
        "hooks")
            show_hooks_help
            ;;
        *)
            show_utility_main_help
            ;;
    esac
}