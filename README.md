# Git Trident

## Overview

Git Trident is a sophisticated set of Bash scripts designed to manage complex Git workflows for multi-platform
projects. It extends the standard Git Flow methodology to support:

- **Multiple Environments**: Distinct Staging and Production lifecycles.
- **Multi-Platform Support**: Managing versions for shared code (e.g., KMP) and specific platforms (e.g., Android, iOS)
  within the same repository.
- **Automated Synchronization**: Ensuring fixes propagate correctly across versions and platforms.

## Key Features

- **Dual-Mode Operation**: Supports both legacy (single-environment) and multi-platform modes.
- **Environment Management**: Separate workflows for Staging (`-rc-XX`) and Production releases.
- **Context-Aware Synchronization**: Automatically detects if a sync is from Production (rebase needed) or Staging
  Hotfix (propagation needed).
- **Cleanup Tools**: Automated pruning of old staging tags (`git trident cleanup`).
- **Hook Management**: Integrated Git hooks for commit message validation and safety checks with global/local support.
- **Safety Checks**: Pre-operation validation for clean working trees, remote connectivity, and version formats.

## Installation

### Quick Install (One-Liner)

Install the latest version directly from GitHub using `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/am-Leon/Git-Trident/main/install.sh | bash
```

This downloads the installer, fetches the latest release package, and installs Git Trident to ~/.git-trident. Your shell profile is updated automatically.

## Documentation

- **[Quick Start Guide](docs/QUICK_START.md)**: How to use the tools for daily tasks.
- **[Detailed Instructions](docs/DETAILED_INSTRUCTIONS.md)**: In-depth guide on architecture, configuration, and
  development guidelines.

## Quick Command Reference

```bash
# Start a staging release
git trident staging release start 1.2.0

# Finish a staging release
git trident staging release finish 1.2.0

# Sync tags after a production release
git trident staging sync-tags 1.2.0

# Cleanup old and deprecated staging tags (local & remote)
git trident cleanup prune

# Sync local tags with remote (removes locally what has been pruned)
git trident cleanup sync

# Manage Git hooks
git trident hooks status
git trident hooks enable
```
