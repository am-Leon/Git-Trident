#!/bin/bash
# tests/test_changelog.sh
# Comprehensive tests for bin/git-trident-changelog-generation
# Uses real temporary git repos with mock commits and tags.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG_SCRIPT="$PROJECT_ROOT/bin/git-trident-changelog-generation"

# =============================================================================
# TEST REPO HELPERS
# =============================================================================

# Create a temporary git repo with a known commit history.
# Returns the path to the repo via stdout.
setup_test_repo() {
    local repo_dir
    repo_dir=$(mktemp -d)

    # Save current dir
    local original_dir="$PWD"

    cd "$repo_dir" || return 1
    git init -q
    git checkout -q -b develop

    # Disable gpg signing for test commits
    git config commit.gpgsign false
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "$repo_dir"
}

cleanup_test_repo() {
    rm -rf "$1"
}

# Make a commit with a given message
make_commit() {
    local msg="$1"
    git commit -q --allow-empty -m "$msg"
}

# =============================================================================
# MOCK CONFIGURATION (exported for sourced script)
# =============================================================================

export CONFIG_LOADED=true
export STAGING_TAG_PREFIX="staging/"
export PRODUCTION_TAG_PREFIX="production/"
export STAGING_TAG_SUFFIX="-rc-"
export RELEASE_STAGING_PREFIX="release/stg/"
export RELEASE_PRODUCTION_PREFIX="release/prod/"
export HOTFIX_STAGING_PREFIX="hotfix/stg/"
export HOTFIX_PRODUCTION_PREFIX="hotfix/prod/"
export PLATFORM_SPECIFIC_TAGS=false
export PLATFORMS=""
export COMMIT_PREFIXES="wip|fix|feat|enhance|cmd"
export COMMIT_PREFIX_DESCRIPTIONS="Work In Progress|Bug Fixes|New Features|Enhancements|Commands"
export CHANGELOG_QA_EXCLUDED_PREFIXES=""
export CHANGELOG_RELEASE_EXCLUDED_PREFIXES="wip|cmd"
export CHANGELOG_WEBHOOK_URL=""
export DEBUG=false

# Source the changelog script (won't auto-execute due to guard)
source "$CHANGELOG_SCRIPT"

# =============================================================================
# SUITE: File Creation
# =============================================================================

start_suite "File Creation"

# -- CL_01: Staging creates CHANGELOG.md + QA_NOTES.md --
start_test_case "CL_01_STG_CREATES_FILES"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: Add login screen"
make_commit "fix: Resolve crash on start"
git tag "staging/1.0.0-rc-01"
git checkout -q -b "release/stg/1.0.0"
make_commit "feat: Add signup flow"

output_dir=$(get_output_dir "")
write_files "staging" "$output_dir" "1.0.0-rc-01" "April 6, 2026" "$(collect_commits 'staging/1.0.0-rc-01' HEAD)"

assert_equals "$(test -f "$output_dir/CHANGELOG.md" && echo 'yes')" "yes" "CHANGELOG.md created"
assert_equals "$(test -f "$output_dir/QA_NOTES.md" && echo 'yes')" "yes" "QA_NOTES.md created"
assert_equals "$(test -f "$output_dir/RELEASE_NOTES.md" && echo 'yes')" "" "RELEASE_NOTES.md NOT created"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# -- CL_02: Production creates CHANGELOG.md + RELEASE_NOTES.md --
start_test_case "CL_02_PROD_CREATES_FILES"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: Initial feature"
git tag "production/1.0.0"
git checkout -q -b "release/prod/1.1.0"
make_commit "feat: New dashboard"

output_dir=$(get_output_dir "")
write_files "production" "$output_dir" "1.1.0" "April 6, 2026" "$(collect_commits 'production/1.0.0' HEAD)"

assert_equals "$(test -f "$output_dir/CHANGELOG.md" && echo 'yes')" "yes" "CHANGELOG.md created"
assert_equals "$(test -f "$output_dir/RELEASE_NOTES.md" && echo 'yes')" "yes" "RELEASE_NOTES.md created"
assert_equals "$(test -f "$output_dir/QA_NOTES.md" && echo 'yes')" "" "QA_NOTES.md NOT created"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# =============================================================================
# SUITE: Version Headers
# =============================================================================

start_suite "Version Headers"

# -- CL_03: Staging header uses RC version --
start_test_case "CL_03_STG_HEADER_RC"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: Feature one"
git tag "staging/1.0.0-rc-01"
make_commit "fix: Fix one"
git tag "staging/1.0.0-rc-02"

display=$(resolve_version_display "staging" "1.0.0" "")
assert_equals "$display" "1.0.0-rc-03" "Staging display increments to next RC (03)"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# -- CL_04: Production header uses base version --
start_test_case "CL_04_PROD_HEADER_BASE"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: Feature one"
git tag "production/1.0.0"

