# 🤝 Contributing to Git Trident

Thank you for your interest in contributing to Git Trident! This document provides instructions for setting up your
development environment, adding new subcommands, writing and running tests, and releasing new versions.

---

## 🛠️ Development Setup

### Prerequisites

To run and develop Git Trident, your local machine needs:

1. **Bash 4.0+**: Modern Bash features (such as associative arrays) are heavily utilized.
    - *macOS*: Install via Homebrew: `brew install bash`.
    - *Linux/Windows Git Bash*: Bash 4.0+ is typically the system default.
2. **Utilities**: `git`, `grep`, `sed`, `awk`, `curl`, `date`, `tar`.

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

