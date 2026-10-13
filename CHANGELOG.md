# Changelog

All notable changes to Git Trident are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] — Unreleased

A correctness and portability release. Six commands did not work at all, and the
documented installation method could not succeed on macOS. Every defect listed
here was reproduced in a throwaway repository before the fix and re-verified
after it.

### ⚠️ Upgrade notes

**You can upgrade in place.** `git trident version update` works from v0.1.1
onward, even though v0.1.1 contains the bug that broke it — the updater fetches
`install.sh` from the repository rather than using the installed copy, and the
new installer accepts the malformed version string the old client sends. No
manual uninstall is needed.

```bash
git trident version update
```

If you prefer a clean install, or if the above fails for any reason:

```bash
curl -fsSL https://raw.githubusercontent.com/am-Leon/Git-Trident/main/install.sh | bash
```

**Two changes alter existing behavior. Read these before upgrading.**

1. **Configuration files are parsed, not executed.** A project config containing
   shell expressions — command substitution, variable interpolation — will no
   longer evaluate them. Plain `KEY=value` and `KEY="value"` are unaffected,
   which covers every generated config and every documented example. If yours
   relies on shell evaluation, set `CONFIG_PARSER=legacy` in
   `~/.git-trident-config` to restore the old behavior for one minor version,
   and migrate before the next.

2. **`config init` no longer silently writes `false` for options you accepted.**
   If you ran `config init` and pressed Enter at the `[Y/n]` prompts, your config
   has `HOOK_COMMIT_MSG_ENABLED=false` and `REQUIRE_CAPITAL_START=false` despite
   the prompt offering Yes as the default. Check those two keys after upgrading:

   ```bash
   git trident config validate
   ```

**Also worth knowing:**

- `brew install bash` is no longer required on macOS. The tool and its installer
  run on the system's Bash 3.2.
- Verification reports move from `.git/` to a gitignored `.git-trident-reports/`.
- `git trident hooks install` was never a real subcommand; use `install-local`
  or `install-global`. The README said otherwise.

### Fixed

**Commands that did not work**

- **`version update` could never download.** The release tag was stripped of its
  leading `v` before being used to build the asset URL, producing
  `.../releases/download/0.1.1/...` when the tag is `v0.1.1` — a 404 on every
  invocation. It also now refuses to "update" to an older published release.
- **`CONFLICT_STRATEGY=prefer-ours` / `prefer-theirs` never applied.** The flag
  was passed to git as a single argument, so git answered
  `fatal: unknown strategy option: -X ours`. Because git's stderr was discarded,
  this surfaced to the user as a merge conflict, dropping them into a
  conflict-resolution prompt with nothing to resolve.
- **`verify-sync --env <branch>` was discarded, then crashed.** The flag was lost
  to a positional-parsing bug, and the code path behind it called eight functions
  that were never defined — while still exiting 0. Those checks are now
  implemented.
- **`hooks enable` was a no-op that reported success.** Its search matched a
  *comment* in the shipped template, so the substitution that followed could not
  apply; it logged `✓ Updated` regardless. It also wrote to the project config,
  which cannot hold that setting. Commit-message validation was therefore never
  enabled by that command.
- **`push-all` failed when there was nothing to push.** An empty tag list was
  counted as one entry, so in multi-platform mode it reported
  `Failed to push 1 tags:` and exited 1 — the path `AUTO_PUSH_ON_FINISH=true`
  takes.
- **`curl … | bash` could not install on macOS.** The installer re-executed into
  Bash 4+ for a single color map; piped from stdin it tried to run the `bash`
  binary as a script (`cannot execute binary file`). It failed even with
  Homebrew's bash installed.

**Correctness**

- Git Trident now works from **any directory inside the repository**, and inside
  `git worktree` checkouts. Configuration, locks, caches and `release_notes/`
  were resolved relative to the current directory, so every command failed one
  level down.
- **`config init` wrote `false` for every `[Y/n]` default you accepted** — the
  default string was compared against a yes/no pattern it could never match.
- **`cleanup prune` reported success regardless of outcome**, and one tag missing
  on the remote aborted a batch of twenty silently.
- **`cleanup sync branches` produced a literal `*`** for the current branch, by
  parsing human-readable `git branch -vv` output.
- **"Deprecated tags exist" on a repository with no tags** — two checks returned
  "healthy" using the value their caller read as "found".
- **The remote-tag cache was never cleared** (its glob was quoted, so it never
  matched), and a failed network fetch was cached as an authoritative empty
  result for five minutes.
- **Interrupted syncs orphaned `temp-rebase-*` / `temp-propagate-*` branches**,
  which then made the *next* sync fail outright.
- **The RC lock protected nothing**: a check-then-create race, released before
  the tag it was guarding was created, while the correct atomic implementation
  sat unused.
- **Global hooks reported errors in unrelated repositories** — seven `[ERROR]`
  lines on every commit in any project that had not opted in.
- **Color was decided by whether stdout is a terminal**, while all logs go to
  stderr; piping either stream produced the wrong result.
- `push-all` pushed each branch **twice** and read `grep`'s exit status instead
  of git's.
- User-configurable tag prefixes and suffixes were interpolated into regular
  expressions unescaped, so any value containing `.`, `+` or `[` matched wrongly.
- Two files were missing their executable bit, so running from a clone failed
  with `Permission denied`.

**Release tooling**

- **`build.sh` never checked its own output.** It now unpacks the finished
  tarball, confirms the required members and executable bits survived, and runs
  the packaged binary — which is how the missing `--version` flag was found.
  The archive also ships `LICENSE` and `CHANGELOG.md`.
