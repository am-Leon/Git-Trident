# 🔱 Git Trident — Remediation & Architecture Plan

> Scope: code defects, dead code, library architecture and infrastructure.
> Out of scope (tracked separately): CI/CD workflow changes, DevOps build-trigger design.

Baseline: `v0.1.1`, commit `8026244`. All defects below were reproduced in throwaway
sandbox repositories, not inferred from reading. Reproduction steps are given per task.

---

## 0. Compatibility invariant — read before touching any file

> **Every change in this plan must run on Bash 3.2.57.**
> That is the version macOS ships at `/bin/bash`, it cannot be replaced, and it is what
> `curl … | bash` executes on a Mac. Treat it as a hard target, not a nice-to-have.

### 0.1 The runtime is already 3.2-clean — the installer is not

This was measured, not assumed. A scan of `bin/ lib/ hooks/ tests/ scripts/ install.sh build.sh`
for every Bash 4.0–4.3 construct returned:

| Construct | Introduced | Occurrences |
|---|---|---|
| `declare -A` / `local -A` | 4.0 | **1 — `install.sh:61`** |
| `mapfile` / `readarray` | 4.0 | none |
| `;;&` case fall-through | 4.0 | none |
| `coproc`, `\|&`, `&>>` | 4.0 | none |
| `${v^^}` / `${v,,}` | 4.0 | none |
| `globstar` | 4.0 | none |
| `declare -g`, `[[ -v ]]` | 4.2 | none |
| `local -n` nameref | 4.3 | none |
| negative array index, `wait -n` | 4.3 | none |

Confirmed by execution, not inspection:

- `/bin/bash tests/run_all.sh` → **10/10 suites pass on 3.2.57**
- A complete lifecycle — `staging release start → finish → hotfix start → finish →
  production release start → finish` — driven entirely by `/bin/bash` 3.2 produces the
  correct tag sequence (`staging/1.0.0-rc-01`, `-rc-02`, `production/1.0.0`).

**So `bin/`, `lib/` and `hooks/` do not require Bash 4 and never did.** The belief that
they do comes from the installer, which is the only file that needs it — and which
aborts loudly telling users to `brew install bash`. That single `declare -A` is a
**cosmetic colour map**. It is the entire reason Bash 4 appears to be a requirement.

### 0.2 The real cost: the documented install command is broken on macOS

`install.sh:7–17` re-execs into a Bash 4+ binary when it detects 3.2:

```bash
exec "/opt/homebrew/bin/bash" "$0" "$@"
```

Under `curl -fsSL … | bash` the script arrives on **stdin**, so `$0` is the interpreter
path `/bin/bash`, not a file. The exec therefore becomes `bash5 /bin/bash` — asking Bash
to run the *binary* as a script:

```
$ cat install.sh | /bin/bash          # exactly what `curl … | bash` does
/bin/bash: /bin/bash: cannot execute binary file
```

**This fails even when brew's bash is installed** (verified on a machine with
`/opt/homebrew/bin/bash` 5.3.20 present). The README's primary install path cannot work
on any Mac. The only route through is cloning and running `bash install.sh` locally,
where `$0` is a real path — which matches the workaround arrived at in practice.

Removing the `declare -A` and deleting the shim fixes it outright. Verified: the patched
installer completes end-to-end under piped `/bin/bash` 3.2 with **no brew bash anywhere
in the picture** (see **P0-6**).

### 0.3 Rules this imposes on the rest of the plan

Two proposals in the first draft of this document would themselves have broken 3.2.
They are corrected in place, and the rules below are binding on all future work:

| Rule | Why |
|---|---|
| **No `set -u`** (see **A9**, revised) | On 3.2, `"${arr[@]}"` on an *empty* array raises `unbound variable`; on 4.4+ it expands to nothing. 84 such sites exist. A `set -u` that passes on the author's Bash 5 would fail on users' Macs. |
| Expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}` | The only form correct on both. |
| No associative arrays | Use parallel arrays, or `KEY=VALUE` strings parsed with `case`/`grep` — the pattern `lib/git-trident-hooks.sh` already uses for `COMMIT_PREFIXES`. |
| No `local -n` namerefs | 4.3+. The existing `eval "$errors_ref_name+=(…)"` idiom in `common.sh` is ugly but 3.2-correct — do not "modernise" it into a nameref. |
| No `mapfile`/`readarray` | Use `IFS=$'\n' read -d '' -ra arr <<< "$s"` — verified identical on 3.2 and 5.3. |
| No `${v^^}` / `${v,,}` | Use `tr` or `awk`, as `changelog-generation:343` already does. |
| `printf -v "$dynamic_name"` **is** allowed | 3.1+. Verified working on 3.2. Relied on by **A2**. |

Enforcement is **T0.4** and **T0.5** — a banned-construct grep plus a mandatory
3.2 test run. Documentation alone is not sufficient; this must fail the build.

---

## 1. Summary

| Severity                | Count | Theme                                                              |
|-------------------------|-------|--------------------------------------------------------------------|
| **P0 — Broken feature** | 6     | A documented command does nothing, or fails/corrupts in normal use |
| **P1 — High**           | 7     | Works, but wrong result or blocks a primary use case               |
| **P2 — Medium**         | 8     | Correctness/robustness, narrower blast radius                      |
| **P3 — Hygiene**        | 7     | Dead code, docs drift, file hygiene                                |
| **A — Architecture**    | 12    | Structural changes that remove whole bug classes                   |
| **E — Enhancement**     | 11    | New capability                                                     |

Five numbers that frame the work:

- **1** Bash 4+ construct in the whole codebase (`install.sh:61`) — and it breaks the
  documented install command on every Mac (**§0**, **P0-6**)
- **162** error-suppression sites (`2>/dev/null` ×117, `>/dev/null 2>&1` ×45)
- **84** array expansions that would break under `set -u` on Bash 3.2 (**A9**)
- **13** functions defined and never called (~330 lines)
- **0** end-to-end tests covering `release finish`, `hotfix finish` or `sync-tags`

The last one matters most: **every P0 below was reproducible in under ten lines**
against a temp repo. They survived because the test suite only exercises pure
string functions. Fixing that is Phase 0, and it comes before any bug fix.

---

## 2. Sequencing

```
Phase 0  Safety net          ── fixtures + shellcheck + BASH 3.2 GATES  (blocks everything)
   │
Phase 1  P0 defects          ── 6 broken features  (P0-6 first: unblocks installation)
   │
Phase 2  P1 defects          ── 5 high-impact correctness bugs
   │
Phase 3  Architecture A1–A7  ── remove the bug classes
   │                             (P2 items fall out of these for free)
Phase 4  P2 / P3 remainder   ── what A1–A7 did not absorb
   │
