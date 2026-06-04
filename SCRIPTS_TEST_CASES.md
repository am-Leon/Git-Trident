# Git Trident - Master Test Registry

This document serves as the Source of Truth for all logic rules, validation constraints, and expected behaviors of the
scripts in the Git Trident project. Every test case listed here must have a corresponding automated test in the
`tests/` directory.

## hooks/commit-msg

**Validation Rules:**

1. **Bypass commits:** Any commit starting with "Merge " or "[flow]: " is skipped.
2. **Spacing constraint:**
    - Legacy: `^[a-zA-Z]+:[_]` (exactly one space after colon)
    - Platform: `^\[[a-zA-Z0-9_-]+\][_][a-zA-Z]+:[_]` (exactly one space after platform, exactly one space after colon)
3. **Optional `[fileName]`:** Supported as part of the description, stripped internally before checking the capitalized
   start.
4. **Capital Start:** Description must start with a capital letter (except for `cmd:` prefix).

| ID                          | Test Case Description           | Input/Trigger               | Expected Result        | Status         |
|-----------------------------|---------------------------------|-----------------------------|------------------------|----------------|
| CM_01_MERGE_BYPASS          | Bypass Merge commit             | `Merge branch develop`      | 0 (Success)            | 📝 Implemented |
| CM_02_LEGACY_VALID          | Valid legacy commit             | `feat: Add login`           | 0 (Success)            | 📝 Implemented |
| CM_03_LEGACY_SPACE_ERR      | Legacy extra space error        | `feat:  Add login`          | 1 (Fail)               | 📝 Implemented |
| CM_04_PLATFORM_VALID        | Valid platform commit           | `[android] feat: Add login` | 0 (Success)            | 📝 Implemented |
| CM_05_PLATFORM_SPACE_ERR    | Platform missing space          | `[android]feat: Add login`  | 1 (Fail)               | 📝 Implemented |
| CM_06_FILENAME_VALID        | Optional filename in desc       | `feat: [Auth] Add login`    | 0 (Success)            | 📝 Implemented |
| CM_07_FILENAME_CASE_ERR     | Filename with lower-case start  | `feat: [Auth] add login`    | 1 (Fail)               | 📝 Implemented |
| CM_08_CMD_PREFIX_LOWER      | cmd prefix allows lowercase     | `cmd: update libs`          | 0 (Success)            | 📝 Implemented |
| CM_09_CMD_PREFIX_WORD_COUNT | cmd prefix word count           | `cmd: run`                  | 1 (Fail - min 2 words) | 📝 Implemented |
| CM_10_MULTIPLE_PREFIXES     | Multiple prefixes block         | `fix: Add feat: new`        | 1 (Fail)               | 📝 Implemented |
| CM_11_LOWER_START_ERR       | Lowercase start fails           | `feat: add login flow`      | 1 (Fail)               | 📝 Implemented |
| CM_12_WORD_COUNT_ERR        | Too short description (3 words) | `feat: Add login`           | 1 (Fail)               | 📝 Implemented |
| CM_13_WORD_COUNT_VALID      | Valid 3+ word description       | `feat: Add new login`       | 0 (Success)            | 📝 Implemented |
| CM_14_FLOW_BYPASS           | Bypass Tool commit              | `[flow]: Sync: Update STG`  | 0 (Success)            | 📝 Implemented |

## lib/git-trident-version-utils.sh

**Validation Rules:**

1. **Platform Extraction:** Correctly extracts "android", "ios", etc. Returns empty if invalid format or no platform.
2. **Base Version Extraction:** Strips `-rc-XX` and platform prefixes, returning exactly `MAJOR.MINOR.PATCH`.
3. **RC Number Extraction:** Extracts the numeric padding after `-rc-` (or custom suffix).
4. **Staging Version Format:** Ensure staging releases strictly use `<platform>-X.Y.Z` or just `X.Y.Z` (no `-rc-XX`).

| ID                          | Test Case Description             | Input/Trigger                                       | Expected Result | Status         |
|-----------------------------|-----------------------------------|-----------------------------------------------------|-----------------|----------------|
| VU_01_EXTRACT_PLATFORM      | Extract platform string           | `extract_platform_from_version android-1.2.3-rc-01` | 'android'       | 📝 Implemented |
| VU_02_EXTRACT_PLATFORM_NONE | Legacy format gives no platform   | `extract_platform_from_version 1.2.3`               | ''              | 📝 Implemented |
| VU_03_BASE_VERS_PLATFORM    | Base version from platform format | `extract_base_version android-1.2.3-rc-05`          | '1.2.3'         | 📝 Implemented |
| VU_04_BASE_VERS_LEGACY      | Base version from legacy format   | `extract_base_version 1.2.3-rc-01`                  | '1.2.3'         | 📝 Implemented |
| VU_05_RC_NUM_EXTRACT        | Extract RC number padded          | `extract_rc_number 1.2.3-rc-08`                     | '08'            | 📝 Implemented |
| VU_06_RC_NUM_EXTRACT_NONE   | Base release has no RC output     | `extract_rc_number 1.2.3`                           | ''              | 📝 Implemented |
| VU_07_STG_VALID_PLATFORM    | Valid platform staging version    | Platform mode, `android-1.2.3`                      | 0 (Success)     | 📝 Implemented |
| VU_08_STG_INVALID_PLATFORM  | Platform missing in platform mode | Platform mode, `1.2.3`                              | 1 (Fail)        | 📝 Implemented |
| VU_09_STG_RC_INVALID        | Staging version cannot contain RC | Legacy mode, `1.2.3-rc-01`                          | 1 (Fail)        | 📝 Implemented |