display=$(resolve_version_display "production" "1.1.0" "")
assert_equals "$display" "1.1.0" "Production display is base version"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# -- CL_14: Staging increments appropriately even without tags --
start_test_case "CL_14_STG_INITIAL_RC"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: Initial"

display=$(resolve_version_display "staging" "1.0.0" "")
assert_equals "$display" "1.0.0-rc-01" "Staging display starts at rc-01"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# =============================================================================
# SUITE: Commit Exclusion Rules
# =============================================================================

start_suite "Commit Exclusion Rules"

COMMITS="feat: Add dark mode
fix: Fix memory leak
wip: Experimental refactor
cmd: Run database migration
enhance: Improve performance"

# -- CL_05: CHANGELOG includes all prefixes --
start_test_case "CL_05_CHANGELOG_ALL"
output=$(categorize_commits "$COMMITS" "changelog")
assert_contains "$output" "feat|||Add dark mode" "feat included"
assert_contains "$output" "fix|||Fix memory leak" "fix included"
assert_contains "$output" "wip|||Experimental refactor" "wip included in changelog"
assert_contains "$output" "cmd|||Run database migration" "cmd included in changelog"
assert_contains "$output" "enhance|||Improve performance" "enhance included"

# -- CL_06: QA_NOTES respects exclusion config --
start_test_case "CL_06_QA_EXCLUDES"
# Set QA exclusion to "cmd"
export CHANGELOG_QA_EXCLUDED_PREFIXES="cmd"
output=$(categorize_commits "$COMMITS" "qa_notes")
assert_contains "$output" "feat|||Add dark mode" "feat included in QA"
assert_contains "$output" "wip|||Experimental refactor" "wip included in QA"
assert_not_contains "$output" "cmd|||" "cmd excluded from QA"
export CHANGELOG_QA_EXCLUDED_PREFIXES=""  # reset

# -- CL_07: RELEASE_NOTES excludes wip and cmd --
start_test_case "CL_07_RN_EXCLUDES"
output=$(categorize_commits "$COMMITS" "release_notes")
assert_contains "$output" "feat|||Add dark mode" "feat included in RN"
assert_contains "$output" "fix|||Fix memory leak" "fix included in RN"
assert_not_contains "$output" "wip|||" "wip excluded from RN"
assert_not_contains "$output" "cmd|||" "cmd excluded from RN"
assert_contains "$output" "enhance|||Improve performance" "enhance included in RN"

# -- CL_15: Multi-prefix commit splitting --
start_test_case "CL_15_MULTI_PREFIX_SPLIT"
export COMMIT_PREFIXES="feat|fix|wip"
MULTI_MSG="feat: Add login fix: Resolve crash wip: Hide button"
output=$(categorize_commits "$MULTI_MSG" "changelog")
assert_contains "$output" "feat|||Add login" "Split feat"
assert_contains "$output" "fix|||Resolve crash" "Split fix"
assert_contains "$output" "wip|||Hide button" "Split wip"
export COMMIT_PREFIXES="wip|fix|feat|enhance|cmd" # reset

# =============================================================================
# SUITE: Tag Resolution
# =============================================================================

start_suite "Tag Resolution"

# -- CL_08: Staging finds previous tag across all versions (sorted) --
start_test_case "CL_08_PREV_TAG_STG"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: Feature for 1.0.0"
git tag "staging/1.0.0-rc-01"
make_commit "feat: Feature for 1.0.0 rc2"
git tag "staging/1.0.0-rc-02"
make_commit "feat: Feature for 1.1.0"
git tag "staging/1.1.0-rc-01"
make_commit "feat: Feature for 1.2.0"
git tag "staging/1.2.0-rc-01"

prev=$(find_previous_env_tag "staging" "")
assert_equals "$prev" "staging/1.2.0-rc-01" "Latest staging tag across all versions"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# -- CL_17: Hybrid tag resolution (picks production if newer) --
start_test_case "CL_17_HYBRID_TAG"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: v1"
git tag "staging/1.0.0-rc-01"
sleep 1 # Ensure different timestamp
make_commit "feat: v1 released"
git tag "production/1.0.0"

# Even though environment is staging, it should pick production/1.0.0 as it is newer
prev=$(find_previous_env_tag "staging" "")
assert_equals "$prev" "production/1.0.0" "Picks newer production tag for staging start"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# -- CL_09: Production finds previous production tag --
start_test_case "CL_09_PREV_TAG_PROD"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: v1"
git tag "production/1.0.0"
make_commit "feat: v1.1"
git tag "production/1.1.0"

prev=$(find_previous_env_tag "production" "")
assert_equals "$prev" "production/1.1.0" "Latest production tag"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# -- CL_10: Initial case — no previous tags --
start_test_case "CL_10_INITIAL_NO_TAGS"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: Very first commit"

