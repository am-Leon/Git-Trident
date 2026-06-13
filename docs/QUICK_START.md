# 🔱 Git Trident — Quick Start Guide

This guide walks you through the initial setup, basic daily workflows, configuration options, and troubleshooting for
Git Trident.

---

## 🚀 Installation

To install Git Trident on your local machine, run the following curl command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/am-Leon/Git-Trident/main/install.sh | bash
```

### What this does:

1. **Clones/Extracts Files**: Installs the command-line utility and libraries into `~/.git-trident`.
2. **Updates Profile**: Automatically adds the bin folder to your shell path in your active profile (e.g.,
   `~/.zprofile`, `~/.bash_profile`).
3. **Restarts Shell**: Safely reloads your shell in place so the `git trident` command is available immediately.
4. **Bootstraps Config**: Generates a default global configuration file at `~/.git-trident-config`.

---

## 📐 Workflow Overview

Git Trident utilizes a strict three-branch pipeline designed to ensure that code changes are properly isolated,
thoroughly QA'ed, and safely released.

```text
               (develop)
                  │
                  ├──────────────────────────────┐
                  │                              │ (1) Staging Release Start
                  ▼                              ▼
             [ Develop ]                  [ release/1.0.0 ]
                  │                              │
                  │                              │ (2) Staging Release Finish
                  ▼                              ▼
             [ Develop ]◄─────────────────[ Staging ] (QA Testing)
                  │          (Sync Back)         │
                  │                              ├─────────────────────────┐
                  │                              │                         │ (3) Production Release Start
                  ▼                              ▼                         ▼
             [ Develop ]◄─────────────────[ Staging ]◄───────────────[ release/prod-1.0.0 ]
                                                                           │
                                                                           │ (4) Production Release Finish
                                                                           ▼
                                                                     [ Production ] (Live Tag v1.0.0)
```

1. **Feature Development**: Done entirely on branches stemming from and merging into `develop`.
2. **Staging Preparation**: Code from `develop` is branched into a staging release candidate branch (
   `release/staging/<version>`) where version codes, metadata, and QA notes are finalized.
3. **Staging Release**: Completing the release branch merges the code into `staging`, creates a staging release
   candidate tag (e.g., `1.0.0-rc-01`), and syncs the changes to `develop`. The developer builds this tag and shares the
   build output (the artifact) with QA. QA tests the final build output.
4. **Staging Hotfixing**: If bugs are found during testing, a staging hotfix branch is created from the latest RC tag,
   code modifications are committed, and completing the hotfix creates the next RC tag (e.g., `1.0.0-rc-02`) and merges
   it to `staging`/`develop` for QA validation.
5. **Production Promotion**: Once a staging release candidate is approved by QA, that exact version tag is promoted and
   merged into `production` with a final release tag (e.g., `1.0.0`).
6. **Sync Back**: Every staging/production release or hotfix automatically syncs its changes back to upstream branches
   to prevent branch drift.

---

## ⚙️ Configuration System

Git Trident uses a **Two-Tier Configuration System** designed to keep individual developer preferences separate from
team-wide repository requirements.

| Layer       | Config File             | Purpose                                     |   Committed to Git?   |
|-------------|-------------------------|---------------------------------------------|:---------------------:|
| **Project** | `./git-trident-config`  | Shared repository rules and branch topology | **Yes** (Commit this) |
| **Global**  | `~/.git-trident-config` | Developer-specific machine configurations   |  **No** (Keep local)  |

### 1. Initializing Your Project Config

Navigate to the root directory of your Git repository and run:

```bash
git trident config init
```

This interactive setup wizard will prompt you for:

- Branch names (e.g., `develop`, `staging`, `production`).
- Tag namespaces (e.g., `staging/` and `production/`).
- Suffix formatting (`-rc-`).
- Multi-platform support flags (e.g., enabling platform-specific tags in KMP environments).

Once completed, commit the newly created `./git-trident-config` to your repository:

```bash
git add git-trident-config
git commit -m "chore: Initialize git-trident project configuration"
```

### 2. Concrete Config Examples

#### Global Config (`~/.git-trident-config`)

This holds settings specific to your environment. For instance, you can disable confirmations for speed or toggle
automatic remote pushing:

```bash
AUTO_PUSH_ON_FINISH=true        # Automatically push to origin on release finish
DELETE_BRANCH_ON_FINISH=true    # Clean up local release/hotfix branches after merge
REQUIRE_CONFIRMATION=true       # Require manual [y/N] prompt for critical actions
REQUIRE_CLEAN_WORKING_TREE=true # Fail early if you have uncommitted files
HOOKS_ENABLED=true              # Enable Git Trident hooks for this machine
DEBUG=false                     # Disable verbose shell logging
```

#### Project Config (`./git-trident-config`)

This defines the structural topology of the repository for all team members:

```bash
DEVELOP_BRANCH="develop"
STAGING_BRANCH="staging"
PRODUCTION_BRANCH="main"
STAGING_TAG_PREFIX="staging/"
PRODUCTION_TAG_PREFIX="production/"
STAGING_TAG_SUFFIX="-rc-"
REMOTE="origin"
PLATFORM_SPECIFIC_TAGS=false
```

> [!WARNING]
> If a developer places global-only keys (e.g., `AUTO_PUSH_ON_FINISH`) inside the project config file, Git Trident will
> ignore them and output a warning.

---

## 🛠️ Step-by-Step Release Walkthrough

### 1. Starting a Staging Release

When you are ready to prepare a new release `1.0.0`, run:

```bash
git trident staging release start 1.0.0
```

- **Why**: This creates a release branch (`release/staging/1.0.0`) from the latest commit on `develop`, allowing you to
  lock down the code and make final adjustments (version codes, build metadata, QA notes) while work continues on the
  `develop` branch.

### 2. Finishing a Staging Release (Creating the RC Build)

Once all release preparation changes are committed on the release branch, complete the staging release to create the
test candidate:

```bash
git trident staging release finish 1.0.0
```

- **Why**: This merges `release/staging/1.0.0` into the `staging` branch, tags it with the first candidate (
  `staging/1.0.0-rc-01`), deletes the release branch, and syncs changes back to `develop`.
- **Next Step**: Build your project from the generated tag `staging/1.0.0-rc-01`, and share the final build output (the
  artifact) with your QA team for testing.

### 3. Fixing Bugs in Staging (Staging Hotfixes)

If the QA team identifies a bug in the build artifact, you must apply a hotfix:

```bash
# 1. Start a hotfix branch based on the latest release candidate tag
git trident staging hotfix start 1.0.0

