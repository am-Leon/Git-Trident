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

# ---------------------------------------------------------------------------
# HC_06 — `--version` works where it is most needed: outside a repository, with
# no project config. It used to fall through to the repo+config gate and fail
# with "Not inside a Git repository", so a packaged tarball could not even be
# asked what version it was.
# ---------------------------------------------------------------------------
start_test_case "hc_06_version_flag_outside_repo"
OUTSIDE="$(mktemp -d)"

for flag in --version -V; do
    out="$(cd "$OUTSIDE" && "$PROJECT_ROOT/bin/git-trident" "$flag" 2>/dev/null)"
    rc=$?
    assert_success "$rc" "'git trident $flag' exits 0 outside a git repository"

    # Must land on STDOUT: the whole point is that a script can read it.
    echo "$out" | grep -qE '^git-trident [0-9]+\.[0-9]+\.[0-9]+$'
    assert_success "$?" "'git trident $flag' prints a parseable version on stdout"
done

# It must agree with the constants, or the tarball verification in build.sh is
# checking the version against itself.
const_ver="$(grep 'TRIDENT_VERSION=' "$PROJECT_ROOT/lib/git-trident-constants.sh" | head -1 | cut -d'"' -f2)"
flag_ver="$(cd "$OUTSIDE" && "$PROJECT_ROOT/bin/git-trident" --version 2>/dev/null | awk '{print $2}')"
[ "$const_ver" = "$flag_ver" ]
assert_success "$?" "--version ($flag_ver) matches TRIDENT_VERSION ($const_ver)"

rmdir "$OUTSIDE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# HC_07 — exactly one workflow file, and it gates the release on the tests.
# The release path used to live in a second file with a weaker gate.
# ---------------------------------------------------------------------------
start_test_case "hc_07_single_workflow_gates_release"
wf="$PROJECT_ROOT/.github/workflows/ci.yml"
[ -f "$wf" ]
assert_success "$?" ".github/workflows/ci.yml exists"

[ ! -f "$PROJECT_ROOT/.github/workflows/release.yml" ]
assert_success "$?" "release.yml is gone (merged into ci.yml)"

grep -q "startsWith(github.ref, 'refs/tags/v')" "$wf"
assert_success "$?" "release job is gated on a v* tag"

grep -q 'needs: \[ test, version-sync \]' "$wf"
assert_success "$?" "release job requires test + version-sync to pass first"

grep -q 'macos-latest' "$wf"
assert_success "$?" "tests run on macOS (the Bash 3.2 compatibility floor)"

# Comment lines are excluded: the workflow documents *why* PCRE is avoided, and
# matching that comment is the same false positive that made `hooks enable` a
# silent no-op.
pcre_hits="$(grep -nE 'grep[[:space:]]+-[A-Za-z]*P' "$wf" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
[ -z "$pcre_hits" ]
assert_success "$?" "no grep -P outside comments (PCRE is absent from BSD grep)"

print_summary
