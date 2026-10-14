#!/bin/bash
# Git Trident Repository Context
#
# Resolves the repository's roots ONCE, so nothing in the codebase has to assume
# that the current working directory is the repository root.
#
# Before this existed, the project config was looked up as "./git-trident-config"
# and lock/cache files were written to a literal ".git/". Both are relative to the
# CURRENT DIRECTORY, so every command failed from a subdirectory:
#
#     $ cd src/main && git trident status
#     ❌ No project configuration file found.
#
# For the monorepo / Kotlin-Multiplatform projects this tool targets, working from
# a subdirectory is the norm rather than the exception.
#
# Using `git rev-parse --absolute-git-dir` rather than "$GT_REPO_ROOT/.git" also
# makes worktrees and submodules work, where .git is a FILE pointing elsewhere.
#
# Exposed:
#   GT_REPO_ROOT  absolute path to the working tree root
#   GT_GIT_DIR    absolute path to the real git directory
#
# Portability: `rev-parse --absolute-git-dir` needs git >= 2.13 (2017). A fallback
# keeps older git and Windows/Git Bash edge cases working.

# Resolve repository context. Returns non-zero when not inside a repository,
# WITHOUT printing anything — utility commands (version, config, hooks,
# uninstall) legitimately run outside a repository and must stay usable.
gt_resolve_repo_context() {
    # Deliberately NOT cached and NOT exported.
    #
    # Caching in exported variables is wrong in both directions: a child process
    # could inherit a root belonging to a different repository, and a long-lived
    # shell that changed directory would keep resolving against the old one.
    # `git rev-parse` costs a few milliseconds and is called once per command,
    # so recomputing is cheaper than reasoning about staleness.
    GT_REPO_ROOT=""
    GT_GIT_DIR=""

    git rev-parse --git-dir >/dev/null 2>&1 || return 1

    local repo_root git_dir
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ -n "$repo_root" ]] || return 1

    git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)"
    if [[ -z "$git_dir" ]]; then
        # git < 2.13: --absolute-git-dir is unavailable. --git-dir may return a
        # relative path, so resolve it against the current directory.
        git_dir="$(git rev-parse --git-dir 2>/dev/null)" || return 1
        case "$git_dir" in
            /*) ;;
            *)  git_dir="$(cd -P "$git_dir" 2>/dev/null && pwd)" || return 1 ;;
        esac
    fi

    GT_REPO_ROOT="$repo_root"
    GT_GIT_DIR="$git_dir"
    return 0
}

# Absolute path to a file at the repository root.
#   gt_repo_path "git-trident-config"  ->  /abs/repo/git-trident-config
# Falls back to a cwd-relative path when no repository context exists, so callers
# behave sanely outside a repository instead of producing "/git-trident-config".
gt_repo_path() {
    local rel="$1"
    if [[ -n "${GT_REPO_ROOT:-}" ]]; then
        printf '%s/%s' "$GT_REPO_ROOT" "$rel"
    else
        printf './%s' "$rel"
    fi
}

# Absolute path to a file inside the git directory.
#   gt_git_path "git-trident-locks"  ->  /abs/repo/.git/git-trident-locks
gt_git_path() {
    local rel="$1"
    if [[ -n "${GT_GIT_DIR:-}" ]]; then
        printf '%s/%s' "$GT_GIT_DIR" "$rel"
    else
        printf '.git/%s' "$rel"
    fi
}