- **`build.sh` claimed to sync `install.sh` and did not.** Its `sed` keyed off a
  trailing comment the file no longer carries, so it matched nothing while
  printing `✓ Synced`. Replaced with a check that fails on a real mismatch
  rather than a build step that rewrites tracked source.
- **`bump-version.sh` ran its checks after publishing.** It edited, built,
  tested, `git add -A`'d, committed and pushed before ever asking whether the
  tag already existed. Preflight now runs first: clean tree, tag not already
  present locally or on `origin`, version actually newer, and an explicit
  confirmation of the branch being released from.
- **`bump-version.sh` committed unrelated work.** `git add -A` swept the whole
  tree into a commit labelled as a version bump; it now stages only the files it
  changed. The commit message is `chore: Release vX.Y.Z` rather than `wip:`, and
  the tag is annotated.
- **A released changelog still said "Unreleased".** `bump-version.sh` now dates
  the `[Unreleased]` heading as part of the bump.

### Added

- **`git trident doctor`** — checks environment, installation, configuration,
  repository and hooks in dependency order, stopping once an upstream layer is
  broken instead of reporting downstream symptoms. Detects orphaned sync
  branches, an interrupted merge, and stale locks.
- **`git trident abort`** — unwinds a partially-completed release or hotfix.
  Removes only **local, unpushed** refs; anything already on the remote is
  reported and left alone.
- **`git trident config validate`** — checks a configuration without running a
  workflow operation. Safe in CI.
- **`--dry-run`, globally** — on every mutating command. Release and hotfix flows
  print the exact sequence they would perform and stop before their first write.
  Verified across all thirteen commands: no branch, tag, working-tree file or
  remote ref changes. (`push-all --dry-run` does fetch — its report is computed
  against remote-tracking refs, and one built on stale refs would be
  confidently wrong — so it refreshes git's cache of the remote and nothing
  else.)
- **`--json`** — `git trident status --json` emits machine-readable status on
  stdout with logs on stderr.
- **`--yes` / `--non-interactive`** — never prompt. Deliberately does *not*
  silence the merge-conflict prompt, which asks about work only a human can have
  done.
- **`--no-color`**, plus `NO_COLOR` and `GT_COLOR=never|always|auto`.
- **`--version` / `-V`** — prints `git-trident <version>` on stdout and works
  outside a repository. Only the `version` *subcommand* was recognised before,
  so the flag form fell through to the repository gate and answered the most
  universal flag in any CLI with "❌ Not inside a Git repository".
- **`LICENSE`** (MIT) — the README has always linked to it; it was never
  committed, and it is now shipped inside the release tarball as the licence
  terms require.
- **Shell completions** for bash and zsh, completing versions and platforms read
  from the repository.
- **`git trident cleanup prune temp`** — removes orphaned sync branches.
- **`CONFIG_SCHEMA_VERSION`** — so a future key change is a visible warning.

### Changed

- Configuration is **parsed rather than executed**. A committed project config is
  no longer a script that runs on every teammate's machine, and settings no
  longer leak into the environment of child processes. `CONFIG_PARSER=legacy`
  restores the old behavior for one minor version.
- **Bash 3.2 is the supported floor** — macOS's system Bash. `brew install bash`
  is no longer a prerequisite.
- `verify-sync --report` writes to `.git-trident-reports/` instead of `.git/`.
- Verification helpers that report a *finding* are named `has_*`, not `check_*`.
- Ten colliding function names across libraries were given module prefixes.
- Git failures now show git's actual error instead of `✗ Failed: <step>`.
- **CI and release are one workflow.** As two files the release path ran a
  *weaker* gate than pull requests did — Ubuntu only, while macOS is the
  Bash 3.2 compatibility floor, so the platform most likely to break was the one
  never tested before publishing. The release job now needs the full matrix.
  shellcheck is installed on both runners, so `test_shellcheck.sh` stops
  skipping itself; the version check runs before the build instead of after it;
  `grep -oP` is gone (PCRE is absent from BSD grep); and the workflow declares
  `permissions: contents: read` with `concurrency` that never cancels a tag.

### Removed

- The incomplete changelog-delivery feature and its three configuration keys.
  The implementation was commented out behind an unconditional early return and
  the keys had no effect.
- 20 functions that were defined and never called, and 13 variables assigned but
  never read.

### Documentation

- README, QUICK_START and DETAILED_INSTRUCTIONS documented branch prefixes that
  the tool never used (`release/staging/` vs the actual `release/stg/`).
- CONTRIBUTING.md required "Bash 4.0+" and claimed associative arrays were
  "heavily utilized" — neither was true. Replaced with the real floor and a
  Bash 3.2 cookbook.
- The help text told users to copy `~/.git-trident-global-config`, a file that
  never exists, into their project config — which would have placed global-only
  keys in a tier that ignores them.

### Testing

Expanded from 10 suites to 22, and from unit-level string checks to end-to-end
runs against real repositories.

|                   | Before | After |
|-------------------|--------|-------|
| Suites            | 10     | 23    |
| Assertions        | 147    | 465   |
| End-to-end suites | 0      | 8     |
| Static gates      | 0      | 5     |

New guards fail the build rather than relying on review: Bash 4+ constructs,
CRLF line endings, git-index executable bits, shellcheck findings, duplicate
library symbols, configuration crossing a process boundary, the `--dry-run`
no-mutation invariant, and documentation coverage — every dispatcher command
must appear in both the main help and the README, and every global flag must be
documented.

The suite now runs under the **platform's own bash** and warns loudly when that
is not 3.2, so a green run on a newer shell is never mistaken for proof that
macOS works.

---

## [0.1.1] — 2026-09

Initial public release.