## lib/git-trident-staging.sh

**Validation Rules:**

1. **Production Guard:** A version cannot be used for a staging operation if a production tag (`prod-<version>`) already
   exists for it.
2. **New Release Guard:** A new staging release (`staging release start`) can only be created if NO release candidates (
   `-rc-XX`) exist for that base version.

| ID                     | Test Case Description  | Input/Trigger                                                 | Expected Result | Status         |
|------------------------|------------------------|---------------------------------------------------------------|-----------------|----------------|
| STG_01_PROD_GUARD      | Production tag exists  | `validate_version_not_in_production 1.2.3` (mock tag exists)  | 1 (Fail)        | 📝 Implemented |
| STG_02_PROD_GUARD_PASS | Production tag missing | `validate_version_not_in_production 1.2.3` (mock tag missing) | 0 (Success)     | 📝 Implemented |
| STG_03_NEW_REL_GUARD   | RC tags exist for base | `validate_new_base_version 1.2.3` (mock RCs exist)            | 1 (Fail)        | 📝 Implemented |
| STG_04_NEW_REL_PASS    | No RC tags for base    | `validate_new_base_version 1.2.3` (mock no RCs)               | 0 (Success)     | 📝 Implemented |

## lib/git-trident-production.sh

**Validation Rules:**

1. **Release Blocked:** A production release cannot start if the production tag already exists for that version.

| ID                  | Test Case Description   | Input/Trigger                                   | Expected Result | Status         |
|---------------------|-------------------------|-------------------------------------------------|-----------------|----------------|
| PROD_01_TAG_EXISTS  | Prod tag already exists | `validate_release_version 1.2.3` (mock exists)  | 1 (Fail)        | 📝 Implemented |
| PROD_02_TAG_MISSING | Prod tag missing        | `validate_release_version 1.2.3` (mock missing) | 0 (Success)     | 📝 Implemented |

## lib/git-trident-staging-sync-from-production.sh

**Validation Rules:**

1. **Deprecated Prevents Sync:** If the tag being synced from is older than the latest production tag, it's considered
   deprecated and sync drops.
2. **Version Greater Rule:** A staging tag is only included for sync if its base version is greater than the production
   version syncing from (legacy mode).

| ID                      | Test Case Description   | Input/Trigger                                                    | Expected Result | Status         |
|-------------------------|-------------------------|------------------------------------------------------------------|-----------------|----------------|
| SYNC_01_NOT_DEPRECATED  | Sync from latest prod   | `validate_production_tag_not_deprecated 2.0.0` (latest is 2.0.0) | 0 (Success)     | 📝 Implemented |
| SYNC_02_DEPRECATED      | Sync from old prod      | `validate_production_tag_not_deprecated 1.0.0` (latest is 2.0.0) | 1 (Fail)        | 📝 Implemented |
| SYNC_03_INCLUDE_TAG_YES | Staging > Prod version  | `should_include_tag_for_production_sync 1.0.0 2.0.0`             | 0 (Success)     | 📝 Implemented |
| SYNC_04_INCLUDE_TAG_NO  | Staging <= Prod version | `should_include_tag_for_production_sync 2.0.0 1.0.0`             | 1 (Fail)        | 📝 Implemented |

## bin/git-trident-changelog-generation

**Validation Rules:**

1. **Three Output Files:** Staging produces `CHANGELOG.md` + `QA_NOTES.md`. Production produces `CHANGELOG.md` +
   `RELEASE_NOTES.md`.
2. **Commit Categorization:** Commits are grouped by their prefix using `COMMIT_PREFIXES` /
   `COMMIT_PREFIX_DESCRIPTIONS`.
3. **Configurable Exclusions:**
    - `CHANGELOG.md` has NO exclusions (single source of truth).
    - `QA_NOTES.md` excludes prefixes in `CHANGELOG_QA_EXCLUDED_PREFIXES`.
    - `RELEASE_NOTES.md` excludes prefixes in `CHANGELOG_RELEASE_EXCLUDED_PREFIXES` (default: `wip|cmd`).
4. **Version Headers:** Staging uses full RC version (`1.0.0-rc-02`). Production uses base version (`1.0.0`).
5. **Tag Resolution:** Previous tag is the most recent tag of the **same environment**, sorted by version across ALL
   base versions.
