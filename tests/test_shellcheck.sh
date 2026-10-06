#!/bin/bash
# tests/test_shellcheck.sh
# Static analysis gate.
#
# Several defects fixed by hand in this branch are things shellcheck finds for
# free, and would have caught before they ever shipped:
#
#   SC2086  rm -f "$cache_pattern"   — quoted glob never expanded, so the
#           remote-tag cache was never cleared (P1-3)
#   SC2206  merge_cmd+=("$merge_strategy_args") — "-X ours" passed as ONE
#           argument, so prefer-ours/prefer-theirs never worked (P0-2)
#   SC2034  assigned but never used — rc_int, latest_version, rc_number
#   SC2154  referenced but never assigned — the typo class that `set -u` would
#           catch at runtime, except `set -u` is unsafe on Bash 3.2 (A9), so it
#           is caught statically here instead
#
# Severity starts at `error` so the gate is green today and can be ratcheted to
# `warning` as findings are cleared. SC2154 is requested explicitly because it
# is only a warning but covers what A9 gave up.
#
# The tool itself is OPTIONAL: this suite skips with a visible notice when it is
# absent, so a contributor without it is not blocked. CI should install it.
# (A comment beginning "# shellcheck " is parsed as a DIRECTIVE, hence the wording.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

start_suite "ShellCheck Static Analysis"

# ---------------------------------------------------------------------------
# Availability
# ---------------------------------------------------------------------------
if ! command -v shellcheck >/dev/null 2>&1; then
    test_log "${YELLOW}  ⏭️  SKIPPED: shellcheck is not installed.${NC}"
    test_log "     Install it to enable this gate:"
    test_log "       macOS : brew install shellcheck"
    test_log "       Debian: apt-get install shellcheck"
    test_log "       Fedora: dnf install ShellCheck"
    test_log ""
    test_log "     This suite reports success so a missing optional tool does not"
    test_log "     block contributors. CI must install shellcheck, otherwise the"
    test_log "     gate silently never runs."
    print_summary
    exit 0
fi

SHELLCHECK_VERSION="$(shellcheck --version 2>/dev/null | awk '/version:/{print $2}')"
test_log "  shellcheck ${SHELLCHECK_VERSION:-unknown}"

