#!/bin/bash
# tests/test_subprocess_config.sh
# Configuration must not cross process boundaries.
#
# bin/git-trident dispatches several commands with `exec`, so the child is a
# fresh process that loads configuration itself. A bug slipped through because
# nothing exercised that path:
#
#   load_project_config exported CONFIG_LOADED=true, but the strict parser sets
#   values with `printf -v` (deliberately NOT exported). The child therefore
#   inherited the FLAG, short-circuited loading, and found every setting empty.
#   `git trident status` reported branch desynchronisation on a perfectly
#   synchronised repository, while running git-trident-verify-sync directly
#   reported it correctly.
#
# Every existing suite passed before and after that fix, because they all source
# the libraries in-process. These tests drive the real binaries instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX="$SCRIPT_DIR/sandbox_subprocess"
SANDBOX_REMOTE="$SCRIPT_DIR/sandbox_subprocess_remote.git"

setup() {
    rm -rf "$SANDBOX" "$SANDBOX_REMOTE"
    mkdir -p "$SANDBOX/home" "$SANDBOX/repo"
    export HOME="$SANDBOX/home"
    cp "$PROJECT_ROOT/templates/git-trident-global-config" "$HOME/.git-trident-config"
    printf '\nREQUIRE_CONFIRMATION=false\nVALIDATE_REMOTE_CONNECTIVITY=false\n' >> "$HOME/.git-trident-config"

    cd "$SANDBOX/repo" || exit 1
    git init -q -b develop .
    git config user.email "test@git-trident.local"
    git config user.name  "Git Trident Test"
    cp "$PROJECT_ROOT/templates/git-trident-config" ./git-trident-config
    echo seed > file.txt
    git add -A && git commit -qm "feat: Initial seed commit here"
    git branch staging && git branch production
    git init -q --bare "$SANDBOX_REMOTE"
    git remote add origin "$SANDBOX_REMOTE"
    git push -q --all origin
}

teardown() {
    cd "$SCRIPT_DIR" || exit 1
    rm -rf "$SANDBOX" "$SANDBOX_REMOTE"
}

start_suite "Subprocess Configuration Isolation"

setup

# ---------------------------------------------------------------------------
# SP_01 — dispatched and direct invocation must agree
# ---------------------------------------------------------------------------
start_test_case "sp_01_dispatcher_and_direct_agree"

direct=$("$PROJECT_ROOT/bin/git-trident-verify-sync" --brief 2>&1 \
         | grep -E 'Production → Staging|Staging → Develop')
dispatched=$("$PROJECT_ROOT/bin/git-trident" status 2>&1 \
         | grep -E 'Production → Staging|Staging → Develop')

assert_equals "$dispatched" "$direct" \
    "'git trident status' matches 'git-trident-verify-sync --brief'"

assert_contains "$dispatched" "✅" \
    "Dispatched status reports a synchronised repository as synchronised"

# ---------------------------------------------------------------------------
# SP_02 — configuration does not leak into the environment
# ---------------------------------------------------------------------------
# Leaked settings are not merely untidy: a value inherited from an unrelated
# repository silently overrides the one in the project being operated on.
start_test_case "sp_02_config_not_exported"

leaked=$(bash -c "
    source '$PROJECT_ROOT/lib/git-trident-common.sh' >/dev/null 2>&1
    env | grep -E '^(CONFIG_LOADED|PRODUCTION_BRANCH|STAGING_BRANCH|DEVELOP_BRANCH|REMOTE|STAGING_TAG_PREFIX|PRODUCTION_TAG_PREFIX|AUTO_PUSH_ON_FINISH)='
" 2>/dev/null)

assert_equals "$leaked" "" "No configuration key is exported to child processes"

# ---------------------------------------------------------------------------
# SP_03 — a stale CONFIG_LOADED in the environment must not blank the config
# ---------------------------------------------------------------------------
start_test_case "sp_03_stale_config_loaded_flag"

out=$(CONFIG_LOADED=true "$PROJECT_ROOT/bin/git-trident" status 2>&1 \
      | grep -E 'Production → Staging')
assert_contains "$out" "✅" \
    "An inherited CONFIG_LOADED=true does not produce an empty configuration"

# ---------------------------------------------------------------------------
# SP_04 — dispatched subcommands work from a subdirectory
# ---------------------------------------------------------------------------
start_test_case "sp_04_dispatched_from_subdirectory"

mkdir -p "$SANDBOX/repo/a/b/c"
cd "$SANDBOX/repo/a/b/c" || exit 1
out=$("$PROJECT_ROOT/bin/git-trident" status 2>&1)
assert_not_contains "$out" "No project configuration file found" \
    "'git trident status' works three directories below the repository root"
assert_contains "$out" "✅" "Status is still correct from a subdirectory"
cd "$SANDBOX/repo" || exit 1

teardown
print_summary
