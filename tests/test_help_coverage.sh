#!/bin/bash
# tests/test_help_coverage.sh
# Every command the dispatcher accepts must be discoverable.
#
# Help drifts silently: a command is added, routed, tested — and never listed,
# so the only people who know it exists are the ones who read the source.
# `hooks`, `doctor` and `abort` were all in that state.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GT="$PROJECT_ROOT/bin/git-trident"

# Commands routed by the dispatcher's main case statement.
COMMANDS="production staging status verify-sync push-all cleanup config hooks version doctor abort tags uninstall"
GLOBAL_FLAGS="--dry-run --yes --no-color --debug"

start_suite "Help Coverage"

# ---------------------------------------------------------------------------
# HC_01 — every command appears in the main help
# ---------------------------------------------------------------------------
start_test_case "hc_01_all_commands_listed"
main_help="$("$GT" --help 2>&1 </dev/null)"
for cmd in $COMMANDS; do
    printf '%s' "$main_help" | grep -qE "(^|[[:space:]])$cmd([[:space:]]|\$|,)"
    assert_success "$?" "'$cmd' is listed in the main help"
done

# ---------------------------------------------------------------------------
# HC_02 — every global flag is documented
# ---------------------------------------------------------------------------
start_test_case "hc_02_global_flags_documented"
for flag in $GLOBAL_FLAGS; do
    printf '%s' "$main_help" | grep -qF -- "$flag"
    assert_success "$?" "'$flag' is documented in the main help"
done

# ---------------------------------------------------------------------------
# HC_03 — `<command> --help` works for every command, from outside a repository
# ---------------------------------------------------------------------------
# Help must never need a repository, a config or the network.
start_test_case "hc_03_per_command_help_outside_a_repo"
tmp="$(mktemp -d)"
cd "$tmp" || exit 1
for cmd in $COMMANDS; do
    out="$("$GT" "$cmd" --help 2>&1 </dev/null)"
    if printf '%s' "$out" | grep -qE 'Not inside a Git repository|No project configuration|command not found'; then
        assert_success 1 "'$cmd --help' works outside a repository"
    elif [ -z "$out" ]; then
        assert_success 1 "'$cmd --help' produces output"
    else
        assert_success 0 "'$cmd --help' works outside a repository"
    fi
done
cd "$PROJECT_ROOT" || exit 1
rm -rf "$tmp"

# ---------------------------------------------------------------------------
# HC_04 — the README command table covers the same surface
# ---------------------------------------------------------------------------
start_test_case "hc_04_readme_lists_commands"
readme="$(cat "$PROJECT_ROOT/README.md")"
for cmd in $COMMANDS; do
    printf '%s' "$readme" | grep -qF "git trident $cmd"
    assert_success "$?" "README mentions 'git trident $cmd'"
done

# ---------------------------------------------------------------------------
# HC_05 — LICENSE exists, since the README links to it
# ---------------------------------------------------------------------------
start_test_case "hc_05_license_present"
[ -f "$PROJECT_ROOT/LICENSE" ]
assert_success "$?" "LICENSE file exists"
grep -q 'MIT License' "$PROJECT_ROOT/LICENSE" 2>/dev/null
assert_success "$?" "LICENSE is the MIT License the README claims"

print_summary
