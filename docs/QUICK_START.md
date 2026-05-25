# Quick Start Guide

## Installation

```bash
./install.sh
```

The installer creates a **global config** at `~/.git-trident-config` with machine-level defaults
(auto-push behavior, security, debug mode). Keep this file on your machine — it is **never** committed to git.

---

## Configuration — Two-Tier System

Git Trident uses **two separate config files** that are loaded together:

| Priority    | File                    | Purpose                   | Committed to git? |
|-------------|-------------------------|---------------------------|:-----------------:|
| 1 (highest) | `./git-trident-config`  | Project settings          |       ✅ Yes       |
| 2           | `./.git-trident-config` | Project (hidden variant)  |     Optional      |
| 3 (lowest)  | `~/.git-trident-config` | Global / machine settings |       ❌ No        |

### Global config `~/.git-trident-config`

Created automatically by the installer. Contains **machine-only** keys:

```text
AUTO_PUSH_ON_FINISH        # push after finish?
DELETE_BRANCH_ON_FINISH    # delete branch after finish?
REQUIRE_CONFIRMATION       # confirm before critical actions?
REQUIRE_CLEAN_WORKING_TREE
VALIDATE_REMOTE_CONNECTIVITY
REMOTE_TAG_CACHE_DURATION
CONFIG_VALIDATION_MODE
DEBUG
HOOKS_ENABLED
GIT_TRIDENT_SKIP_HOOKS
```

### Project config `./git-trident-config`

Create one **per repo** and commit it so all teammates get the same workflow automatically. Git Trident provides an
interactive wizard to initialize this file:

```bash
git trident config init
```

The wizard will guide you through:

1. Naming branches (Production, Staging, Develop)
2. Setting custom tag prefixes/namespaces
3. Custom RC (release candidate) suffix format
4. Multi-platform settings (KMP/platform-specific tagging)

After running the wizard, review the generated file, and then commit it:

```bash
git add git-trident-config
git commit -m "wip: Add git-trident project config"
```

> ⚠️ If the tool detects global-only keys in a project config, it will print a warning and restore
> the global value — they will **not** take effect from the project file.

---

## Basic Workflow

### 1. Start a New Feature

```bash
git checkout develop
git checkout -b feature/my-feature
# ... work ...
git commit -m "feat: Add my feature"
git checkout develop
git merge feature/my-feature
```

### 2. Create a Staging Release

```bash
git trident staging release start 1.2.0
# ... test ...
git trident staging release finish 1.2.0
```

### 3. Staging Hotfix (Iterate on RC)

If a bug is found in `1.2.0-rc-01`:

```bash
git trident staging hotfix start 1.2.0
# Fix the bug...
git trident staging hotfix finish 1.2.0   # creates rc-02
```

### 4. Production Release

```bash
git trident production release start 1.2.0
git trident production release finish 1.2.0
```

### 5. Multi-Platform (KMP) Example

```bash
git trident staging release start android-1.0.0
git trident staging hotfix start shared-1.0.0
```

---

## Useful Commands

| Command                             | Description                                   |
|-------------------------------------|-----------------------------------------------|
| `git trident status`                | Quick sync status                             |
| `git trident push-all`              | Push all branches and tags                    |
| `git trident config show`           | Show active config (both files)               |
| `git trident cleanup prune`         | Delete deprecated staging RC tags             |
| `git trident cleanup sync`          | Sync local tags & branches from remote (Full) |
| `git trident cleanup sync branches` | Prune local branches whose remote is gone     |
| `git trident cleanup sync tags`     | Prune local tags that don't exist on remote   |
| `git trident verify-sync`           | Full branch/tag synchronisation check         |

---

## Hook Management

### 1. Install

```bash
git trident hooks install-global   # all repos on this machine
git trident hooks install-local    # only current repo
```

### 2. Enable

Hooks are **disabled by default**. Enable in your **global** config:

```bash
# ~/.git-trident-config
HOOKS_ENABLED=true
```

Or via command:

```bash
git trident hooks enable global    # machine-wide
git trident hooks enable project   # current project only
```

### 3. Status

```bash
git trident hooks status
```