Phase 5  Enhancements        ── A8–A12 + E1–E11
```

**Why Phase 0 first.** Two reasons now. Several Phase 1 fixes touch merge and push
paths, and without an integration harness there is no way to prove a fix works without
hand-driving a repo each time. More importantly, **T0.4/T0.5 must land before any other
code change** — they are what stop a Bash-4 construct from being reintroduced while the
rest of this plan is being implemented. A compatibility rule that is only written down
is a rule that gets broken by the third pull request.

**Why P0-6 leads Phase 1.** It is the smallest fix in the plan and the only one blocking
installation for new macOS users. Everything else is invisible to someone who cannot
install the tool.

**Why architecture before the P2 tail.** A1 (root resolution) alone closes **P1-1,
P1-6, P2-7, P3-7** plus four further P2 items. A4 (no echo-returns) closes three.
Fixing them individually is
wasted effort.

---

## 3. Phase 0 — Safety net

### T0.1 · Integration test harness `tests/lib/repo_fixture.sh` — **L**

Everything in Phase 1 depends on this.

```bash
gt_fixture_new_repo        # temp repo + bare remote + project config + HOME sandbox
gt_fixture_platform_repo   # same, PLATFORM_SPECIFIC_TAGS=true, shared/android/ios
gt_fixture_commit  <msg>
gt_fixture_tag     <tag> [ref]
gt_fixture_run     <args…>  # runs bin/git-trident, captures stdout/stderr/exit separately
gt_fixture_destroy
```

Requirements:

- Isolated `HOME` so the global config and `core.hooksPath` cannot leak in
  (this is exactly how the Phase 1 hook-noise defect was found).
- `REQUIRE_CONFIRMATION=false`, `VALIDATE_REMOTE_CONNECTIVITY=false` by default,
  with an opt-in to re-enable for prompt tests.
- Assert on **exit code, stdout and stderr independently** — the current framework
  only checks strings, which is why silent `command not found` went unnoticed.

### T0.2 · Integration suites — **L**

| Suite                         | Covers                                                                                    |
|-------------------------------|-------------------------------------------------------------------------------------------|
| `test_e2e_staging_flow.sh`    | release start → finish → hotfix start → finish; tag sequence, branch merges, develop sync |
| `test_e2e_production_flow.sh` | promote RC → finish → tags → sync back to staging+develop                                 |
| `test_e2e_hotfix_flow.sh`     | production hotfix start/finish, auto patch bump, downstream sync                          |
| `test_e2e_sync_tags.sh`       | both propagation directions, legacy + platform mode, resume mode                          |
| `test_e2e_push_all.sh`        | zero-tag case, platform filter, cache behaviour                                           |
| `test_e2e_cwd.sh`             | **every command from a repo subdirectory**                                                |

### T0.3 · `shellcheck` gate — **S**

Add `tests/test_shellcheck.sh` (skip with a notice when the binary is absent so local
runs do not break). Start at `-S error`, ratchet to `-S warning` once Phase 2 lands.

Shellcheck statically catches **P0-2, P0-4, P1-3** and most of the dead code. It is the
cheapest item in this plan and the highest yield.

### T0.4 · Banned-construct gate `tests/test_bash32_compat.sh` — **S** · _enforces §0.3_

A static guard that **fails the suite** when a Bash 4+ construct appears anywhere in
`bin/ lib/ hooks/ tests/ scripts/`. After **P0-6**, `install.sh` is included too — there
is then no exempt file.

```bash
BANNED=(
  'declare[[:space:]]+-[A-Za-z]*A|local[[:space:]]+-[A-Za-z]*A[[:space:]]'  # 4.0 assoc arrays
  '\b(mapfile|readarray)\b'                                                 # 4.0
  ';;&'                                                                     # 4.0
  '\bcoproc\b|\|&|&>>'                                                      # 4.0
  '\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,|\^|,)[^}]*\}'                         # 4.0 case mod
  'shopt[[:space:]]+-s[[:space:]]+globstar'                                 # 4.0
  'declare[[:space:]]+-[A-Za-z]*g'                                          # 4.2
  '\[\[[^]]*-v[[:space:]]'                                                  # 4.2
  '(local|declare)[[:space:]]+-[A-Za-z]*n[[:space:]]'                       # 4.3 nameref
  'wait[[:space:]]+-n'                                                      # 4.3
)
```

Also guard the `set -u` trap, since that is the subtle one a reviewer will miss:

```bash
# fail if 'set -u' is introduced into the runtime (see A9)
grep -rnE '^[[:space:]]*set[[:space:]]+[-+][a-zA-Z]*u' bin lib hooks \
    && fail "set -u is unsafe on Bash 3.2 — see §0.3"
