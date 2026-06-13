# 🔱 Git Trident — Detailed Architecture and Reference

This document provides a comprehensive deep dive into the design, internal mechanics, command specifications, and
configuration variables of Git Trident.

---

## 🏛️ Architecture & Directory Structure

Git Trident is built as a modular suite of Bash scripts. Rather than housing all logic in a single monolithic script,
the system separates CLI entry points (dispatchers), core libraries (business logic), templates (boilerplate), and
hooks.

```text
~/.git-trident/
├── bin/                       # CLI executable entry points
│   ├── git-trident            # Main command dispatcher
│   ├── git-trident-uninstall  # Uninstall CLI tool
│   ├── git-trident-*          # Subcommand handlers (e.g. status, config, verify-sync)
│   └── ...
├── lib/                       # Internal libraries (sourced, not run directly)
│   ├── git-trident-common.sh  # Core helper functions, config loading, logging
│   ├── git-trident-constants.sh # Shared constants (version, branch names, tags)
│   ├── git-trident-help.sh    # Centralized help manuals
│   ├── git-trident-hooks.sh   # Hook loader and helper scripts
│   ├── git-trident-staging.sh # Staging environment operations
│   ├── git-trident-production.sh # Production environment operations
│   └── ...
├── templates/                 # Boilerplate configuration templates
│   ├── git-trident-config     # Committed project config template
│   └── git-trident-global-config # Local-only global config template
└── hooks/                     # Pre-packaged Git hooks (e.g., commit-msg)
```

### Script Execution Lifecycle

When a user runs a command like `git trident staging release start 1.0.0`:

1. **Main Entry**: The main `git-trident` dispatcher script in `bin/` intercepts the request.
2. **Library Loading**: It sources `lib/git-trident-common.sh`.
3. **Configuration Injection**: `common.sh` loads and merges the configuration hierarchy (Global
   `~/.git-trident-config` → Hidden Local `./.git-trident-config` → Project `./git-trident-config`).
4. **Preconditions & Validation**: The dispatcher performs sanity checks (e.g., verifying a clean working tree or
   checking if we are inside a Git repository).
5. **Delegation**: The command is delegated to the appropriate subcommand executable in `bin/` (e.g.,
   `git-trident-staging`).

---

## 🔄 Core Release Lifecycle Mechanics

### 1. Staging Release Flow

Staging releases manage the QA and stabilization phase of a version candidate.

#### Starting a Staging Release

Running `git trident staging release start <version>`:

1. Validates that the version format is correct (`MAJOR.MINOR.PATCH`).
2. Confirms that no previous Release Candidate tags or branches exist for this version.
3. Checks out the `develop` branch (or a specified commit) and pulls updates.
4. Creates a new release branch named `release/staging/<version>`.

*Note: The command only checks out the new branch. No git tags or release candidates are created at this stage.*

#### Staging Hotfixes

If the QA team identifies a bug in the project build output, a staging hotfix is executed:

1. `git trident staging hotfix start <version>` checks out a branch `hotfix/staging/<version>` stemming from the latest
   RC tag (e.g. `staging/1.0.0-rc-01`).
2. The developer makes changes, updates version or QA notes, and commits the fixes.
3. Running `git trident staging hotfix finish <version>` creates the next increment tag (`staging/1.0.0-rc-02`), merges
   it to `staging`, and syncs changes to `develop`.
4. The developer builds from the new tag `staging/1.0.0-rc-02` and shares the build output with the QA team.

#### Finishing a Staging Release

When the developer completes release preparations (version bumping, QA notes, etc.) on the release branch:

1. Merges the release branch into the `staging` branch.
2. Tags the merge commit as `staging/<version>-rc-01`.
3. Deletes the local and remote release branches.
4. Synchronizes the changes back into the `develop` branch to keep them in sync.
5. The developer then compiles the project build output (artifact) from the created tag (`staging/<version>-rc-01`) and
   delivers it to the QA team.

---

### 2. Production Release Flow

Production releases promote validated staging releases to the live environment.

```text
[ staging/1.0.0-rc-02 ] (Latest RC Tag)
          │
          ▼ (production release start)
[ release/prod-1.0.0 ] (Release Branch)
          │
          ▼ (production release finish)
[ production ] (Merge & Tag production/1.0.0)
          │
          ├─────────────────────────┐
          ▼ (Sync Back)             ▼ (Sync Back)
     [ staging ]               [ develop ]
```

#### Promoting Staging to Production

1. **Start**: Running `git trident production release start 1.0.0` looks up the highest staging RC tag (e.g.,
   `staging/1.0.0-rc-02`) and checks out a temporary release branch `release/prod-1.0.0` from that tag.
2. **Finish**: Running `git trident production release finish 1.0.0` merges the temporary release branch into the
   `production` branch, creates the immutable tag `production/1.0.0`, and deletes the release branch.