# ---------------------------------------------------------------------------
# What to analyse
# ---------------------------------------------------------------------------
collect_targets() {
    local f
    for f in bin/* lib/*.sh hooks/* tests/*.sh tests/lib/*.sh scripts/*.sh install.sh build.sh; do
        [ -f "$f" ] || continue
        echo "$f"
    done
}

# Code that users actually run. SH_04 applies only to this set.
#
# The test harness legitimately uses patterns shellcheck dislikes: the
# project-wide idiom `[ -f some/path ]` followed by `assert_success "$?"` trips
# SC2319 (it is correct — `[` is a command — but the shape is error-prone in
# general), and the `git()` mocks trip SC2178/SC2128. Those are deliberate
# testing constructs, so holding test files to the same correctness codes would
# mean either rewriting ~100 assertions or carrying permanent exclusions.
collect_shipped_targets() {
    local f
    for f in bin/* lib/*.sh hooks/* scripts/*.sh install.sh build.sh; do
        [ -f "$f" ] || continue
        echo "$f"
    done
}

TARGETS="$(collect_targets)"
SHIPPED_TARGETS="$(collect_shipped_targets)"
target_count=$(printf '%s\n' "$TARGETS" | grep -c .)
shipped_count=$(printf '%s\n' "$SHIPPED_TARGETS" | grep -c .)
test_log "  analysing $target_count files ($shipped_count shipped)"
test_log ""

# Run shellcheck over one file and print findings in gcc format.
# --external-sources follows `source` directives so cross-file definitions are
# understood.
#
# IMPORTANT: checks that name specific codes with --include use
# `--severity=style` (the LOWEST floor), never --severity=warning. A floor is
# applied on top of --include, so asking for SC2086 (which is `note` severity)
# while flooring at `warning` silently matches nothing — the check then passes
# for the wrong reason. That mistake was present in the first version of this
# file and was only found by planting a violation and seeing it go undetected.
run_shellcheck() {
    local severity="$1" file="$2"
    shellcheck --shell=bash --severity="$severity" --format=gcc --external-sources \
               --enable=all --exclude=SC2250,SC2248,SC2292,SC2312,SC2310,SC2311,SC2249 \
               "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# SH_01 — no error-severity findings anywhere
# ---------------------------------------------------------------------------
start_test_case "sh_01_no_errors"

errors=""
for file in $TARGETS; do
    out="$(run_shellcheck error "$file")"
    [ -n "$out" ] && errors="${errors}${out}"$'\n'
done
errors="$(printf '%s' "$errors" | grep -v '^$')"

if [ -z "$errors" ]; then
    assert_success 0 "No shellcheck errors in any shipped script"
else
    test_log "${RED}     errors:${NC}"
    printf '%s\n' "$errors" | head -40 | sed 's/^/       /'
    total=$(printf '%s\n' "$errors" | grep -c .)
    [ "$total" -gt 40 ] && test_log "       ... and $((total - 40)) more"
    assert_success 1 "No shellcheck errors in any shipped script"
fi

# ---------------------------------------------------------------------------
# SH_02 — SC2154: referenced but never assigned
# ---------------------------------------------------------------------------
# This is the protection A9 gave up by not adopting `set -u` (which makes an
# empty array expansion fatal on Bash 3.2). Catching it statically is both
# stricter and portable.
start_test_case "sh_02_no_undefined_variable_references"

undefined=""
for file in $TARGETS; do
    out="$(shellcheck --shell=bash --severity=style --format=gcc --external-sources \
                      --include=SC2154 "$file" 2>/dev/null)"
    [ -n "$out" ] && undefined="${undefined}${out}"$'\n'
done
undefined="$(printf '%s' "$undefined" | grep -v '^$')"

if [ -z "$undefined" ]; then
    assert_success 0 "No references to variables that are never assigned (SC2154)"
else
    test_log "${RED}     SC2154 findings:${NC}"
    printf '%s\n' "$undefined" | head -25 | sed 's/^/       /'
    assert_success 1 "No references to variables that are never assigned (SC2154)"
fi

# ---------------------------------------------------------------------------
# SH_03 — the specific patterns that caused shipped bugs
# ---------------------------------------------------------------------------
# SC2086 unquoted/badly-quoted expansion  -> the cache glob that never expanded
# SC2206 array assignment word splitting  -> "-X ours" as a single argument
start_test_case "sh_03_no_quoting_or_array_splitting_bugs"

quoting=""
for file in $TARGETS; do
    out="$(shellcheck --shell=bash --severity=style --format=gcc --external-sources \
                      --include=SC2086,SC2206,SC2068 "$file" 2>/dev/null)"
    [ -n "$out" ] && quoting="${quoting}${out}"$'\n'
done
quoting="$(printf '%s' "$quoting" | grep -v '^$')"

if [ -z "$quoting" ]; then
    assert_success 0 "No quoting or array-splitting findings (SC2086/SC2206/SC2068)"
else
    test_log "${YELLOW}     findings:${NC}"
    printf '%s\n' "$quoting" | head -25 | sed 's/^/       /'
    total=$(printf '%s\n' "$quoting" | grep -c .)
    [ "$total" -gt 25 ] && test_log "       ... and $((total - 25)) more"
    assert_success 1 "No quoting or array-splitting findings (SC2086/SC2206/SC2068)"
fi

# ---------------------------------------------------------------------------
# SH_04 — correctness codes that are currently clean, locked in
# ---------------------------------------------------------------------------
# SC2076  quoted right-hand side of =~ matches literally, not as a regex
# SC2128  expanding an array without an index yields only the first element
# SC2178  a name used as an array and then assigned a string
# SC2034  assigned but never read (dead code, and a typo detector)
# SC2319  $? refers to a condition, not the command you think
# Each of these was non-zero before this gate existed; keeping them at zero is
# cheaper than rediscovering them.
start_test_case "sh_04_no_correctness_regressions"

correctness=""
for file in $SHIPPED_TARGETS; do
    out="$(shellcheck --shell=bash --severity=style --format=gcc --external-sources \
                      --include=SC2076,SC2128,SC2178,SC2034,SC2319 "$file" 2>/dev/null)"
    [ -n "$out" ] && correctness="${correctness}${out}"$'\n'
done
correctness="$(printf '%s' "$correctness" | grep -v '^$')"

if [ -z "$correctness" ]; then
    assert_success 0 "No SC2076/SC2128/SC2178/SC2034/SC2319 findings in shipped code"
else
    test_log "${RED}     findings:${NC}"
    printf '%s\n' "$correctness" | head -25 | sed 's/^/       /'
    assert_success 1 "No SC2076/SC2128/SC2178/SC2034/SC2319 findings in shipped code"
fi

# ---------------------------------------------------------------------------
# SH_05 — SC2155 is tracked, not enforced
# ---------------------------------------------------------------------------
# `local x=$(cmd)` masks cmd's exit status. There are ~350 instances, almost all
# harmless because the status is not consulted. Fixing them wholesale would be a
# large, risky diff for little gain, so this records the count and fails only if
# it grows — a ratchet rather than a cliff.
start_test_case "sh_05_sc2155_does_not_grow"
SC2155_BUDGET=360

sc2155=0
for file in $TARGETS; do
    n="$(shellcheck --shell=bash --severity=style --format=gcc --external-sources \
                    --include=SC2155 "$file" 2>/dev/null | grep -c .)"
    sc2155=$((sc2155 + n))
done
test_log "     SC2155 count: $sc2155 (budget $SC2155_BUDGET)"
[ "$sc2155" -le "$SC2155_BUDGET" ]
assert_success "$?" "SC2155 count stays within budget ($sc2155 <= $SC2155_BUDGET)"

print_summary