```

**Scope note.** `bin/`, `lib/` and `hooks/` contain **no** `set -u` today, so this gate
starts green. Three standalone scripts do use it — `install.sh:20`, `build.sh:6`,
`scripts/bump-version.sh:14` — and they are deliberately **out of scope** for the ban:
they are entry points, not sourced libraries, and `set -u` is valuable there. The
condition attached is that each must be audited for empty-array expansion, because
`${a[*]}` and `"${a[@]}"` are fatal on 3.2 under `set -u` while `${#a[@]}` is not:

```
bash 3.2.57 :  set -u; a=(); echo "${#a[@]}"   →  0        ✅
bash 3.2.57 :  set -u; a=(); echo "${a[*]}"    →  unbound variable   ❌
bash 3.2.57 :  set -u; a=(); echo "${a[@]}"    →  unbound variable   ❌
```

This matters most for `install.sh`, which **P0-6** moves from Bash 4 to Bash 3.2 while
keeping its `set -u` — see the audit table there.

### T0.5 · Run the whole suite under real Bash 3.2 — **S** · _the gate that actually matters_

A grep cannot catch everything (`set -u` + empty array is a runtime failure, not a
syntax one). The suite must **execute** under 3.2.

```bash
# tests/run_all.sh — pick the oldest available bash unless overridden
GT_TEST_BASH="${GT_TEST_BASH:-$( [ -x /bin/bash ] && echo /bin/bash || command -v bash )}"
"$GT_TEST_BASH" --version | head -1          # always print it; silent assumptions caused this
```

- Locally on macOS this is `/bin/bash` 3.2.57 by default — developers test the floor
  without having to think about it.
- On Linux (where `/bin/bash` is 5.x) set `GT_TEST_BASH` to a 3.2 build, or accept that
  the macOS developer machine is the real gate.
- Every integration suite from **T0.2** must invoke `bin/git-trident` through
  `$GT_TEST_BASH`, not via the shebang.

### T0.6 · Correct the Bash documentation — **S**

`CONTRIBUTING.md` currently states Bash 4.0+ is required and that "associative arrays
are heavily utilized". Both are false for `bin/`/`lib/`/`hooks/`, and after **P0-6**
they are false for `install.sh` too. Replace with: **Bash 3.2+ (macOS stock) — no
`brew install bash` required**, and link §0.3's rules table.

---

## 4. Phase 1 — P0 defects

### P0-1 · `git trident version update` always 404s — **S**

**File** [`bin/git-trident-version:527`](../bin/git-trident-version#L527)

`latest_tag` is built with `sed 's/^v//'`, stripping the `v`. It is then exported as
`INSTALL_VERSION`, which [`install.sh:143`](../install.sh#L143) interpolates directly
into the asset URL. Releases are tagged `v0.1.1`, so the URL never resolves.

```
.../releases/download/0.1.1/git-trident.tar.gz   →  HTTP 404
.../releases/download/v0.1.1/git-trident.tar.gz  →  HTTP 200
```

**Fix.** Keep the raw tag for the URL and derive a display version separately:

```bash
latest_tag=$(printf '%s' "$response" | awk -F'"' '/"tag_name":/ {print $4; exit}')  # v0.1.1
latest_version="${latest_tag#v}"                                                     # 0.1.1
# compare on $latest_version, pass INSTALL_VERSION="$latest_tag"
```

Also replace the `==` equality check with a real comparison via `is_version_greater`,
so a local build ahead of the latest release is not offered a downgrade.

**Verify.** Unit-test the URL builder; assert the constructed URL contains `/v`.

---

### P0-2 · `CONFLICT_STRATEGY=prefer-ours|prefer-theirs` is inoperative — **S**

**File** [`lib/git-trident-common.sh:956–987`](../lib/git-trident-common.sh#L956)

`merge_strategy_args="-X ours"` is appended as a **single** argv element:

```
git merge --no-ff "-X ours" <src> -m <msg>
  → fatal: unknown strategy option: -X ours
```

Compounding it, the merge at line 980 is `2>/dev/null`, so the fatal error is swallowed
and the code falls into `handle_merge_conflict` — the user is told there is a merge
conflict and prompted to resolve conflicts **that do not exist**.

**Fix.** Use an array, and stop hiding git's stderr:

```bash
local -a strategy_args=()
case "${CONFLICT_STRATEGY:-interactive}" in
    prefer-ours)   strategy_args=(-X ours)   ;;
    prefer-theirs) strategy_args=(-X theirs) ;;
esac

local merge_output rc
# NOTE: ${a[@]+"${a[@]}"} — not "${a[@]}". On Bash 3.2 the plain form raises
# 'unbound variable' for an empty array once set -u is on. See §0.3.
merge_output=$(git merge --no-ff ${strategy_args[@]+"${strategy_args[@]}"} \
                         "$source_ref" -m "$msg" 2>&1); rc=$?
if [ $rc -eq 0 ]; then return 0; fi
if has_unresolved_conflicts; then
    handle_merge_conflict "$target_branch" "$source_ref" "$context"; return $?
fi
log_error "Merge failed (not a conflict): $merge_output"   # ← surface the real error
return 1
```

> **Bash 3.2 note.** `interactive` (the default) leaves `strategy_args` empty, so this
> is the common path, not an edge case. The first draft of this plan used the plain
> `"${strategy_args[@]}"` form — correct on Bash 5, a latent failure on macOS.

The conflict/non-conflict distinction is the important half: today **any** merge
failure is reported as a conflict.

**Verify.** Integration test with `CONFLICT_STRATEGY=prefer-ours` on a genuinely
conflicting merge; assert the merge succeeds and the conflict prompt never appears.

---

### P0-3 · `verify-sync --env <branch>` — flag ignored, then crashes — **M**

**File** [`bin/git-trident-verify-sync:98`, `:811–824`, `:1276`](../bin/git-trident-verify-sync#L98)

Two independent defects stacked:

**(a) The flag is silently discarded.** `parse_arguments` returns five space-joined
fields; when `platform_filter` is empty the double space collapses under `read`'s
default IFS and every field shifts left. `--env develop` therefore sets
`PLATFORMS=develop` and runs the comprehensive check instead. Observed: no error, exit 0.

**(b) The code path calls eight functions that do not exist.** Force all five fields
non-empty and:

```
line 823: check_unmerged_features: command not found
line 824: check_pending_releases: command not found
```

Missing: `check_production_tags`, `check_production_sync_status`,
`validate_production_tags`, `check_staging_tags`, `check_rc_sequence`,
`check_hotfix_propagation_status`, `check_unmerged_features`, `check_pending_releases`.
The script still exits 0.

**Fix.**

1. Replace echo-returns with explicit globals (see **A4**) — removes (a) permanently:
   ```bash
   GT_ARG_MODE= GT_ARG_REPORT= GT_ARG_DEPRECATED= GT_ARG_PLATFORM= GT_ARG_ENV=
   parse_arguments "$@"   # sets them directly; no echo, no read
   ```
2. For (b), choose one — **this is a product decision**:
   - **Option A (recommended):** cut `--env` to what exists today
     (`show_branch_info` + `check_branch_relationships` + `check_custom_branch_tags`),
     and remove the eight calls. Ships immediately, no behavior promised that is not delivered.
   - **Option B:** implement the eight checks. They are each a thin wrapper over
     functions that already exist (`get_all_staging_tags`, `validate_rc_sequence_for_platform`,
     `detect_staging_hotfix_impact`, `check_staging_releases_need_rebase`). ~150 lines, and
     `--env` becomes the most useful diagnostic in the tool.
3. Either way: make `check_environment_specific` propagate a non-zero exit on failure.

**Verify.** `test_e2e_verify_sync.sh` asserting `--env develop` *without* `-p` reaches
the branch-specific path, and that stderr contains no `command not found`.

---

### P0-4 · `push-all` counts zero tags as one; fails hard in platform mode — **S**

**File** [`bin/git-trident-push-all:653`, `:824`, `:939`](../bin/git-trident-push-all#L653)

`echo "" | wc -l` is `1`. With no un-pushed tags the summary reports phantom work, and
in platform mode the per-tag loop iterates once over an empty string:

```
[INFO] Pushing 1 tag(s) for platform android...
[ERROR] ✗
[ERROR] Failed to push 1 tags:
EXIT CODE = 1
```

This is the exact path `auto_push_if_enabled` takes, so `AUTO_PUSH_ON_FINISH=true` in
platform mode reports failure whenever the tags are already pushed (re-runs, resumes,
manual pushes).

**Fix.** A counting helper used at all three sites:

```bash
gt_count_lines() { [ -z "$1" ] && { echo 0; return; }; printf '%s\n' "$1" | grep -c .; }
```

and guard the loop with `[ -n "$unpushed_tags" ] || return 0` before the `while read`.

**Verify.** `test_e2e_push_all.sh`: branch changes + zero tags, legacy **and** platform
mode, assert exit 0 and no `Failed to push`.

---

### P0-5 · Global hooks spam every non-Trident repository — **S**

**File** [`lib/git-trident-hooks.sh:21`](../lib/git-trident-hooks.sh#L21)

With `core.hooksPath` installed globally (the documented setup), `load_project_config || true`
runs in **every** repository on the machine. In any repo without a trident config it prints
seven red `[ERROR]` lines on every single commit, before correctly allowing the commit:

```
$ git commit -m "chore: whatever"
[ERROR] ❌ No project configuration file found.
[ERROR]    Git Trident requires a project config to operate in this repository.
[ERROR] 💡 Run the following command to initialize your project config:
[ERROR]      git trident config init
...
[main 54f02fd] chore: whatever          ← commit succeeds
```

Reproduced on this machine, which has `core.hooksPath = ~/.git-trident/hooks`.

**Fix.** One line — hooks must never diagnose a repo that is not opted in:

```bash
SUPPRESS_CONFIG_ERRORS=true load_project_config || true
```

Then confirm `check_hooks_enabled` returns non-zero when no project config loaded, so
the hook is a clean no-op rather than a half-configured validator.

**Verify.** Fixture: global `core.hooksPath` set, plain repo with no config → assert
commit succeeds **and stderr is empty**.

---

### P0-6 · `curl … | bash` cannot install on macOS — **S** · _highest user impact_

**File** [`install.sh:6–17`, `:61`, `:66–69`, `:316`](../install.sh#L6)

The README's primary — and for most users only — install path:

```bash
curl -fsSL https://raw.githubusercontent.com/am-Leon/Git-Trident/main/install.sh | bash
```

On macOS `bash` is `/bin/bash` 3.2.57, so the Bash-4 shim fires. Because the script came
from **stdin**, `$0` is the interpreter path rather than a file, and the exec degenerates
into "run the bash binary as a shell script":

```
$ cat install.sh | /bin/bash
/bin/bash: /bin/bash: cannot execute binary file
```

Reproduced on a machine **with** `/opt/homebrew/bin/bash` 5.3.20 installed — brew does
not rescue this path. Nothing is installed; the exit status is not even propagated.

The whole Bash-4 requirement exists to support one decorative associative array:

```bash
declare -A UI=( [RED]='\033[0;31m' [GREEN]='\033[0;32m' … )   # install.sh:61
log_info() { echo -e "${UI[GREEN]}[INFO]${UI[NC]} $1"; }       # 5 usages total
```

**Fix** — two edits, no behaviour change:

```bash
# 1. install.sh:61 — plain scalars instead of an associative array
UI_RED='\033[0;31m'; UI_GREEN='\033[0;32m'; UI_YELLOW='\033[1;33m'
UI_BLUE='\033[0;34m'; UI_NC='\033[0m'
# then ${UI[GREEN]} → ${UI_GREEN} at lines 66,67,68,69,316

# 2. install.sh:6-17 — delete the shim entirely; it is no longer needed
```

**Verified.** With exactly these two edits, `cat install.sh | /bin/bash` (3.2.57)
completes the full installation — binary in place, templates extracted, global config
written, profile updated — with no Bash 4 anywhere in the process.

**Knock-on effects:** `brew install bash` stops being a prerequisite; the dependency
check in `check_dependencies` no longer needs to special-case bash; `CONTRIBUTING.md`'s
prerequisites section shrinks (**T0.6**); and `install.sh` comes under the **T0.4** gate
with no exemption.

> ⚠️ **One thing this change alters silently.** `install.sh:20` sets `set -u`, and until
> now that ran under Bash 4+. After this fix it runs under **3.2 + `set -u`**, where
> expanding an empty array is fatal. Audited — all four sites are currently safe:
>
> | Line | Expansion | Status on 3.2 + `set -u` |
> |---|---|---|
> | 93 | `"${dependencies[@]}"` | safe — literal, never empty |
> | 99 | `${#missing_deps[@]}` | safe — `${#a[@]}` is permitted even when empty |
> | 100 | `${missing_deps[*]}` | safe — guarded by the `-ne 0` test above it |
> | 183 | `"${candidates[@]}"` | safe — assigned non-empty on every branch |
>
> It passes today, but it is one careless edit away from a macOS-only crash. Convert
> all four to `${arr[@]+"${arr[@]}"}` while making this change, and the file is
> permanently safe rather than accidentally safe.

**Verify.** Add `tests/test_install_bash32.sh`: pipe `install.sh` into `/bin/bash` with
a sandboxed `HOME` and `LOCAL_TARBALL`, assert exit 0 and that
`$HOME/.git-trident/bin/git-trident` exists. This is the single most valuable new test
in the plan — it covers the path every new user takes.

---

## 5. Phase 2 — P1 defects

### P1-1 · Trident only works from the repository root — **M**

**File** [`lib/git-trident-common.sh:176–179`](../lib/git-trident-common.sh#L176)

`./git-trident-config` is resolved against **cwd**. From `repo/sub/dir`:

```
[ERROR] ❌ No project configuration file found.
```

For the headline KMP/monorepo use case this is a significant limitation. The same
cwd-relative assumption appears in `.git/git-trident-locks`, `.git/git-trident-rc-lock`,
`.git/git-trident-remote-tags-*`, the verification report path, and the
`-f ".git/MERGE_HEAD"` test (which is also wrong in worktrees and submodules).

**Fix.** Folded into **A1b** — resolve `GT_REPO_ROOT` / `GT_GIT_DIR` once, use everywhere.

**Verify.** `test_e2e_cwd.sh` runs the full command surface from a nested directory.

---

### P1-2 · `config init` silently inverts every `true` default — **S**

**File** [`bin/git-trident-config:41`](../bin/git-trident-config#L41)

`answer="${answer:-$default}"` substitutes the literal string `true`, which then fails
`[[ "$answer" =~ ^[Yy] ]]`:

```
ENTER, default=true   →  false      ← prompt displayed [Y/n]
y,     default=true   →  true
ENTER, default=false  →  false
```

An all-defaults `config init` writes `HOOK_COMMIT_MSG_ENABLED=false` and
`REQUIRE_CAPITAL_START=false` while showing `[Y/n]` for both.

**Fix.**

```bash
_ask_bool() {
    local prompt="$1" default="${2:-false}" hint answer
    [[ "$default" == "true" ]] && hint="Y/n" || hint="y/N"
    read -rp "$(echo -e "${BLUE}?${NC} $prompt [$hint]: ")" answer
    [[ -z "$answer" ]] && { echo "$default"; return; }     # ← accept the default verbatim
    [[ "$answer" =~ ^[Yy] ]] && echo "true" || echo "false"
}
```

**Verify.** Unit test all three paths (empty / `y` / `n`) × both defaults.

---

### P1-3 · Remote tag cache is never cleared, and poisons itself — **S**

**File** [`bin/git-trident-push-all:263`, `:280–284`](../bin/git-trident-push-all#L263)

Two bugs in one function:

- `ls "$cache_pattern"` / `rm -f "$cache_pattern"` quote the glob, so neither expands.
  The non-platform cache clear is a **confirmed no-op**.
- `get_cached_remote_tags` writes the cache even when `git ls-remote` fails, caching an
  empty result for `REMOTE_TAG_CACHE_DURATION` (300 s). Every local tag then reads as un-pushed.

**Fix.**

```bash
# clear: let the shell expand, and tolerate no matches
rm -f "$GT_GIT_DIR"/git-trident-remote-tags-"$remote"*

# populate: only cache a successful fetch
local raw rc
raw=$(git ls-remote --tags "$remote" 2>/dev/null); rc=$?
if [ $rc -ne 0 ]; then
    log_warn "Could not reach $remote; skipping tag cache"
    return 1
fi
```

Also add `git trident cleanup cache` to drop it manually.

---

### P1-4 · "Deprecated tags exist" reported on a repo with no tags — **S**

**File** [`bin/git-trident-verify-sync:413`, `:464`](../bin/git-trident-verify-sync#L413)

`check_deprecated_tags_for_platform` and `..._legacy` both `return 0` to mean
*"no production tags, so no deprecation possible"*. But the caller treats `return 0`
as *"deprecated tags were found"*. A fresh repo reports:

```
[INFO] ℹ️  Deprecated tags exist (use --deprecated to see details)
```

**Fix.** `return 1` on the early exits — then adopt **A6** so this category of
inverted-boolean bug cannot recur.

---

### P1-5 · `cleanup prune` reports success even when deletion fails — **M**

**File** [`bin/git-trident-cleanup:109–130`](../bin/git-trident-cleanup#L109)

Local and remote deletions are both `>/dev/null 2>&1`, then `✓ Deleted $count ...` is
logged unconditionally. Worse, `git push --delete` batches 20 tags at a time: one tag
already absent on the remote fails the whole batch, silently, and the other 19 survive.

**Fix.** Capture status per batch, count real successes, report honestly, and
pre-filter against `git ls-remote --tags` so absent tags are never submitted.
Report `Deleted N local, M remote (K skipped — not on remote)`.

---

### P1-6 · `version update` silently abandons a custom install path — **S**

**File** [`bin/git-trident-version:599`](../bin/git-trident-version#L599)

`install.sh` supports a custom location (`bash install.sh /opt/tools`), and most of the
tool honours it correctly. The self-updater does not:

```bash
if bash "$tmp_installer"; then     # ← no path argument
```

With no argument, `install.sh:46–55` falls back to `INSTALL_DIR="$HOME/.git-trident"`.
Verified against a custom install at `…/opt/tools/.git-trident`:

```
before : custom install present, ~/.git-trident absent
after  : custom install STILL present (now stale)
         ~/.git-trident NOW EXISTS                  ← second copy
         profile PATH line REWRITTEN to ~/.git-trident/bin
```

So an update leaves two installations, repoints `PATH` at the new default, and orphans
the one the user chose. Nothing warns about it.

**Fix.** Pass the current root through, derived from the running script rather than assumed:

```bash
local current_root; current_root="$(cd "$SCRIPT_DIR/.." && pwd)"
if bash "$tmp_installer" "$current_root"; then
```

`install.sh` already normalises a path ending in `.git-trident`
([`install.sh:47–51`](../install.sh#L47)), so passing the resolved root is correct and
idempotent.

**Implement via A1a** — `GT_INSTALL_ROOT` is exactly this value, resolved through
symlinks. Add a test asserting a custom-path install updates in place and creates no
second directory.

---

### P1-7 · `git trident hooks enable` is a silent no-op — **S**

**File** [`bin/git-trident-hooks:284–288`](../bin/git-trident-hooks#L284)

Two defects stacked, and the command reports success through both.

**(a) The grep matches a comment.** `templates/git-trident-config` contains no
`HOOKS_ENABLED` assignment — only a comment mentioning it:

```
templates/git-trident-config:93:  # Granular hook control (requires HOOKS_ENABLED=true in global config).
```

`grep -q "HOOKS_ENABLED=" "$config_file"` matches that line, so the code takes the
"update existing setting" branch and runs an anchored substitution:

```bash
sed -i.bak 's/^HOOKS_ENABLED=.*/HOOKS_ENABLED=true/' "$config_file"
```

`^` cannot match a line beginning with `#`, so **the file is unchanged** — yet the next
statement logs `✓ Updated HOOKS_ENABLED=true in: …` unconditionally. Verified: file byte-identical
after the sed.

**(b) It targets the wrong configuration tier.** `enable_hooks "auto"` prefers
`./git-trident-config` when present ([`:262`](../bin/git-trident-hooks#L262)) — which is
always, because Trident requires a project config. But `HOOKS_ENABLED` is declared
**global-only** ([`common.sh:82`](../lib/git-trident-common.sh#L82)), so even a successful
write would be discarded by the loader and warned about on the next command.

Net effect: `git trident hooks enable` → `✓ Updated` → hooks still disabled → invalid
commit messages are accepted. Reproduced on both a default and a custom-path install.

**Fix.**

1. Match assignments only: `grep -qE '^[[:space:]]*HOOKS_ENABLED=' "$config_file"`.
2. Verify the write and report the truth — re-grep after `sed`, fail loudly if unchanged.
3. Route global-only keys to the **global** config regardless of `auto`. Better: derive
   the target tier from the key itself, reusing `GLOBAL_ONLY_CONFIG_KEYS` as the single
   source of truth rather than hardcoding a preference order.
4. Apply the identical fix to `disable_hooks` ([`:317`](../bin/git-trident-hooks#L317)),
   which has the same structure.

**Verify.** Fixture: `hooks enable` → assert `HOOKS_ENABLED=true` lands in the *global*
config, then assert an invalid commit message is actually rejected.

---

## 6. Phase 3 — Architecture

These are the structural changes. Each removes a **class** of defect rather than an instance.

### A1 · Resolve all three roots once — **L** · _closes P1-1, P1-6, P2-7, P3-7 and 4 × P2_

> **Widened.** The first draft covered only the *repository* roots. Four separate
> defects turned out to share one root cause — **a root that is assumed rather than
> derived** — so this task now owns all three.

| Root | Assumed today as | Defects it causes |
|---|---|---|
| `GT_INSTALL_ROOT` | `$HOME/.git-trident`, or `$SCRIPT_DIR/..` without resolving symlinks | **P1-6** (update relocates a custom install), **P2-7** (symlinked entrypoint breaks everything), **P3-7** (wrong paths in error messages) |
| `GT_REPO_ROOT` | cwd (`./git-trident-config`) | **P1-1** (only works from the repo root) |
| `GT_GIT_DIR` | literal `.git/` relative to cwd | locks, tag cache, `MERGE_HEAD`, report path — broken in subdirectories and worktrees |

#### A1a · Install root — a shared preamble in every `bin/` script

Chicken-and-egg: this cannot live in a library, because it is what *finds* the library.
It must be inlined — 8 lines at the top of each `bin/` script, replacing the current
`SCRIPT_DIR=` line:

```bash
# --- Git Trident preamble: resolve the real script location (symlink-safe) ---
GT_SELF="${BASH_SOURCE[0]}"
while [ -L "$GT_SELF" ]; do
    GT_LINK_DIR="$(cd -P "$(dirname "$GT_SELF")" && pwd)"
    GT_SELF="$(readlink "$GT_SELF")"
    case "$GT_SELF" in /*) ;; *) GT_SELF="$GT_LINK_DIR/$GT_SELF" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$GT_SELF")" && pwd)"
GT_INSTALL_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"
# -----------------------------------------------------------------------------
```

**Why this form.** Plain `readlink` is POSIX and works on BSD and GNU alike;
`readlink -f` is **not** available on macOS before 12.3, which is why
`git-trident-hooks:21` already needs a fallback it does not have (**P2-6**). The loop
also follows symlink *chains* and handles relative link targets, which `readlink -f`
would but a single `readlink` call would not.

**Verified on Bash 3.2.57** across all four invocation styles:

| Invocation | `GT_INSTALL_ROOT` | lib found |
|---|---|---|
| direct path | `…/real` | ✅ |
| absolute symlink | `…/real` | ✅ |
| relative symlink → symlink (chain) | `…/real` | ✅ |
| `PATH` lookup of the symlink | `…/real` | ✅ |

And end-to-end against the real dispatcher, invoked through a symlink on `PATH`:

```
BEFORE : …/localbin/../lib/git-trident-common.sh: No such file or directory
         pre_operation_checks: command not found      (exit 0 — silent failure)
AFTER  : [INFO] 🔍 Running pre-operation checks for: status      ✅
```

Keep `SCRIPT_DIR` as the variable name so the ~40 existing `$SCRIPT_DIR/../lib/…`
references keep working unchanged — only its *computation* changes. Apply to all 10
`bin/` scripts **and** `hooks/commit-msg`, which has the same pattern.

Then replace the assumed install paths:

| Today | Becomes |
|---|---|
| `bash "$tmp_installer"` *(version:599)* | `bash "$tmp_installer" "$GT_INSTALL_ROOT"` — **P1-6** |
| `"$HOME/.git-trident"` in `discover_install_dir` *(hooks:33)* | drop the hardcoded list; the preamble already resolved it |
| `$HOME/$PROJECT_DIR_NAME/templates/…` *(common.sh:252-253)* | `$GT_INSTALL_ROOT/templates/…` — **P3-7** |
| `cp ~/.git-trident-global-config …` *(help.sh:703)* | `git trident config init` *(the referenced file never exists)* — **P3-7** |

#### A1b · Repository roots — `lib/git-trident-context.sh`

Sourced by `common.sh` once the install root is known:

```bash
GT_REPO_ROOT=$(git rev-parse --show-toplevel   2>/dev/null) || return 1
GT_GIT_DIR=$(git   rev-parse --absolute-git-dir 2>/dev/null) || return 1
export GT_REPO_ROOT GT_GIT_DIR
```

Then mechanically replace:

| Today | Becomes |
|---|---|
| `./git-trident-config` | `$GT_REPO_ROOT/git-trident-config` |
| `.git/git-trident-locks` | `$GT_GIT_DIR/git-trident-locks` |
| `.git/git-trident-rc-lock` | `$GT_GIT_DIR/git-trident-rc-lock` |
| `.git/git-trident-remote-tags-*` | `$GT_GIT_DIR/git-trident-remote-tags-*` |
| `[ -f ".git/MERGE_HEAD" ]` | `[ -f "$GT_GIT_DIR/MERGE_HEAD" ]` |
| `release_notes/` | `$GT_REPO_ROOT/release_notes/` |

Side benefit: worktree and submodule support, for free.

#### Ordering

**A1a before A1b.** The install root must resolve before anything is sourced; the
repository roots need `git` and a repo, which utility commands (`version`, `config`,
`hooks`, `uninstall`) legitimately run without. Keep them separate so `--help` and
`version` stay usable outside a repository (**A11**).

#### Verification

- `test_e2e_cwd.sh` — every command from a nested subdirectory (**P1-1**)
- `test_e2e_symlink.sh` — install to a custom path, symlink the entrypoint onto `PATH`,
  run the full lifecycle, assert **no** `No such file or directory` on stderr (**P2-7**)
- `test_e2e_custom_path_update.sh` — custom install, run the updater, assert it updates
  in place and that `$HOME/.git-trident` is **not** created (**P1-6**)
- `test_e2e_worktree.sh` — run from a `git worktree`, assert locks and `MERGE_HEAD`
  resolve correctly

---

### A2 · Stop `source`-ing config — parse it — **L** · _security + correctness_

Today [`common.sh:116–124`](../lib/git-trident-common.sh#L116):

```bash
set -a
source "$config_file"     # ← arbitrary code execution from a committed repo file
set +a
```

Two real problems:

1. **`git-trident-config` is committed and executed.** Cloning a repository and running
   any trident command runs whatever is in that file. For a tool explicitly designed to
   be shared across a team, that is a supply-chain hole.
2. **`set -a` exports everything.** This is why `CONFIG_LOADED=true` leaks into child
   processes and makes them skip validation entirely, and why a stray environment
   variable in the user's shell silently overrides project config.

It also forces the `GLOBAL_ONLY_CONFIG_KEYS` snapshot/restore workaround at
[`common.sh:199–236`](../lib/git-trident-common.sh#L199), built on `eval` with
dynamically-constructed variable names — fragile and hard to test.

**Proposed reader:**

```bash
gt_config_load_file() {       # <file> <scope: global|project>
    local file="$1" scope="$2" line key val
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
        key="${BASH_REMATCH[2]}"; val="${BASH_REMATCH[3]}"
        val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
        gt_config_key_is_known "$key" || { log_warn "Unknown config key: $key"; continue; }
        if [ "$scope" = project ] && gt_config_key_is_global_only "$key"; then
            log_warn "Ignoring global-only key in project config: $key"; continue   # ← never loaded
        fi
        printf -v "$key" '%s' "$val"
    done < "$file"
}
```

Wins: no code execution, no env leakage, the snapshot/restore hack **deletes entirely**
(global-only keys are simply never read from a project file), unknown keys are caught
at load time instead of silently ignored, and the loader becomes directly unit-testable.

Note: this is a behavioral change — anyone using shell expressions inside their config
breaks. Ship behind `CONFIG_PARSER=strict|legacy` for one minor version, default
`strict` in the next.

---

### A3 · Namespace every function — **M** · _closes the collision class_

`staging.sh` and `production.sh` both define `validate_release_branch_exists`,
`validate_hotfix_branch_exists`, `show_release_preparation_summary`,
`show_hotfix_changes`, `show_hotfix_completion_summary`. Both sync libs define
`show_detection_analysis` with **different signatures**. `is_valid_tag` is defined twice.

Safe today only because one lib loads per command — but `check_hotfix_impact`
([`staging.sh:573`](../lib/git-trident-staging.sh#L573)) and `check_staging_synchronization`
([`production.sh:263`](../lib/git-trident-production.sh#L263)) cross-source at runtime,
so the guarantee is already broken in practice.

Convention: `gt_<module>_<verb>` — `gt_stg_validate_release_branch`,
`gt_prod_validate_release_branch`, `gt_ver_extract_platform`, `gt_log_info`.
Mechanical and scriptable; add a test asserting no symbol is defined in two libs.

---

### A4 · Eliminate echo-based multi-value returns — **M** · _closes P0-3a + 3 × P2_

The pattern that broke `--env`:

```bash
echo "$mode $generate_report $show_deprecated $platform_filter $environment"
IFS=' ' read -r mode generate_report show_deprecated platform_filter environment <<< "$(parse_arguments "$@")"
```

Empty fields collapse, everything shifts, no error. It also means `exit 1` inside
`parse_arguments` only kills the **subshell** — the caller continues with empty values
(`push-all:990`, `verify-sync:1276`, `staging-sync-tags:547`).

`bin/git-trident-version` already does this correctly with `PARSE_RESULT_COMMAND`.
Standardize on it: parsers set `GT_ARG_*` globals and return a status; never echo.

Same treatment for the `:`-delimited `analyze_tag_propagation_impact`
([`push-all:33`](../bin/git-trident-push-all#L33)), whose early returns emit **5** fields
while the success path emits **6**.

---

### A5 · A `gt_git` wrapper, and stop blanket-suppressing errors — **L**

162 suppression sites. The damage is concentrated where failure matters most:
`interactive_merge` hides the real git error and misreports it as a conflict (P0-2);
`cleanup prune` hides every delete failure (P1-5); `push_tags` hides per-tag failures.

```bash
gt_git() {
    local out rc
    out=$(git "$@" 2>&1); rc=$?
    [ $rc -ne 0 ] && log_debug "git $* → exit $rc: $out"
    printf '%s' "$out"
    return $rc
}
```

Migrate in priority order: **merge → tag → push → delete**, then everything else.
Read-only probes (`git rev-parse`, `git show-ref`) may keep `2>/dev/null`; those are
legitimate existence tests.

---

### A6 · One boolean convention — **S** · _closes P1-4_

Functions currently mix "0 = success" with "0 = found", which is the direct cause of
P1-4. Adopt and enforce:

| Prefix                              | `return 0` means    |
|-------------------------------------|---------------------|
| `check_*`, `validate_*`, `verify_*` | **healthy / valid** |
| `has_*`, `is_*`, `*_exists`         | **true**            |

Rename the offenders (`check_deprecated_tags*` → `has_deprecated_tags*`) and document
it in `CONTRIBUTING.md`.

---

### A7 · Unify locking; allocate the RC number exactly once — **M**

Today [`version-utils.sh:334–362`](../lib/git-trident-version-utils.sh#L334):

```bash
while [ -f "$lock_file" ] && [ $waited -lt $max_wait ]; do sleep 0.5; ... done
touch "$lock_file"           # ← test-then-touch: not atomic (TOCTOU)
...
rm -f "$lock_file"           # ← released BEFORE the tag is created
echo "$next_rc"
```

Three defects: the check/create is not atomic; after 5 s it proceeds **without** the
lock anyway; and the critical section (read the latest RC → create tag) is not covered,
because the lock is released at the end of this function while the tag is created later
(`staging.sh:661`). Meanwhile, the correct `mkdir`-based `acquire_lock`/`release_lock`
([`common.sh:1151`](../lib/git-trident-common.sh#L1151)) is **dead code — never called**.

Also, `staging_hotfix_finish` calls `get_next_rc_number` while `staging_hotfix_start`
already called it, so the number is computed twice from different repository states.

**Fix.** Delete the `touch` lock. Use the mkdir lock, acquire it around
*allocate → tag*, release via `trap … EXIT INT TERM`, and compute the RC number once
per command, passing it down.

---

### A8 · Tag-grammar module — **M**

`STAGING_TAG_SUFFIX` is interpolated **unescaped** into `[[ =~ ]]` in ~8 places
(`version-utils.sh:47, 97, 139`, `verify-sync:317, 325`, `sync-tags:79, 118, 249`…).
A suffix containing `.`, `+`, `*` or `[` silently mis-matches: `.rc.` would match
`Xrc1` as readily as `.rc.`.

New `lib/git-trident-tagspec.sh` owning composition and matching:

```bash
gt_regex_escape() { printf '%s' "$1" | sed 's/[][\.*^$(){}?+|\/]/\\&/g'; }
gt_tag_staging()        { printf '%s%s%s%02d' "$STAGING_TAG_PREFIX" "$1" "$(gt_rc_suffix)" "$2"; }
gt_tag_staging_glob()   { printf '%s%s%s*'    "$STAGING_TAG_PREFIX" "$1" "$(gt_rc_suffix)"; }
gt_tag_staging_regex()  { printf '^%s(.+)%s([0-9]+)$' "$(gt_regex_escape "$STAGING_TAG_PREFIX")" ...; }
```

Every prefix/suffix concatenation in the codebase routes through it. Add a test matrix
of exotic suffixes (`-rc-`, `.rc.`, `_RC_`, `+rc+`).

---

### A9 · Shell-safety baseline — **REVISED for Bash 3.2** — **M**

> The first draft proposed adopting `set -u`. **That was wrong** and is withdrawn.
> It is the exact failure mode §0 warns about: it passes on the author's Bash 5 and
> breaks on users' Macs.

**Why `set -u` is off the table.** On Bash 3.2, expanding an *empty* array raises an
error; from 4.4 onward it expands to nothing:

```
bash 3.2.57 :  set -u; a=(); printf "%s" "${a[@]}"   →  a[@]: unbound variable
bash 5.3.20 :  set -u; a=(); printf "%s" "${a[@]}"   →  (prints nothing, exit 0)
```

There are **84** such expansions across `bin/ lib/ hooks/` — including arrays that are
routinely empty in normal operation (`tags_to_delete`, `batch`, `stale_branches`,
`check_results`, `strategy_args`). Enabling `set -u` would convert "nothing to clean up"
into a crash, on macOS only, for every one of them.

**Revised baseline:**

1. **`set -o pipefail`** in every `bin/` entry point. Safe on 3.2, and immediately
   exposes the `git push … | tee | grep` masking bug in `push_branch` (P2-1).
2. **No `set -u`.** Instead get the same protection without the portability cost:
   - default every optional read: `"${VAR:-}"` — already the dominant style
   - shellcheck **SC2154** (referenced but not assigned) via **T0.3**, which catches
     genuine typos statically and costs nothing at runtime
   - **T0.4** actively fails the build if `set -u` is reintroduced
3. **No `set -e`.** Unchanged from the first draft: this codebase uses non-zero returns
   for control flow throughout. Use explicit checks plus `gt_git` (**A5**).
4. **Audit the 84 array expansions** as a standalone task: any array that can be empty
   at the expansion point must use `${arr[@]+"${arr[@]}"}`. Do this even without
   `set -u` — it is the form that stays correct if anyone ever turns it on, and it
   documents intent.

**Net effect:** the safety goal (catch unset variables) moves from runtime to static
analysis, where it is both stricter and portable.

---

### A10 · stdout / stderr contract — **S**

~120 raw `echo`/`printf` calls bypass the loggers. `show_platform_summary` and
`show_brief_status` write to **stdout** mid-way through a stderr log stream, so
`git trident status > file` produces a fragmented, interleaved mess.

Rule: **logs → stderr, data → stdout.** Only values a caller consumes (tag names,
versions, parsed results) go to stdout. Prerequisite for E1 (`--json`).

---

### A11 · Make `--help` work without a repository — **S**

[`bin/git-trident:8`](../bin/git-trident#L8) whitelists `help|--help|-h|version|config|hooks|uninstall`
for `--no-init`, but misses the staging/production namespaces. Result:

```
$ git trident staging release --help
[ERROR] ❌ Not inside a Git repository.
```

Help requires a repo, a project config **and** network reachability (because
`run_pre_operation_checks` runs before dispatch). Detect `--help`/`-h`/`help` anywhere
in the argv **before** config load and pre-operation checks, and short-circuit.

---

### A12 · Dead-code removal — **S**

13 functions defined and never called (~330 lines):

| File                      | Dead functions                                                                                                                                        |
|---------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| `common.sh`               | `acquire_lock`, `release_lock`, `validate_platform_config`, `get_dependent_platforms`                                                                 |
| `version-utils.sh`        | `filter_tags_by_propagation_rules`, `validate_version_with_classification`, `get_latest_staging_base_version`, `show_platform_classification_summary` |
| `sync-from-staging.sh`    | `process_propagation_versions`, `find_affected_versions`, `get_staging_tags_newer_than_version`                                                       |
| `sync-from-production.sh` | `process_rebase_versions`, `find_outdated_staging_tags`                                                                                               |

Plus: `_write_line` (`config`), unused `rc_int` / `latest_version` / `rc_number`
(`verify-sync:418, 469, 707, 710, 751, 754`), and the ~60-line commented-out
delivery block in `changelog-generation` together with its four config keys.

**Caveat:** `acquire_lock`/`release_lock` are dead but **correct** — A7 revives them
rather than deleting them. The `process_*_versions` pair duplicates logic that the main
flows inline; delete the dead copies rather than the live loops.

---

## 7. Phase 4 — P2 / P3 remainder

Items **not** absorbed by Phase 3:

| ID   | Issue                                                                                                                                                       | File                          | Fix                                                                                              | Size |
|------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------|--------------------------------------------------------------------------------------------------|------|
| P2-1 | `push_branch` pushes twice — the first `git push` inside the `if` already performs it, and the pipeline's exit status is `grep`'s, not git's                | `push-all:804`                | Push once, capture `rc` and output                                                               | S    |
| P2-2 | `cleanup sync branches` yields `*` as a branch name for the current branch (`awk '{print $1}'` returns the `*` marker)                                      | `cleanup:192`                 | `git for-each-ref --format='%(refname:short) %(upstream:track)'` instead of parsing `branch -vv` | S    |
| P2-3 | Orphan `temp-rebase-*` / `temp-propagate-*` branches survive an interrupted sync                                                                            | `sync-from-*.sh`              | `trap` cleanup + `git trident cleanup temp`                                                      | M    |
| P2-4 | `check_staging_releases_need_rebase` returns 1 both for "needs rebase" and "prerequisites invalid"                                                          | `sync-from-production.sh:675` | Distinct exit codes (0 ok / 1 action / 2 error)                                                  | S    |
| P2-5 | `generate_sync_report` writes into `.git/` — reports are user artifacts, and are lost on clone                                                              | `verify-sync:107`             | Write to `$GT_REPO_ROOT/.git-trident-reports/`, gitignored                                       | S    |
| P2-6 | `readlink -f` is GNU-only (BSD fallback missing)                                                                                                            | `hooks:21`                    | Guarded `readlink -f` → `python3`/loop fallback, or drop (branch 1 almost always wins)           | S    |
| P2-7 | **Symlinked entrypoint breaks every command** — `SCRIPT_DIR` does not resolve symlinks, so `ln -s …/bin/git-trident /usr/local/bin/` makes all three `source` lines fail, then `pre_operation_checks: command not found` — **and it still exits 0**. 9 of 10 `bin/` scripts have no symlink handling; only `git-trident-hooks` does | all `bin/*:5` | **Implemented by A1a** — symlink-resolving preamble | M |
| P3-1 | README + QUICK_START document `release/staging/`, `hotfix/staging/`, `release/prod-<v>`; actual defaults are `release/stg/`, `hotfix/stg/`, `release/prod/` | docs                          | Correct the docs                                                                                 | S    |
| P3-2 | CONTRIBUTING.md claims Bash 4+ associative arrays "heavily utilized"                                                                                        | `CONTRIBUTING.md`             | Covered by T0.4                                                                                  | S    |
| P3-3 | `templates/git-trident-config` has no trailing newline — appending corrupts the last line                                                                   | template                      | Add newline; add a test                                                                          | S    |
| P3-4 | Repo does not dogfood its own config                                                                                                                        | repo root                     | Add a `git-trident-config` matching the repo's actual branch topology                            | S    |
| P3-5 | `SCRIPTS_TEST_CASES.md` marks cases "📝 Implemented" with no link to the asserting test                                                                     | docs                          | Add test-file/case references; make the registry the index the integration suites map onto       | M    |
| P3-6 | README documents `git trident hooks [install/enable/status]`, but `install` is not a subcommand — actual names are `install-local` / `install-global` (or `local` / `global`) | `README.md:180` | Correct the docs, or add `install` as an alias that prompts for scope | S |
| P3-7 | Install-path assumptions hardcoded in user-facing messages: `common.sh:252-253` points at `$HOME/.git-trident/templates/…` (wrong for a custom install), and `help.sh:703` says `cp ~/.git-trident-global-config …` — **a file that never exists** (installer writes `~/.git-trident-config`), and copying the *global* config into the *project* tier is the exact mistake the loader warns about | `common.sh:252`, `help.sh:703` | **Implemented by A1a** — use `$GT_INSTALL_ROOT`; replace the help snippet with `git trident config init` | S |

---

## 8. Phase 5 — Enhancements

| ID  | Enhancement                                            | Rationale                                                                                              | Size |
|-----|--------------------------------------------------------|--------------------------------------------------------------------------------------------------------|------|
| E1  | `--json` on `status`, `verify-sync`, `tags`, `version` | Makes the tool scriptable; depends on **A10**                                                          | M    |
| E2  | `--dry-run` on every mutating command                  | Only `sync-tags` has it today; the highest-risk commands (`release finish`, `hotfix finish`) have none | M    |
| E3  | `git trident doctor`                                   | Consolidates `version health` + `verify-sync` + config validation into one diagnostic                  | S    |
| E4  | `git trident abort`                                    | Unwind a partially-completed flow: abort merge, drop temp branches, delete the just-created tag        | M    |
| E5  | Global `--yes` / `--non-interactive`                   | Today only `version update` has it; needed for any automation                                          | S    |
| E6  | `--no-color` + `NO_COLOR` env support                  | `common.sh:91` only checks `[[ -t 1 ]]`                                                                | S    |
| E7  | Bash/zsh completions                                   | Large command surface, deeply nested subcommands                                                       | M    |
| E8  | `CONFIG_SCHEMA_VERSION` key                            | Enables safe config migrations; pairs with **A2**                                                      | S    |
| E9  | `git trident config validate`                          | Validate without running an operation; reuses the A2 loader                                            | S    |
| E10 | `git trident config migrate`                           | Rewrite configs when keys are renamed/moved between tiers                                              | M    |
| E11 | Structured progress for long syncs                     | `sync-tags` across many versions gives no overall progress indication                                  | S    |

---

## 9. Task checklist

### Phase 0 — Safety net
- [x] **T0.1** `tests/lib/repo_fixture.sh` — isolated HOME, real bare remote, stdin from /dev/null, per-commit files, and `assert_no_shell_errors` / `assert_tags_equal` / `assert_branch_contains` — **DONE**
- [x] **T0.2** Six e2e suites, 126 assertions: staging, production+hotfix, sync-tags (both directions), push-all, cwd/worktree, multi-platform — **DONE**
- [ ] **T0.3** `tests/test_shellcheck.sh`, `-S error` + **SC2154**, skip-if-absent — **S**
- [x] **T0.4** `tests/test_bash32_compat.sh` — 15 checks: Bash 4+ constructs, `set -u`, CRLF, `.gitattributes`, git-index exec bits, shebangs — **DONE**
- [x] **T0.5** `GT_TEST_BASH` → suite runs under the platform bash; warns when not 3.2 — **DONE**
- [ ] **T0.6** Correct CONTRIBUTING.md: floor is Bash 3.2, no brew required — **S**


### Landed out-of-plan (surfaced while implementing, cross-platform critical)

- [x] **`.gitattributes`** — `* text=auto eol=lf`. Git for Windows defaults to
  `core.autocrlf=true`, which rewrites every script to CRLF on checkout and yields
  `bash: /bin/bash^M: bad interpreter`. The repo had no `.gitattributes` at all.
- [x] **Exec bits corrected in the git index** — `bin/git-trident-changelog-generation`
  and `hooks/commit-msg` were mode `100644`. Installed copies worked only because
  `install.sh` chmods; running from a clone (the workflow CONTRIBUTING.md documents)
  failed with `Permission denied`. Windows cannot represent the bit in the filesystem,
  so the index is the only portable source of truth — now asserted by **T0.4** `bc_14`.


### Landed out-of-plan (Phase 0, completed)

- [x] **Changelog delivery removed completely** — code, config keys, comments, docs and
  test fixtures. `git grep -i webhook` now returns nothing.
- [x] **Two fixture properties learned from failures while writing the suites:**
  `gt_fixture_run` redirects stdin from `/dev/null`, because `REQUIRE_CONFIRMATION=false`
  silences `confirm_action` but NOT `force_confirm_action` — a test that hit a merge
  conflict hung indefinitely instead of failing. And `gt_fixture_commit` writes to a
  distinct file per commit, because appending everything to one file made independent
  release lines conflict artificially.
- [x] **All `tests/` files normalised to mode 100755 in the git index**, for the same
  reason as `bin/` and `hooks/`: Windows cannot represent the bit in the filesystem.

### Phase 1 — P0
- [x] **P0-1** Tag kept verbatim for the URL (HTTP 200, was 404); `is_version_greater` comparison prevents downgrades — **DONE**
- [x] **P0-2** `-X` as separate argv (`${a[@]+…}` form); git stderr captured; conflict vs. non-conflict failures now distinguished — **DONE**
- [x] **P0-3** Parser sets `GT_ARG_*` globals (no echo/`read` field collapse); **Option B** taken — all 8 checks implemented as thin delegations; exit status now propagates — **DONE**
- [x] **P0-4** `count_lines()` in common.sh + empty-guard before the tag loop (4 sites) — **DONE**
- [x] **P0-5** `SUPPRESS_CONFIG_ERRORS=true` in the hooks loader **and** an opt-in check in `check_hooks_enabled` (the second noise path) — **DONE**
- [x] **P0-6** Removed `declare -A` + the Bash-4 shim; hardened 3 array expansions for `set -u` on 3.2 — **DONE**

### Phase 2 — P1
- [x] **P1-1** `GT_REPO_ROOT`/`GT_GIT_DIR` via **A1b**; all cwd- and `.git`-relative paths anchored; worktrees work — **DONE**
- [x] **P1-2** `_ask_bool` returns the default verbatim on an empty answer — **DONE**
- [x] **P1-3** Glob expanded by the shell; `ls-remote` status checked so a failed fetch is never cached — **DONE**
- [x] **P1-4** Early returns inverted (2 sites); verified both directions — **DONE**
- [x] **P1-5** Per-tag counts, remote pre-filter, batch falls back to one-by-one; honest summary + non-zero exit on failure — **DONE**
- [x] **P1-6** `GT_INSTALL_ROOT` passed to the installer, so a custom install updates in place — **DONE**
- [x] **P1-7** `gt_config_set_key` (anchored + verified) and `gt_config_file_for_key` (tier from `GLOBAL_ONLY_CONFIG_KEYS`) — **DONE**


### Landed out-of-plan (Phase 2)

- [x] **A1b** `lib/git-trident-context.sh` — `gt_resolve_repo_context`, `gt_repo_path`,
  `gt_git_path`. Deliberately **not cached and not exported**: a child process could
  inherit a root belonging to a different repository, and a shell that changed directory
  would keep resolving against the old one.
- [x] **P2-5** Verification reports moved out of `.git/` into a gitignored
  `.git-trident-reports/` — they are user artifacts, and inside `.git` they were
  invisible and lost on a fresh clone.
- [x] **Test isolation fixed.** `tests/sandbox_test` sits INSIDE the Git Trident
  checkout, so it was never a repository root and inherited this repo's own `origin`.
  The config tests were therefore asserting the pre-P1-1 behaviour. The sandbox now
  runs `git init` with its own bare remote. This was not cosmetic: during development
  an intermediate run wrote `config_01`'s answers (`prod-main`/`stg-rc`/`dev-flow`) into
  the real project root as `git-trident-config`. The suite could modify the user's
  actual project; it no longer can.

### Phase 3 — Architecture
- [x] **A1a** Preamble in 11 entry points; `discover_install_dir` simplified, GNU-only `readlink -f` eliminated — **DONE** _(remaining: thread `GT_INSTALL_ROOT` into `version update` (P1-6), `common.sh:252-253` and `help.sh:703` (P3-7))_
- [ ] **A1b** `git-trident-context.sh` → `GT_REPO_ROOT` / `GT_GIT_DIR`; replace all cwd- and `.git`-relative paths — **M**
- [x] **A2** `_parse_config_file` with an allowlist; `CONFIG_PARSER=legacy` escape hatch; snapshot/restore now legacy-only; config no longer exported — **DONE**
- [x] **A3** **Targeted**: the 10 genuine lib/ collisions renamed (`stg_*`/`prod_*`/`stg_sync_*`/`prod_sync_*`), duplicate `is_valid_tag` dropped, `tests/test_no_duplicate_symbols.sh` guards regressions — **DONE** _(a full 367-function rename was judged high-churn/low-value; `main` and `parse_arguments` repeat across `bin/` by design, since those are separate processes)_
- [x] **A4** All four parsers set `GT_ARG_*`; `analyze_tag_propagation_impact` emits six fields on every path — **DONE**
- [x] **A5** `gt_git` / `gt_git_checked` added; `verify_step` and `push_branch` now surface git's real error — **DONE**
- [x] **A6** `check_deprecated_tags_*` → `has_deprecated_tags_*`; convention documented in CONTRIBUTING.md — **DONE**
- [x] **A7** touch-lock removed; mkdir lock held across allocate→tag with a trap; RC computed once — **DONE**
- [x] **A8** `lib/git-trident-tagspec.sh` with separate ERE and BRE escapers; verified across `-rc- .rc. +rc+ _RC_ [rc]` — **DONE**
- [x] **A9** `set -o pipefail` in all 11 entry points; `set -u` withdrawn (Bash 3.2) and blocked by T0.4 — **DONE**
- [x] **A10** Platform summary table and brief-status lines moved to stderr — **DONE**
- [x] **A11** Help detected across all argv before sourcing; 14 invocations verified outside a repository — **DONE**
- [x] **A12** 20 dead functions + the abandoned changelog-delivery feature and its config keys removed (−461 lines) — **DONE**


### Landed out-of-plan (Phase 3)

- [x] **Config no longer crosses process boundaries.** A2 set values with `printf -v`
  (not exported) while `CONFIG_LOADED=true` was still exported, so any `exec`-dispatched
  subcommand short-circuited loading and then found every setting empty:
  `git trident status` reported branch desynchronisation on a synchronised repository,
  while `git-trident-verify-sync --brief` reported it correctly. Nothing is exported now,
  and `load_project_config` ignores the flag when no configuration is actually present.
- [x] **`tests/test_subprocess_config.sh`** — every suite passed both before and after
  that bug, because they all source the libraries in-process. These tests drive the real
  binaries: dispatcher vs direct invocation must agree, no config key may be exported, a
  stale inherited flag must not blank the config, and dispatch must work from a
  subdirectory.
- [x] **`tests/test_no_duplicate_symbols.sh`** — fails when two `lib/` files define the
  same function, which is how `show_detection_analysis` came to exist twice with
  different parameter orders.

### Phase 4 — Remainder
- [ ] **P2-1 … P2-7**, **P3-1 … P3-7** (table in §7)

### Phase 5 — Enhancements
- [ ] **E1 … E11** (table in §8)

---

## 10. Open decisions

Three items need a product call before implementation:

1. ~~**P0-3** — Option A or B?~~ **RESOLVED: Option B.** All eight checks were
   implemented as thin delegations to functions that already existed and were already
   exercised by the comprehensive run (`get_all_*_tags`, `check_branch_sync_status`,
   `validate_rc_sequence_for_platform`, `check_staging_releases_need_rebase`,
   `detect_staging_hotfix_impact`), so no second implementation of any analysis was
   introduced. Option A would have left `production`, `staging` and `development`
   roles producing identical output, which is honest but near-useless.
2. **A2** — accept that configs stop being executable shell? It is the correct fix, but it
   is a breaking change for anyone using shell expressions in `git-trident-config`.
   Proposed: `CONFIG_PARSER=strict|legacy` for one minor version.
3. **A3** — a full `gt_*` rename touches every file and makes the diff large. Worth doing
   in one pass, or limit to the eight genuinely colliding symbols?
4. **P0-6 / §0** — confirm that dropping the Bash-4 requirement outright (rather than
   improving the shim to handle the piped case) is the direction. Dropping it is
   strictly better: it removes `brew install bash` from onboarding and brings
   `install.sh` under the same compatibility gate as everything else. The only cost is
   five lines of colour-variable syntax.

---

## 11. Appendix — Bash 3.2 cookbook

Keep this with `CONTRIBUTING.md`. Left column breaks on macOS; right column works everywhere.

| Instead of (Bash 4+) | Use (Bash 3.2-safe) |
|---|---|
| `declare -A m; m[k]=v; ${m[k]}` | parallel arrays, or a `k=v` string split with `case`/`IFS` — as `parse_commit_prefix_config` already does |
| `mapfile -t arr < <(cmd)` | `IFS=$'\n' read -d '' -ra arr <<< "$(cmd)"` |
| `"${arr[@]}"` *(array may be empty)* | `${arr[@]+"${arr[@]}"}` |
| `set -u` | `"${VAR:-}"` defaults + shellcheck **SC2154** |
| `local -n ref=$name` | `eval "$name=…"` / `eval "$name+=(…)"` *(existing idiom)* |
| `${s^^}` / `${s,,}` | `tr '[:lower:]' '[:upper:]'` / `awk '{print toupper($0)}'` |
| `[[ -v VAR ]]` | `[ -n "${VAR+x}" ]` |
| `;;&` case fall-through | restructure, or repeat the branch |
| `echo ${arr[-1]}` | `echo "${arr[${#arr[@]}-1]}"` |
| `&>> file` | `>> file 2>&1` |

**Quick local check before every commit:**

```bash
/bin/bash --version | head -1     # must say 3.2.57 on macOS
/bin/bash tests/run_all.sh        # the floor, not the author's shell
```
