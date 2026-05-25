# Git Trident - Detailed Instructions & Developer Guidelines

## Project Context

This project implements a custom Git Flow workflow using Bash scripts. It supports both legacy (single-environment) and
multi-platform (e.g., KMP with Android/iOS) projects. The core logic handles versioning, tagging, branching, and
synchronization between `develop`, `staging`, and `production`.

## Architecture & Logic

### Directory Structure

- **`bin/`**: Executable entry points (`git-trident`).
- **`lib/`**: Core logic libraries sourced by executables.
- **`templates/`**: Configuration templates.

### Key Logic

#### Versioning

- **Formats**:
    - Legacy: `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)
    - Platform: `platform-MAJOR.MINOR.PATCH` (e.g., `android-1.2.3`)
- **Staging**: Always appends `-rc-XX` (e.g., `android-1.2.3-rc-01`).
- **Production**: Strictly `MAJOR.MINOR.PATCH`.

#### Synchronization

- **Production Sync**: When a production release occurs, newer staging versions are rebased to verify they include
  production changes.
- **Staging Propagation**: When a staging hotfix occurs (`rc-01` -> `rc-02`), newer staging versions must also receive
  this fix.

#### Platform Propagation Rules

1. **Common → Independent**: Changes to `shared` platform propagate to dependent platforms (e.g., `android`, `ios`).
2. **Independent → Independent**: Changes stay within the same platform.

## Configuration — Two-Tier System

Configuration is loaded from **two files** that are merged at startup:

### Global config `~/.git-trident-config`

- Created automatically by the installer.
- **Never committed to git** — stays on the developer's machine.
- Controls machine-level behavior:

| Key                            | Purpose                                   |
|--------------------------------|-------------------------------------------|
| `AUTO_PUSH_ON_FINISH`          | Push to remote after finish               |
| `DELETE_BRANCH_ON_FINISH`      | Delete release/hotfix branch after finish |
| `REQUIRE_CONFIRMATION`         | Prompt before critical actions            |
| `REQUIRE_CLEAN_WORKING_TREE`   | Reject dirty working tree                 |
| `VALIDATE_REMOTE_CONNECTIVITY` | Check remote before ops                   |
| `REMOTE_TAG_CACHE_DURATION`    | Tag cache TTL (seconds)                   |
| `CONFIG_VALIDATION_MODE`       | `strict` or `relaxed`                     |
| `DEBUG`                        | Verbose diagnostic output                 |
| `HOOKS_ENABLED`                | Master on/off switch for hooks            |
| `GIT_TRIDENT_SKIP_HOOKS`       | Bypass git-trident hooks                  |

### Project config `./git-trident-config`

- **Committed to git** — all teammates get it automatically on checkout.
- Controls workflow topology for the repository.
- Can be interactively initialized via `git trident config init` which prompts for branch names, prefixes, suffixes,
  and KMP platforms.

| Key                                                       | Purpose                                         |
|-----------------------------------------------------------|-------------------------------------------------|
| `PLATFORM_SPECIFIC_TAGS`                                  | Enable multi-platform mode (`true`/`false`)     |
| `PLATFORMS`                                               | All supported platforms (space-separated)       |
| `COMMON_PLATFORMS`                                        | Platforms that propagate to others              |
| `INDEPENDENT_PLATFORMS`                                   | Platforms that stay isolated                    |
| `STAGING_TAG_PREFIX` / `PRODUCTION_TAG_PREFIX`            | Custom tag namespaces                           |
| `PRODUCTION_BRANCH` / `STAGING_BRANCH` / `DEVELOP_BRANCH` | Branch names                                    |
| `CONFLICT_STRATEGY`                                       | `interactive` / `prefer-ours` / `prefer-theirs` |
| `CHANGELOG_*`                                             | Changelog & release-notes configuration         |

### Enforcement

- Global-only keys found in a project config file are **ignored** and a warning is printed.
- Use `git trident config show` (or the older `git trident version config` alias) to inspect both active files and
  see which values are resolved.

## Developer Guidelines

- **Language**: Bash (Shell Script).
- **Style**:
    - Use `log_info`, `log_warn`, `log_error` for output.
    - Always verify git operations (clean tree, branch existence).
    - Use `verify_step` wrapper for critical git commands.
- **Adding Commands**:
    1. Create/Modify script in `lib/`.
    2. Register command in `bin/git-trident`.
    3. Add help documentation in `lib/git-trident-help.sh`.

## Common Tasks

### Diagnostics

Check system health and active configuration:

```bash
git trident version health
git trident config show
```

### Manual Testing

Test commands in a separate dummy repository to ensure logic holds without affecting production data.

## Hook Architecture

The hook system is designed to be non-intrusive and highly configurable.

### Key Logic

- **Global vs Local**: Uses `git config --global core.hooksPath` for system-wide hooks or `git config core.hooksPath`
  for per-repo hooks.
- **Chaining**: If a local `.git/hooks/` script exists, it is automatically executed after the Git Trident hook.
- **Bypassing**: You can bypass Git Trident hooks by setting `GIT_TRIDENT_SKIP_HOOKS=true` in your environment.
- **Granular Toggles**: Each hook (e.g., `commit-msg`) can be individually enabled/disabled in the config file.

### Adding Custom Hooks

1. Add the hook script to the `hooks/` directory.
2. Ensure it sources `lib/git-trident-hooks.sh` for environment and config loading.
3. Update `lib/git-trident-hooks.sh` and the configuration template to include the new hook toggle.
