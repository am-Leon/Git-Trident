#!/bin/bash
# tests/lib/repo_fixture.sh
# Throwaway repositories for end-to-end tests.
#
# The existing suites exercise pure string functions in-process. That is why a
# string of real defects survived: `verify-sync --env` calling eight functions
# that did not exist, `push-all` failing with "Failed to push 1 tags:" when there
# was nothing to push, and configuration silently blanking across an `exec`
# boundary. Every one of them reproduced in under ten lines against a real
# repository, and none of them were visible to a test that sources a library.
#
# Three properties this fixture guarantees, each learned from a bug:
#
#   1. ISOLATED HOME. tests/sandbox_test used to live inside the Git Trident
#      checkout, so it inherited this repo's own `origin` and resolved its
#      repository root to the project itself. A test run once wrote a generated
#      config into the real project root.
#   2. A REAL BARE REMOTE. pre_operation_checks requires `origin` to exist and
#      be reachable; a fake URL makes tests pass for the wrong reason.
#   3. SEPARATE stdout / stderr / exit STATUS. `command not found` and a zero
#      exit code coexisted happily for months because assertions only ever
#      looked at combined output.

# Resolve the project root from this file's own location.
GT_FIXTURE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GT_FIXTURE_PROJECT_ROOT="$(cd "$GT_FIXTURE_LIB_DIR/../.." && pwd)"
GT_BIN="$GT_FIXTURE_PROJECT_ROOT/bin"

# Populated by gt_fixture_new_repo
GT_FIXTURE_ROOT=""      # sandbox base
GT_FIXTURE_REPO=""      # working tree
GT_FIXTURE_REMOTE=""    # bare remote
GT_FIXTURE_HOME=""      # isolated HOME

# Captured by gt_fixture_run
GT_RUN_STDOUT=""
GT_RUN_STDERR=""
GT_RUN_STATUS=0

# ---------------------------------------------------------------------------
# gt_fixture_new_repo [name]
# ---------------------------------------------------------------------------
# Creates: <tmp>/<name>/{home,repo,remote.git}, with develop/staging/production
# branches, a seed commit, a project config and a reachable origin.
# Leaves the shell inside the working tree with HOME pointed at the sandbox.
gt_fixture_new_repo() {
    local name="${1:-fixture}"

    GT_FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gt-${name}-XXXXXX")"
    GT_FIXTURE_HOME="$GT_FIXTURE_ROOT/home"
    GT_FIXTURE_REPO="$GT_FIXTURE_ROOT/repo"
    GT_FIXTURE_REMOTE="$GT_FIXTURE_ROOT/remote.git"

    mkdir -p "$GT_FIXTURE_HOME" "$GT_FIXTURE_REPO"
    export HOME="$GT_FIXTURE_HOME"

    # Global config: non-interactive and offline-friendly, so tests never block
    # on a prompt or depend on the network.
    cp "$GT_FIXTURE_PROJECT_ROOT/templates/git-trident-global-config" \
       "$GT_FIXTURE_HOME/.git-trident-config"
    {
        echo ""
        echo "REQUIRE_CONFIRMATION=false"
        echo "VALIDATE_REMOTE_CONNECTIVITY=false"
        echo "DELETE_BRANCH_ON_FINISH=true"
        echo "AUTO_PUSH_ON_FINISH=false"
    } >> "$GT_FIXTURE_HOME/.git-trident-config"

    cd "$GT_FIXTURE_REPO" || return 1
    git init -q -b develop .
    git config user.email "fixture@git-trident.local"
    git config user.name  "Git Trident Fixture"
    # Never let the developer's global hooks fire inside a fixture.
    git config core.hooksPath "$GT_FIXTURE_REPO/.git/hooks"

    cp "$GT_FIXTURE_PROJECT_ROOT/templates/git-trident-config" ./git-trident-config

    echo "seed" > README.txt
    git add -A
    git commit -qm "feat: Add initial project seed"

    git branch staging
    git branch production

    git init -q --bare "$GT_FIXTURE_REMOTE"
    git remote add origin "$GT_FIXTURE_REMOTE"
    git push -q --all origin

    return 0
}

# ---------------------------------------------------------------------------
# gt_fixture_platform_repo [name]
# ---------------------------------------------------------------------------
# As above, in multi-platform mode: shared (common) + android/ios (independent).
gt_fixture_platform_repo() {
    gt_fixture_new_repo "${1:-platform}" || return 1
    {
        echo ""
        echo 'PLATFORM_SPECIFIC_TAGS=true'
        echo 'PLATFORMS="shared android ios"'
        echo 'COMMON_PLATFORMS="shared"'
        echo 'INDEPENDENT_PLATFORMS="android ios"'
    } >> "$GT_FIXTURE_REPO/git-trident-config"
    git add -A && git commit -qm "feat: Enable multi platform mode"
    git push -q --all origin
    return 0
}

