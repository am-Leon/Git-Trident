# 🔱 Git Trident

> A Git workflow automation tool for three-branch development (develop → staging → production) with multi-platform
> support.

Git Trident is a sophisticated set of Bash scripts designed to manage complex Git release lifecycles. It extends
standard Git Flow principles to support structured Staging environments, Production hotfixing, and independent or shared
multi-platform (e.g. Kotlin Multiplatform) project versioning in a single repository.

---

## Why Git Trident?

In modern software development teams, managing releases across multiple environments is error-prone and tedious:

- **Wrong Merges**: Features accidentally bypass staging, or release hotfixes fail to propagate back to development
  branches.
- **Inconsistent Tags**: Release Candidate (RC) tags and production tags are mismanaged, making it hard to track what is
  deployed where.
- **Changelog Pain**: Writing changelogs manually or tracking QA notes across multiple branches is highly repetitive.
- **Platform Separation**: In monorepos or multi-platform setups (like Kotlin Multiplatform), you often need to release
  individual platforms (e.g., Android, iOS) or common libraries (shared) independently.

**The Solution**: Git Trident automates the heavy lifting. The name **Trident** represents the **3 prongs** of your
release pipeline: **develop**, **staging**, and **production**. It guarantees safety, checks preconditions, automates
cross-branch synchronization, and manages the release lifecycle cleanly.

---

## What It Does

Git Trident enforces and automates a **Three-Branch Workflow**:

```text
                  [ Feature Branch ]
                          │ (Merge)
                          ▼
┌──────────────────────────────────────────────────┐
│              develop (Default Dev)               │◄──────┐
└─────────────────────────┬────────────────────────┘       │
                          │ (Staging Release Start)        │ (Sync/Merge Back)
                          ▼                                │
┌──────────────────────────────────────────────────┐       │
│               staging (QA / RCs)                 ├───────┤
└─────────────────────────┬────────────────────────┘       │
                          │ (Production Release Start)     │
                          ▼                                │
┌──────────────────────────────────────────────────┐       │
│           production (Live Environment)          ├───────┘
└──────────────────────────────────────────────────┘
```

### Staging Lifecycle

1. **Start**: A release candidate branch (`release/staging/<version>`) is created from `develop`. The developer prepares
   the release on this branch (e.g. modifying version files, updating configuration, writing QA notes).
2. **Finish**: When adjustments are committed, the release is finished. This creates the first staging RC tag (e.g.,
   `staging/1.2.0-rc-01`), merges the release branch into `staging`, and syncs everything back to `develop`.
3. **Build & QA**: The developer builds the project from this RC tag and shares the build output (artifact) with the QA
   team.
4. **Iterate (Staging Hotfixes)**: If QA finds bugs in the build, the developer starts a staging hotfix (
   `hotfix/staging/<version>`) from the latest RC tag, applies changes, and completes the hotfix to increment the RC
   tag (e.g., `rc-01` → `rc-02`) for a new QA build iteration.

### Production Lifecycle

1. **Start**: A production release branch (`release/prod-<version>`) is created, promoting the latest validated staging
   RC of that version.
2. **Finish**: The release branch is merged into `production`, a production tag is created (e.g., `production/1.2.0`),
   and changes are automatically synced back to both `staging` and `develop`.
3. **Hotfix**: Live production bugs can be fixed via `production hotfix start`, which branches from `production`,
   auto-increments the patch version, and merges back to all branches upon finishing.

### Multi-Platform Mode

For monorepos (e.g., Kotlin Multiplatform), Git Trident supports releasing platforms independently (e.g.,
`android-1.2.0`, `ios-2.3.0`, `shared-1.0.0`), with strict propagation rules:

- **Common → Independent**: Changes to a common platform (e.g., `shared`) automatically propagate to dependent
  platforms.
- **Independent → Independent**: Platform-specific changes remain isolated.

---

## Quick Install

Install Git Trident directly using `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/am-Leon/Git-Trident/main/install.sh | bash
```

### What gets installed:

1. Core files are installed to `~/.git-trident`.
2. Your active shell profile (`~/.zprofile`, `~/.bash_profile`, `~/.bashrc`, or `~/.profile`) is updated to append
   `~/.git-trident/bin` to your `PATH`.
3. An interactive shell restart is triggered to apply the new path immediately.
4. A default global config template is created at `~/.git-trident-config`.

---

## Getting Started

### 1. Initialize Project Config

Run this command inside your Git repository to initialize a project configuration file:

```bash
git trident config init
```

The interactive wizard will help you configure:

- Branch names (develop, staging, production).
- Tag prefixes and RC suffixes.
- Single-environment or multi-platform mode.

Review the generated `git-trident-config` and commit it:

```bash
git add git-trident-config
git commit -m "chore: Add git-trident project configuration"
```

### 2. Perform Your First Staging Release

Create and prepare the first release candidate for version `1.0.0`:

```bash
# 1. Start the staging release (creates release/staging/1.0.0)
git trident staging release start 1.0.0

# 2. (Developer makes final adjustments: updates codes, versions, QA notes, etc. on the branch)

# 3. Complete the release (creates tag staging/1.0.0-rc-01, merges to staging/develop)
git trident staging release finish 1.0.0

# 4. Build your project from the staging/1.0.0-rc-01 tag and share the build output with the QA team.
```

### 3. Promote to Production

Once staging is approved by QA, promote it to production:

```bash
# 1. Start the production release (pulls in the latest 1.0.0 staging RC)
git trident production release start 1.0.0

# 2. Finish the production release
git trident production release finish 1.0.0
```

This merges the changes to your production branch, tags it as `production/1.0.0`, and syncs everything back to `develop`
and `staging`.

---

## Command Reference

| Namespace      | Command                                           | Description                                                    |
|----------------|---------------------------------------------------|----------------------------------------------------------------|
| **Staging**    | `git trident staging release start <version>`     | Start staging release for new version (first RC)               |
|                | `git trident staging release finish <version>`    | Merge staging release to `staging` and create tag              |
|                | `git trident staging hotfix start <version>`      | Create next RC for existing staging version                    |
|                | `git trident staging hotfix finish <version>`     | Merge hotfix to `staging` and create next RC tag               |
|                | `git trident staging sync-tags <version>`         | Propagate hotfixes or prod releases to newer RCs               |
|                | `git trident staging changelog <version>`         | Generate developer changelog (CHANGELOG/QA_NOTES)              |
| **Production** | `git trident production release start <version>`  | Promote latest staging RC to production release                |
|                | `git trident production release finish <version>` | Merge release to `production` and tag it                       |
|                | `git trident production hotfix start [platform]`  | Start a critical hotfix branch directly from production        |
|                | `git trident production hotfix finish`            | Finish production hotfix and sync changes back                 |
|                | `git trident production changelog [version]`      | Generate public release notes                                  |
| **Utility**    | `git trident status`                              | Check sync status, branch differences, and environment tags    |
|                | `git trident verify-sync`                         | In-depth verification of branches/tags sync                    |
|                | `git trident push-all [remote]`                   | Push all local staging/production/develop updates & tags       |
|                | `git trident cleanup prune`                       | Delete deprecated RC tags from local and remote                |
|                | `git trident cleanup sync [tags/branches]`        | Re-sync local git references from remote                       |
|                | `git trident config [init/show]`                  | Initialize or inspect current two-tier configuration           |
|                | `git trident hooks [install/enable/status]`       | Install/configure Git Trident git hooks                        |
|                | `git trident version [health/env]`                | Show tool version, system health check, and environment        |
|                | `git trident version [check/update]`              | Check for updates or upgrade Git Trident to the latest version |
|                | `git trident uninstall [--force]`                 | Completely remove Git Trident from your system                 |

---

## Configuration Guide

Git Trident utilizes a **Two-Tier Configuration System**:

### 1. Global Configuration (`~/.git-trident-config`)

Used for developer-specific preferences on a single machine. **Do not commit this file to Git.**

- `AUTO_PUSH_ON_FINISH`: Automatically push branches and tags to remote on command completion (`true`/`false`).
- `DELETE_BRANCH_ON_FINISH`: Auto-delete release/hotfix branches locally after completion (`true`/`false`).
- `REQUIRE_CONFIRMATION`: Interactively prompt before destructive/critical operations (`true`/`false`).
- `REQUIRE_CLEAN_WORKING_TREE`: Disallow operations if there are uncommitted changes (`true`/`false`).
- `VALIDATE_REMOTE_CONNECTIVITY`: Verify remote connectivity before starting releases (`true`/`false`).
- `HOOKS_ENABLED`: Master toggle for Git Trident git hooks (`true`/`false`).

### 2. Project Configuration (`./git-trident-config`)

Defines the workflow rules for all developers in the repository. **Commit this file to Git.**

- `DEVELOP_BRANCH` / `STAGING_BRANCH` / `PRODUCTION_BRANCH`: Branch topologies.
- `STAGING_TAG_PREFIX` / `PRODUCTION_TAG_PREFIX`: Git tag namespaces.
- `PLATFORM_SPECIFIC_TAGS`: Set to `true` to enable multi-platform releases.
- `PLATFORMS` / `COMMON_PLATFORMS` / `INDEPENDENT_PLATFORMS`: Platform propagation definitions.

> [!NOTE]
> Global-only variables placed in a project config are automatically ignored for security, and a warning is displayed.

---

## Uninstallation

To completely remove Git Trident from your computer:

```bash
git trident uninstall
```

This will cleanly remove the installation directory (`~/.git-trident`), clean your shell profile, and ask whether you
want to delete your global configuration file.

---

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for developer guidelines, setup instructions,
and testing details.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