6. **Branch Guard:** Must run from a `release/` or `hotfix/` branch for the target environment.
7. **Production Aggregation:** New production releases aggregate all staging RC commits into one entry.
8. **Prepend Order:** New versions are prepended on top of existing file content.

| ID                       | Test Case Description              | Input/Trigger                                | Expected Result                  | Status         |
|--------------------------|------------------------------------|----------------------------------------------|----------------------------------|----------------|
| CL_01_STG_CREATES_FILES  | Staging creates CHANGELOG + QA     | Staging env, write_files                     | CHANGELOG.md + QA_NOTES.md exist | 📝 Implemented |
| CL_02_PROD_CREATES_FILES | Prod creates CHANGELOG + RN        | Production env, write_files                  | CHANGELOG.md + RELEASE_NOTES.md  | 📝 Implemented |
| CL_03_STG_HEADER_RC      | Staging header uses RC version     | resolve_version_display staging 1.0.0        | `1.0.0-rc-02`                    | 📝 Implemented |
| CL_04_PROD_HEADER_BASE   | Prod header uses base version      | resolve_version_display production 1.1.0     | `1.1.0`                          | 📝 Implemented |
| CL_05_CHANGELOG_ALL      | CHANGELOG includes all prefixes    | categorize_commits with "changelog" type     | wip + cmd included               | 📝 Implemented |
| CL_06_QA_EXCLUDES        | QA_NOTES respects exclusion config | categorize_commits with "qa_notes" type      | Configured prefix excluded       | 📝 Implemented |
| CL_07_RN_EXCLUDES        | RELEASE_NOTES excludes wip + cmd   | categorize_commits with "release_notes" type | wip + cmd excluded               | 📝 Implemented |
| CL_08_PREV_TAG_STG       | Staging finds latest across all    | Multiple staging tags, find_previous_env_tag | Latest version-sorted tag        | 📝 Implemented |
| CL_09_PREV_TAG_PROD      | Prod finds latest prod tag         | Multiple prod tags, find_previous_env_tag    | Latest prod tag                  | 📝 Implemented |
| CL_10_INITIAL_NO_TAGS    | First release — no previous tags   | Empty repo, find_previous_env_tag            | Empty string                     | 📝 Implemented |
| CL_11_BRANCH_GUARD       | Rejects wrong branch               | validate_branch from develop                 | Fails on develop, passes release | 📝 Implemented |
| CL_12_PREPEND_ORDER      | Newest version on top              | Two prepend_to_file calls                    | 2.0.0 above 1.0.0                | 📝 Implemented |
| CL_13_PROD_RC_AGGREGATE  | Prod aggregates staging RCs        | 3 staging RCs, production collect            | All RC commits in one entry      | 📝 Implemented |

## Two-Tier Configuration & Cleanup

**Validation Rules:**

1. **Layered Config Loading:** Project config loaded over global config. Global-only keys are protected.
2. **Quiet Loading:** `SUPPRESS_CONFIG_ERRORS` avoids errors during initial global installations without project
   configs.
3. **Interactive Scaffolding:** `git trident config init` successfully creates `./git-trident-config`.
4. **Cleanup Routing:** `cleanup sync [tags|branches]` and `cleanup prune [tags]` accurately dispatch commands.
5. **Dry-Run Mode:** `--dry-run` prevents state mutation and accurately logs impacts.

| ID                                   | Test Case Description                | Input/Trigger                                       | Expected Result                        | Status         |
|--------------------------------------|--------------------------------------|-----------------------------------------------------|----------------------------------------|----------------|
| CONFIG_01_INTERACTIVE_INIT           | Initializes project config wizard    | `bin/git-trident-config init`                       | File generated, variables match input  | 📝 Implemented |
| CONFIG_02_TWO_TIER_LOADING           | Project overrides global config      | `load_project_config`                               | Global defaults with project overlay   | 📝 Implemented |
| CONFIG_03_GLOBAL_ONLY_KEY_PROTECTION | Protect global-only overrides        | `load_project_config`                               | Rejects global keys in project config  | 📝 Implemented |
| CONFIG_04_SUPPRESS_ERRORS            | Quiet loading ignores missing config | `load_project_config` with `SUPPRESS_CONFIG_ERRORS` | Fail code but no stdout/stderr output  | 📝 Implemented |
| CONFIG_05_NOT_IN_GIT_REPO            | Error when not inside a Git repo     | `load_project_config` outside a Git repository      | Fails with clean git-repo error        | 📝 Implemented |
| CONFIG_06_NO_PROJECT_CONFIG          | Error when project config missing    | `load_project_config` without project config        | Fails with config init recommendation  | 📝 Implemented |
| CLEANUP_01_SUBCOMMAND_ROUTING        | Validates cleanup target dispatch    | `bin/git-trident-cleanup sync tags/branches`        | Appropriate subcommand function called | 📝 Implemented |
| CLEANUP_02_DRY_RUN_FLAG              | Validates dry-run execution          | `bin/git-trident-staging-sync-tags --dry-run`       | Pre-operation logs impact without run  | 📝 Implemented |