3. **Upstream Sync**: It automatically propagates the production release commits back to both the `staging` and
   `develop` branches.

#### Production Hotfixes

Critical live issues are resolved directly on production:

1. `git trident production hotfix start` auto-detects the latest production tag and increments the patch version (e.g.,
   `1.0.0` → `1.0.1`).
2. It creates a hotfix branch `hotfix/prod-1.0.1` directly from the production branch.
3. Once the bug is fixed, `git trident production hotfix finish` merges the hotfix back into `production`, tags
   `production/1.0.1`, and merges it back down to `staging` and `develop`.

---

## 🔀 Synchronization Logic (`sync-tags`)

The `git-trident staging sync-tags <version>` command handles the cascading propagation of changes to newer, active
releases.

### Scenario A: Production Release Sync

When version `1.0.0` is finalized and released to production, newer release candidates (e.g., `1.1.0-rc-01` or
`1.2.0-rc-01`) do not yet contain the production-ready fixes from the `1.0.0` branch.

- **Action**: Git Trident automatically detects that `1.0.0` is a production version.
- **Resolution**: It rebases or merges the `production/1.0.0` changes into each active newer release branch, generating
  fresh RCs (e.g. `1.1.0-rc-02` containing the `1.0.0` production fixes).

### Scenario B: Staging Hotfix Sync

If a bug is fixed during staging of `1.0.0` (producing `1.0.0-rc-02`), and a concurrent staging release `1.1.0-rc-01` is
already in progress:

- **Action**: Sourcing the sync command on the staging version `1.0.0`.
- **Resolution**: The staging hotfix commits are cherry-picked or merged directly into the `1.1.0-rc-01` release
  candidate branch, incrementing it to `1.1.0-rc-02`.

---

## 🌐 Multi-Platform (KMP) Deep Dive

In multi-platform projects (e.g., Kotlin Multiplatform), you may have shared core libraries and independent platforms in
the same repository. Git Trident implements platform-specific versioning using the prefix format:
`<platform>-MAJOR.MINOR.PATCH`.

### 1. Platform Propagation Rules

Platform topology is defined using three config arrays: `PLATFORMS`, `COMMON_PLATFORMS`, and `INDEPENDENT_PLATFORMS`.

- **Common Platform**: (e.g. `shared`). A release or hotfix on a common platform affects all other dependent platforms.
  Sourcing `sync-tags shared-1.0.0` will automatically propagate those changes to all other platforms.
- **Independent Platform**: (e.g. `android` or `ios`). A hotfix on `android-1.0.0` is isolated and does not affect the
  `ios` release candidate.

```text
                  [ Shared Platform release ]
                               │
            ┌──────────────────┴──────────────────┐
            ▼ (Propagates)                        ▼ (Propagates)
[ Android release candidate ]          [ iOS release candidate ]
```

---

## 📝 Changelog and Notes Generation

Git Trident automates changelog creation, outputting three distinct release files inside the repository when completing
staging or production releases:

1. **`CHANGELOG.md`**: The primary developer-facing changelog. Contains all conventional commits (e.g. `feat: ...`,
   `fix: ...`) since the previous release.
2. **`QA_NOTES.md`**: Dedicated notes for quality assurance engineers. Highlights commits tagged with `test:` or `qa:`,
   and excludes routine refactoring or documentation work.
3. **`RELEASE_NOTES.md`**: Public, high-level summaries suitable for app stores or stakeholders. Typically filters out
   internal commits and aggregates user-facing features (`feat:`).

---

## 🔄 Update Checking & Self-Upgrades

Git Trident features built-in self-update subcommands under the `version` command namespace to help developers stay
up-to-date with remote releases on GitHub.

### 1. `git trident version check`

Queries the GitHub Releases API to see if a newer version tag exists on the remote repository compared to the local
`TRIDENT_VERSION`.

- **Exit Codes**: Returns exit code `1` if an update is available (non-zero exits can be used for scripting
  notifications) or `0` if the CLI is fully up-to-date.

### 2. `git trident version update [--dry-run] [--yes]`

Initiates the self-upgrade flow:

- `--dry-run`: Performs a dry run, outputting download URLs and command setups without executing them.
- `--yes` or `-y`: Automatically accepts the confirmation prompt (suited for non-interactive scripting/CI).
- **Behavior**: Downloads the latest `install.sh` from the repository to a temp location and runs it, which
  automatically replaces the binaries and re-sources shell PATH configurations.

---

## 🧪 Testing Framework & Verification

Git Trident includes an automated unit-test runner and test suites located in the `tests/` directory to verify CLI
behaviors across different platforms.

### Test Runner

Run all test suites by executing the master runner script:

```bash
bash tests/run_all.sh
```