# ---------------------------------------------------------------------------
# gt_fixture_commit <message> [file]
# ---------------------------------------------------------------------------
# Each commit touches its OWN file by default.
#
# Appending every change to one shared file makes independent release lines
# conflict artificially: a hotfix on 1.0.0 then collides with 2.0.0 purely
# because both appended to README.txt. Tests that WANT a conflict should pass an
# explicit shared filename.
GT_FIXTURE_COMMIT_SEQ=0
gt_fixture_commit() {
    local message="$1"
    local file="${2:-}"
    if [ -z "$file" ]; then
        GT_FIXTURE_COMMIT_SEQ=$((GT_FIXTURE_COMMIT_SEQ + 1))
        file="change_${GT_FIXTURE_COMMIT_SEQ}.txt"
    fi
    printf '%s\n' "$message" >> "$file"
    git add -A
    git commit -qm "$message"
}

# gt_fixture_tag <tag> [ref]
gt_fixture_tag() {
    git tag -a "$1" "${2:-HEAD}" -m "fixture tag $1"
}

# ---------------------------------------------------------------------------
# gt_fixture_run <args...>
# ---------------------------------------------------------------------------
# Runs bin/git-trident, capturing stdout, stderr and the exit status
# INDEPENDENTLY. Combining them is how `command not found` on stderr went
# unnoticed next to a zero exit status.
gt_fixture_run() {
    local out_file err_file
    out_file="$(mktemp "${TMPDIR:-/tmp}/gt-out-XXXXXX")"
    err_file="$(mktemp "${TMPDIR:-/tmp}/gt-err-XXXXXX")"

    # stdin from /dev/null, always.
    #
    # REQUIRE_CONFIRMATION=false silences confirm_action, but NOT
    # force_confirm_action, which prompts unconditionally because resolving a
    # merge conflict genuinely requires a human. With an inherited stdin a test
    # that hits a conflict blocks forever instead of failing; with /dev/null the
    # read sees EOF, the default (No) applies, and the command exits non-zero.
    # GT_BIN goes on PATH for the call.
    #
    # The binary is invoked by absolute path, so this looks redundant — it is
    # not. `doctor` checks whether git-trident is reachable as `git trident`,
    # and without this the answer came from the machine running the suite: it
    # passed for anyone with the tool installed and failed for everyone else,
    # CI included. A fixture must not read state from its host.
    PATH="$GT_BIN:$PATH" "$GT_BIN/git-trident" "$@" >"$out_file" 2>"$err_file" </dev/null
    GT_RUN_STATUS=$?

    GT_RUN_STDOUT="$(cat "$out_file")"
    GT_RUN_STDERR="$(cat "$err_file")"
    rm -f "$out_file" "$err_file"

    return $GT_RUN_STATUS
}

# Combined output, for assertions that do not care which stream a line used.
gt_run_output() {
    printf '%s\n%s' "$GT_RUN_STDOUT" "$GT_RUN_STDERR"
}

# ---------------------------------------------------------------------------
# Assertions specific to integration tests
# ---------------------------------------------------------------------------

# No shell-level breakage: an undefined function, an unbound variable or a
# syntax error must fail the test even when the command exits 0.
assert_no_shell_errors() {
    local label="$1"
    local combined; combined="$(gt_run_output)"
    if printf '%s' "$combined" | grep -qE 'command not found|unbound variable|syntax error|No such file or directory'; then
        test_log "${RED}     shell-level error in output:${NC}"
        printf '%s' "$combined" | grep -E 'command not found|unbound variable|syntax error|No such file or directory' | head -5 | sed 's/^/       /'
        assert_success 1 "$label"
    else
        assert_success 0 "$label"
    fi
}

# assert_tag_exists <tag> <label>
assert_tag_exists() {
    git rev-parse "$1" >/dev/null 2>&1
    assert_success "$?" "$2"
}

# assert_tag_absent <tag> <label>
assert_tag_absent() {
    if git rev-parse "$1" >/dev/null 2>&1; then
        assert_success 1 "$2"
    else
        assert_success 0 "$2"
    fi
}

# assert_tags_equal <space-separated expected, version-sorted> <label>
assert_tags_equal() {
    local expected="$1" label="$2"
    local actual; actual="$(git tag -l | sort -V | tr '\n' ' ')"
    actual="${actual% }"
    assert_equals "$actual" "$expected" "$label"
}

# assert_branch_contains <container> <contained> <label>
assert_branch_contains() {
    local container="$1" contained="$2" label="$3"
    local missing; missing="$(git log --oneline "$container..$contained" 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "$missing" "0" "$label"
}

# ---------------------------------------------------------------------------
# gt_fixture_destroy
# ---------------------------------------------------------------------------
gt_fixture_destroy() {
    cd "$GT_FIXTURE_PROJECT_ROOT" || return 0
    [ -n "$GT_FIXTURE_ROOT" ] && [ -d "$GT_FIXTURE_ROOT" ] && rm -rf "$GT_FIXTURE_ROOT"
    GT_FIXTURE_ROOT=""; GT_FIXTURE_REPO=""; GT_FIXTURE_REMOTE=""; GT_FIXTURE_HOME=""
    return 0
}
