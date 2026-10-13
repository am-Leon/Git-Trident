# Git Trident — bash completion
#
# Install:
#   source <git-trident-root>/completions/git-trident.bash
# or copy it into your completion directory, e.g.
#   /usr/local/etc/bash_completion.d/  (macOS, Homebrew)
#   /etc/bash_completion.d/            (Linux)
#
# Completes both `git-trident <tab>` and `git trident <tab>`.
#
# Written for Bash 3.2: no associative arrays, no `mapfile`.

_git_trident_versions() {
    # Base versions that already have staging RCs, de-duplicated.
    local prefix suffix
    prefix="$(git config --get trident.stagingTagPrefix 2>/dev/null)"
    [ -z "$prefix" ] && prefix="staging/"
    suffix="-rc-"
    git tag -l "${prefix}*" 2>/dev/null \
        | sed "s|^${prefix}||" \
        | sed "s|${suffix}[0-9]*$||" \
        | sort -u
}

_git_trident_platforms() {
    local root cfg
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
    cfg="$root/git-trident-config"
    [ -f "$cfg" ] || cfg="$root/.git-trident-config"
    [ -f "$cfg" ] || return 0
    sed -n 's/^[[:space:]]*PLATFORMS=["'"'"']\{0,1\}\([^"'"'"']*\).*/\1/p' "$cfg" | head -1
}

_git_trident() {
    local cur prev words cword
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local top="production staging status verify-sync push-all cleanup config hooks version doctor abort tags help"
    local globals="--yes --no-color --debug --help"

    # Find the first non-flag word after the command name.
    local i ns="" sub="" act=""
    for (( i=1; i<COMP_CWORD; i++ )); do
        case "${COMP_WORDS[i]}" in
            -*) continue ;;
        esac
        if   [ -z "$ns" ];  then ns="${COMP_WORDS[i]}"
        elif [ -z "$sub" ]; then sub="${COMP_WORDS[i]}"
        elif [ -z "$act" ]; then act="${COMP_WORDS[i]}"
        fi
    done

    case "$cur" in
        -*) COMPREPLY=( $(compgen -W "$globals" -- "$cur") ); return 0 ;;
    esac

    if [ -z "$ns" ]; then
        COMPREPLY=( $(compgen -W "$top" -- "$cur") ); return 0
    fi

    case "$ns" in
        production|staging)
            if [ -z "$sub" ]; then
                COMPREPLY=( $(compgen -W "release hotfix changelog sync-tags" -- "$cur") ); return 0
            fi
            case "$sub" in
                release|hotfix)
                    if [ -z "$act" ]; then
                        COMPREPLY=( $(compgen -W "start finish" -- "$cur") ); return 0
                    fi
                    # Version argument. `production hotfix start` takes a PLATFORM
                    # in multi-platform mode, not a version.
                    if [ "$ns" = production ] && [ "$sub" = hotfix ] && [ "$act" = start ]; then
                        COMPREPLY=( $(compgen -W "$(_git_trident_platforms)" -- "$cur") ); return 0
                    fi
                    COMPREPLY=( $(compgen -W "$(_git_trident_versions)" -- "$cur") ); return 0
                    ;;
                changelog|sync-tags)
                    COMPREPLY=( $(compgen -W "$(_git_trident_versions) --dry-run" -- "$cur") ); return 0
                    ;;
            esac
            ;;
        config)   COMPREPLY=( $(compgen -W "init show validate help" -- "$cur") ); return 0 ;;
        hooks)    COMPREPLY=( $(compgen -W "install-local install-global uninstall-local uninstall-global enable disable status" -- "$cur") ); return 0 ;;
        cleanup)
            if [ -z "$sub" ]; then
                COMPREPLY=( $(compgen -W "prune sync" -- "$cur") ); return 0
            fi
            case "$sub" in
                prune) COMPREPLY=( $(compgen -W "tags temp" -- "$cur") ) ;;
                sync)  COMPREPLY=( $(compgen -W "tags branches" -- "$cur") ) ;;
            esac
            return 0 ;;
        version)  COMPREPLY=( $(compgen -W "check update env config health --dry-run --yes" -- "$cur") ); return 0 ;;
        tags)     COMPREPLY=( $(compgen -W "staging production" -- "$cur") ); return 0 ;;
        status)   COMPREPLY=( $(compgen -W "--json" -- "$cur") ); return 0 ;;
        abort)    COMPREPLY=( $(compgen -W "--dry-run" -- "$cur") ); return 0 ;;
        verify-sync)
            COMPREPLY=( $(compgen -W "--brief --json --report --deprecated --platform --env" -- "$cur") ); return 0 ;;
        push-all)
            if [ "$prev" = "--platform" ] || [ "$prev" = "-p" ]; then
                COMPREPLY=( $(compgen -W "$(_git_trident_platforms)" -- "$cur") ); return 0
            fi
            COMPREPLY=( $(compgen -W "--platform $(git remote 2>/dev/null)" -- "$cur") ); return 0 ;;
    esac

    return 0
}

complete -F _git_trident git-trident

# `git trident <tab>` — git's completion calls _git_<subcommand> when present.
_git_trident_wrapper() { _git_trident; }
complete -F _git_trident_wrapper git-trident 2>/dev/null