### Core Test Suites

- **`tests/test_version_utils.sh`**: Validates version parsing, platform extraction, and tag format regex checks.
- **`tests/test_sync_utils.sh`**: Validates tag matching, sorting, and tag boundary extraction.
- **`tests/test_staging_prod_validators.sh`**: Validates version ranges and environment rules.
- **`tests/test_commit_msg.sh`**: Tests the git commit hook verification regex.
- **`tests/test_config_cleanup_hooks.sh`**: Tests configuration parsing, tag pruning, and hook installations.
- **`tests/test_remote_installation.sh`**: Validates remote install paths, path updates, and centralized constant
  checks.
- **`tests/test_build.sh`**: Validates `build.sh` exit status, tarball package generation, and packaging structures.
- **`tests/test_uninstall.sh`**: Validates standalone uninstaller (`git-trident-uninstall`), PATH removal, config
  cleanup, and profile restoration inside sandboxed environments.
- **`tests/test_bump_version.sh`**: Validates release version bumping validations, local file edits, and git push/tag
  mock operations.

---

## ⚙️ Configuration Reference

### Global Variables (`~/.git-trident-config`)

Global settings apply to the local developer machine and should not be checked into Git.

| Variable                       | Type      | Default    | Description                                                                                                 |
|--------------------------------|-----------|------------|-------------------------------------------------------------------------------------------------------------|
| `AUTO_PUSH_ON_FINISH`          | `Boolean` | `false`    | Automatically pushes branches and tags to the remote repository upon finishing a release/hotfix.            |
| `DELETE_BRANCH_ON_FINISH`      | `Boolean` | `true`     | Automatically deletes local release or hotfix branches after they have been successfully merged.            |
| `REQUIRE_CONFIRMATION`         | `Boolean` | `true`     | Prompts the user with `[y/N]` verification before executing destructive or major actions.                   |
| `REQUIRE_CLEAN_WORKING_TREE`   | `Boolean` | `true`     | Aborts operations early if there are uncommitted modifications or untracked files in the working directory. |
| `VALIDATE_REMOTE_CONNECTIVITY` | `Boolean` | `true`     | Verifies connection to the remote server before allowing a release or hotfix operation to start.            |
| `REMOTE_TAG_CACHE_DURATION`    | `Integer` | `300`      | Time (in seconds) that remote tag searches are cached locally to reduce network latency.                    |
| `CONFIG_VALIDATION_MODE`       | `String`  | `"strict"` | Sets the level of strictness for configuration parameters (`strict` or `relaxed`).                          |
| `DEBUG`                        | `Boolean` | `false`    | Enables verbose debug output and traces commands.                                                           |
| `HOOKS_ENABLED`                | `Boolean` | `false`    | Master toggle to enable or disable Git Trident's integrated Git hooks.                                      |
| `GIT_TRIDENT_SKIP_HOOKS`       | `Boolean` | `false`    | Global environment bypass flag for pre-commit or commit-msg validations.                                    |

---

### Project Variables (`./git-trident-config`)

Project settings govern repository workflows and must be committed to Git.

| Variable                 | Type      | Default         | Description                                                                      |
|--------------------------|-----------|-----------------|----------------------------------------------------------------------------------|
| `DEVELOP_BRANCH`         | `String`  | `"develop"`     | The default development branch where features are integrated.                    |
| `STAGING_BRANCH`         | `String`  | `"staging"`     | The branch representing the staging/QA environment.                              |
| `PRODUCTION_BRANCH`      | `String`  | `"main"`        | The branch representing the live/production environment.                         |
| `STAGING_TAG_PREFIX`     | `String`  | `"staging/"`    | The namespace prefix prepended to all staging release tags.                      |
| `PRODUCTION_TAG_PREFIX`  | `String`  | `"production/"` | The namespace prefix prepended to all production release tags.                   |
| `STAGING_TAG_SUFFIX`     | `String`  | `"-rc-"`        | Suffix pattern used to separate the base version from the candidate number.      |
| `REMOTE`                 | `String`  | `"origin"`      | The name of the remote Git server.                                               |
| `PLATFORM_SPECIFIC_TAGS` | `Boolean` | `false`         | Set to `true` to enable multi-platform releases.                                 |
| `PLATFORMS`              | `String`  | `""`            | Space-separated list of active platform names (e.g. `"android ios shared"`).     |
| `COMMON_PLATFORMS`       | `String`  | `""`            | Platforms whose changes propagate to dependent environments.                     |
| `INDEPENDENT_PLATFORMS`  | `String`  | `""`            | Platforms that stay isolated from other releases.                                |
| `CONFLICT_STRATEGY`      | `String`  | `"interactive"` | How merge conflicts are handled (`interactive`, `prefer-ours`, `prefer-theirs`). |