# 2. Make your edits on the hotfix branch and commit the fix
git commit -am "fix: resolve login layout alignment"

# 3. Complete the hotfix to tag a new release candidate
git trident staging hotfix finish 1.0.0
```

- **Why**: This increments the staging release candidate suffix (e.g., `rc-01` → `rc-02`), merges the hotfix changes
  into `staging`, deletes the hotfix branch, and syncs the fix to `develop`.
- **Next Step**: Build the project from the new tag `staging/1.0.0-rc-02` and share the new build output with QA for
  validation.

### 4. Promoting to Production

Once QA approves the final release candidate (e.g. `staging/1.0.0-rc-02`), promote the approved version directly to
production:

```bash
# 1. Start the promotion branch (automatically locates and checks out the latest approved staging RC)
git trident production release start 1.0.0

# 2. Complete the release to production
git trident production release finish 1.0.0
```

- **Why**: This checks out the highest staging RC tag (e.g., `staging/1.0.0-rc-02`), merges it into your production
  branch (e.g., `main`), tags it as `production/1.0.0`, and synchronizes all release commits back down to `staging` and
  `develop` branches.

---

## 🩺 Troubleshooting

### 1. `command not found: git-trident` (or `git: 'trident' is not a git command`)

This occurs when the installation bin directory is not in your current shell session's `PATH`.

- **Solution**: Load the changes manually in your terminal by running:
  ```bash
  source ~/.zprofile  # Or ~/.bash_profile / ~/.bashrc, depending on your shell
  ```

### 2. Configuration Validation Errors

If you see a warning or error message about missing configurations:

- **`❌ Not inside a Git repository.`**: Git Trident must be executed from inside a Git repository. Change directory into
  your repository and retry.
- **`❌ No project configuration file found.`**: The current repository has not been initialized. Initialize it by
  running:
  ```bash
  git trident config init
  ```

### 3. Commit Message Hook Failures

If you enable Git Trident hooks, you might receive rejection messages when trying to commit.

- **Why**: The integrated `commit-msg` hook enforces conventional commit messages (e.g. `feat: ...`, `fix: ...`).
- **Solution**: Rewrite your commit message to match the conventional prefix format, or bypass the validation checks
  temporarily by setting the environment variable:
  ```bash
  GIT_TRIDENT_SKIP_HOOKS=true git commit -m "wip: temporary commit"
  ```
  You can also disable hooks entirely by running:
  ```bash
  git trident hooks disable project
  ```

---

## 🔄 Checking and Installing Updates

To check if a newer version of Git Trident is available on GitHub, and to install updates directly from the CLI, use the
update subcommands:

```bash
# 1. Check if a newer version exists
git trident version check

# 2. Perform a dry-run to see what actions will be taken
git trident version update --dry-run

# 3. Interactively upgrade to the latest version
git trident version update

# 4. Perform a non-interactive, auto-accepted upgrade (useful for scripting/CI)
git trident version update --yes
```

If an update is available, the installer script is automatically downloaded to a temporary location, run in-place, and
cleanup is handled automatically.

---

## 🗑️ Uninstallation

If you need to remove Git Trident from your computer, run:

```bash
git trident uninstall
```

This script:

1. Prompts for confirmation.
2. Removes all files from `~/.git-trident`.
3. Strips the path exports from your active shell profiles.
4. Asks if you want to delete your global configuration file (`~/.git-trident-config`).
