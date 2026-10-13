# 🤝 Contributing to Git Trident

Thank you for your interest in contributing to Git Trident! This document provides instructions for setting up your
development environment, adding new subcommands, writing and running tests, and releasing new versions.

---

## 🛠️ Development Setup

### Prerequisites

To run and develop Git Trident, your local machine needs:

1. **Bash 3.2+** — no `brew install bash` required.

   macOS ships Bash **3.2.57** at `/bin/bash` and it cannot be replaced, so 3.2 is the
   floor for everything in `bin/`, `lib/` and `hooks/`, and for `install.sh`. The whole
   test suite runs on it.

   | Platform           | `/bin/bash`                          |
   |--------------------|--------------------------------------|
   | macOS              | 3.2.57 — **the compatibility floor** |
   | Linux              | 4.x / 5.x                            |
   | Windows (Git Bash) | 4.4 / 5.x (MSYS2)                    |

   A Bash 4+ construct passes on a developer's machine and fails on every Mac, so this
   is enforced rather than documented: `tests/test_bash32_compat.sh` rejects Bash 4.0–4.3
   constructs, and `tests/run_all.sh` runs the suite under the *platform's own* bash,
   warning loudly when that is not 3.2.

   See [Bash 3.2 cookbook](#-bash-32-cookbook) below for the idioms to use instead.

2. **Utilities**: `git`, `grep`, `sed`, `awk`, `curl`, `date`, `tar`.
3. **Optional**: `shellcheck` — enables `tests/test_shellcheck.sh`. The suite skips that
   gate when it is absent, so it is not required to contribute.

### Local Installation for Development

1. Clone the repository to your local machine.
2. Run the installer script locally to link your development path:
   ```bash
   bash install.sh
   ```
3. To test changes directly without reinstalling, you can run the files in the workspace's `bin/` directory directly by
   adding the project's absolute path to your `PATH` variable:
   ```bash
   export PATH="/path/to/Git-Trident/bin:$PATH"
   ```

---

## 🔌 Adding New Commands

Git Trident utilizes a dispatcher pattern in `bin/git-trident` to route subcommands.

### Step 1: Add Route to the Dispatcher

Open [bin/git-trident](bin/git-trident) and find the routing block in the
`main` function. Add your new subcommand to the `case` statement:

```bash
case "$cmd" in
    # ... existing commands ...
    my-command)
        shift
        # Dispatch to your new script
        exec "$SCRIPT_DIR/git-trident-my-command" "$@"
        ;;
```

### Step 2: Create Subcommand Script

Create the handler script inside the `bin/` folder (e.g. `bin/git-trident-my-command`).

- The script should source `lib/git-trident-common.sh` for config loading and utility functions.
- If it doesn't require Git repository initialization, pass `--no-init` when sourcing or when registering in the
  dispatcher.

Example template:

```bash
#!/usr/bin/env bash
# SCRIPT_DIR setup...
source "$SCRIPT_DIR/../lib/git-trident-common.sh"
# Implement command logic here...
```

Remember to make the script executable: `chmod +x bin/git-trident-my-command`.

### Step 3: Document the Command

Update the help manuals
inside [lib/git-trident-help.sh](lib/git-trident-help.sh):

1. Add descriptions to the general helper manuals (e.g. `show_main_help` or `show_utility_main_help`).
2. Add a command-specific help manual if needed (e.g. `show_my_command_help`).

---

## 📐 Code Conventions

### 🐚 Bash 3.2 cookbook

**Why this is a hard rule.** macOS ships Bash 3.2.57 at `/bin/bash`, it cannot be
replaced, and it is what `curl … | bash` runs on a Mac. A Bash 4+ construct passes on
the author's machine and fails for every macOS user — so it is enforced by the test
suite rather than left to review:

- `tests/test_bash32_compat.sh` rejects Bash 4.0–4.3 constructs, `set -u`, CRLF line
  endings and wrong git-index exec bits.
- `tests/run_all.sh` runs the suite under the **platform's own** bash and warns loudly
  when that is not 3.2, so a green run on Bash 5 is never mistaken for proof.

The whole runtime is 3.2-clean. For a long time the installer alone needed Bash 4 — for
a single associative array used as a colour map — and that one construct broke the
documented install path entirely, because under `curl … | bash` the re-exec tried to run
the `bash` binary as a shell script.

Left column breaks on macOS. Right column works on every supported platform.

| Instead of (Bash 4+)                 | Use (Bash 3.2-safe)                                                                               |
|--------------------------------------|---------------------------------------------------------------------------------------------------|
| `declare -A m; m[k]=v`               | parallel arrays, or a `k=v` string split with `case`/`IFS` — as `parse_commit_prefix_config` does |
| `mapfile -t arr < <(cmd)`            | `IFS=$'\n' read -d '' -ra arr <<< "$(cmd)"`                                                       |
| `"${arr[@]}"` *(array may be empty)* | `${arr[@]+"${arr[@]}"}`                                                                           |
| `set -u`                             | `"${VAR:-}"` defaults + shellcheck **SC2154**                                                     |
| `local -n ref=$name`                 | `eval "$name=…"` *(the existing idiom)*                                                           |
| `${s^^}` / `${s,,}`                  | `tr '[:lower:]' '[:upper:]'` / `awk '{print toupper($0)}'`                                        |
| `[[ -v VAR ]]`                       | `[ -n "${VAR+x}" ]`                                                                               |
| `;;&` case fall-through              | restructure, or repeat the branch                                                                 |
| `${arr[-1]}`                         | `"${arr[${#arr[@]}-1]}"`                                                                          |
| `&>> file`                           | `>> file 2>&1`                                                                                    |

**`set -u` is banned in `bin/`, `lib/` and `hooks/`** and the compatibility gate fails if
it reappears. On Bash 3.2 expanding an *empty* array under `set -u` is fatal, while on
4.4+ it expands to nothing:

```
bash 3.2.57 :  set -u; a=(); printf "%s" "${a[@]}"   ->  a[@]: unbound variable
bash 5.3.20 :  set -u; a=(); printf "%s" "${a[@]}"   ->  (nothing, exit 0)
```

There are 80+ such expansions, so `set -u` would break macOS only. `install.sh`,
`build.sh` and `scripts/` may use it — they are entry points, not sourced libraries —
but must expand possibly-empty arrays with `${arr[@]+"${arr[@]}"}`.

**Before every commit:**

```bash
/bin/bash --version | head -1     # must say 3.2.57 on macOS
/bin/bash tests/run_all.sh        # the floor, not your shell
```

### Return-value convention

| Prefix                              | `return 0` means |
|-------------------------------------|------------------|
| `check_*`, `validate_*`, `verify_*` | healthy / valid  |
| `has_*`, `is_*`, `*_exists`         | true             |

Mixing these are what made a repository with no tags report "Deprecated tags exist".

### Output streams

Logs go to **stderr** (`log_info`, `log_warn`, `log_error`, `log_step`, `log_empty`).
Only values a caller consumes go to **stdout**. Printing a table to stdout in the middle
of a stderr log stream makes either redirection useless.

### Returning multiple values

Set named globals (`GT_ARG_*`, `GT_OUT_*`) — never `echo "$a $b"` for the caller to split
with `read`. Empty fields collapse under the default IFS and shift every later field, and
`exit` inside a command substitution terminates only the subshell.

---

## 🧪 Testing Strategy

Automated test suites are located in the `tests/` directory.

### Running All Tests

Execute the test runner script from the root of the workspace:

```bash
bash tests/run_all.sh
```

This runs all tests sequentially. The tests verify features such as:

- Directory safety checks
- Validation logic
- Hook operations
- Tag increments and branch merging

### Adding New Test Cases

1. Create a test script in the `tests/` directory following the name convention `test_*.sh`.
2. Follow the testing conventions described
   in [SCRIPTS_TEST_CASES.md](SCRIPTS_TEST_CASES.md).
3. Update [tests/run_all.sh](tests/run_all.sh) to include your new test
   file.

---

## 🚀 Releasing a New Version

Git Trident versioning is automated. Do not manually edit the version number in source files.

### Automated Version Bumping

Run the release tool from the root of the repository to bump version configurations and update assertions:

```bash
# Dry run: updates files locally but does not push
./scripts/bump-version.sh 1.0.3

# Full release: bumps files, commits, tags, and pushes to remote
./scripts/bump-version.sh 1.0.3 --release
```

### CI/CD Pipeline

One workflow, `.github/workflows/ci.yml`, handles both. They were separate files
until the release path was found to be running a *weaker* gate than pull requests
did — tests on Ubuntu only, while macOS is the compatibility floor.

| Job | Runs on | Does |
|-----------------|--------------------------------------------|---------------------------------------------------------------|
| `test` | every push to `main`/`develop`, every PR, and every `v*` tag | Full suite on Ubuntu **and** macOS, with shellcheck installed so `test_shellcheck.sh` actually executes |
| `version-sync` | the same | Constants vs. test assertions, plus the tag itself on a tag build — before anything is built |
| `release` | `v*` tags only (`if: startsWith(github.ref, 'refs/tags/v')`) | Builds the tarball, checks it reports the tag's version, publishes the GitHub Release |

`release` needs both other jobs, so a tag that fails on macOS never publishes.