prev=$(find_previous_env_tag "staging" "")
assert_equals "$prev" "" "Empty string for initial case"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# =============================================================================
# SUITE: Branch Validation
# =============================================================================

start_suite "Branch Validation"

# -- CL_11: Rejects wrong branch --
start_test_case "CL_11_BRANCH_GUARD"
REPO=$(setup_test_repo)
cd "$REPO" || exit
make_commit "feat: On develop"

# Should fail on develop branch
(validate_branch "staging") >/dev/null 2>&1
assert_failure "$?" "Rejects develop for staging"

# Should pass on release/stg/ branch
git checkout -q -b "release/stg/1.0.0"
(validate_branch "staging") >/dev/null 2>&1
assert_success "$?" "Accepts release/stg/ for staging"

# Should pass on hotfix/prod/ branch
git checkout -q -b "hotfix/prod/1.0.1"
(validate_branch "production") >/dev/null 2>&1
assert_success "$?" "Accepts hotfix/prod/ for production"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# =============================================================================
# SUITE: File Content & Ordering
# =============================================================================

start_suite "File Content and Ordering"

# -- CL_12: New section prepended on top of existing --
start_test_case "CL_12_PREPEND_ORDER"
REPO=$(setup_test_repo)
cd "$REPO" || exit
mkdir -p release_notes

# Write version 1.0.0 first
commits_v1="feat: First feature"
cat_v1=$(categorize_commits "$commits_v1" "changelog")
section_v1=$(generate_version_section "1.0.0" "Jan 1, 2026" "$cat_v1")
prepend_to_file "release_notes/CHANGELOG.md" "$section_v1"

# Write version 2.0.0 on top
commits_v2="feat: Second feature"
cat_v2=$(categorize_commits "$commits_v2" "changelog")
section_v2=$(generate_version_section "2.0.0" "Feb 1, 2026" "$cat_v2")
prepend_to_file "release_notes/CHANGELOG.md" "$section_v2"

# Read the file — 2.0.0 should be on top
file_content=$(cat "release_notes/CHANGELOG.md")
first_version=$(echo "$file_content" | grep "### Version:" | head -1)

assert_contains "$first_version" "2.0.0" "Newest version is on top"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# -- CL_13: Production aggregates all staging RCs into one entry --
start_test_case "CL_13_PROD_RC_AGGREGATE"
REPO=$(setup_test_repo)
cd "$REPO" || exit

# Simulate staging cycle: 3 RCs for 1.2.0
make_commit "feat: Feature from RC1"
git tag "staging/1.2.0-rc-01"
make_commit "fix: Fix from RC2"
git tag "staging/1.2.0-rc-02"
make_commit "enhance: Polish from RC3"
git tag "staging/1.2.0-rc-03"

# Production release
git tag "production/1.2.0"
git checkout -q -b "release/prod/1.2.0"

# Collect commits from previous prod tag to HEAD (no previous prod tag here)
commits=$(collect_commits "" "HEAD")

# All commits from the entire history should be present
assert_contains "$commits" "Feature from RC1" "RC1 commit present"
assert_contains "$commits" "Fix from RC2" "RC2 commit present"
assert_contains "$commits" "Polish from RC3" "RC3 commit present"

# Generate the section — should show base version 1.2.0
categorized=$(categorize_commits "$commits" "release_notes")
section=$(generate_version_section "1.2.0" "April 6, 2026" "$categorized")
assert_contains "$section" "### Version: 1.2.0" "Production header is base version"
assert_contains "$section" "Feature from RC1" "RC1 content in production notes"

# -- CL_16: Production CHANGELOG is header-only --
start_test_case "CL_16_PROD_HEADER_ONLY"
cats="feat|||A"$'\n'"fix|||B"
section=$(generate_version_section "1.2.0" "April 6, 2026" "$cats" "true")
assert_contains "$section" "### Version: 1.2.0" "Has version"
assert_not_contains "$section" "feat" "No feat bullets"
assert_not_contains "$section" "fix" "No fix bullets"
assert_contains "$section" "---" "Has separator"

# -- CL_18: Commands section uses code block --
start_test_case "CL_18_CMD_BLOCK"
cats="cmd|||npm install"$'\n'"cmd|||npm test"
section=$(generate_version_section "1.2.0" "April 6, 2026" "$cats" "false")
assert_contains "$section" "> **Commands**" "Has title"
assert_contains "$section" '```commandline' "Has code block start"
assert_contains "$section" "npm install" "Has command 1"
assert_contains "$section" "npm test" "Has command 2"
assert_contains "$section" '```' "Has code block end"
assert_not_contains "$section" "  - npm install" "No bullet points"

cd "$SCRIPT_DIR" || exit
cleanup_test_repo "$REPO"

# =============================================================================
# SUMMARY
# =============================================================================

print_summary
