#!/bin/bash
# tests/test_bash32_compat.sh
# Portability gate — macOS / Linux / Windows (Git Bash).
#
# Git Trident must run on the oldest Bash any supported platform ships:
#   macOS   /bin/bash  → 3.2.57   ← the floor
#   Linux   /bin/bash  → 4.x–5.x
#   Windows Git Bash   → 4.4–5.x  (MSYS2)
#
# A Bash 4+ construct passes on the author's machine and fails on every Mac, so
# this gate is static: it fails the suite the moment one is introduced.
#
# Uses POSIX ERE (grep -E) only — no grep -P, which is unavailable on BSD grep.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# This file necessarily contains the banned patterns as data; never scan it.
SELF_NAME="test_bash32_compat.sh"

# ---------------------------------------------------------------------------
# Build the list of shipped shell files (portable: no 'find -printf', no mapfile)
# ---------------------------------------------------------------------------
collect_shell_files() {
    local f
    for f in bin/* lib/*.sh hooks/* tests/*.sh scripts/*.sh install.sh build.sh; do
        [ -f "$f" ] || continue
        case "$f" in */"$SELF_NAME") continue ;; esac
        echo "$f"
    done
}

SHELL_FILES="$(collect_shell_files)"

# grep -E across the file list; prints "file:line:match", empty when clean.
#
# Comment-only lines are excluded. A banned construct is legitimate inside a
# comment that documents why it is banned, and matching comments is exactly the
# false-positive that makes `hooks enable` a silent no-op (see P1-7) — so the
# lesson is applied here rather than repeated.
scan() {
    local pattern="$1" file hits=""
    for file in $SHELL_FILES; do
        hits="$hits$(grep -nE "$pattern" "$file" 2>/dev/null \
                     | grep -vE '^[0-9]+:[[:space:]]*#' \
                     | sed "s|^|$file:|")"
    done
    echo "$hits"
}

# Assert a pattern appears nowhere. Prints offenders on failure.
assert_absent() {
    local pattern="$1" label="$2"
    local hits
    hits="$(scan "$pattern")"
    if [ -z "$hits" ]; then
        assert_success 0 "$label"
    else
        test_log "${RED}     offending lines:${NC}"
        echo "$hits" | sed 's/^/       /'
        assert_success 1 "$label"
    fi
}

start_suite "Bash 3.2 / Cross-Platform Portability Gate"

# ---------------------------------------------------------------------------
# BC_01..BC_10 — Bash 4.0+ constructs
# ---------------------------------------------------------------------------
start_test_case "bc_01_no_associative_arrays"
assert_absent '(declare|local|typeset)[[:space:]]+-[A-Za-z]*A([[:space:]]|$)' \
    "No associative arrays (declare -A — Bash 4.0)"

start_test_case "bc_02_no_mapfile_readarray"
assert_absent '(^|[^[:alnum:]_])(mapfile|readarray)([^[:alnum:]_]|$)' \
    "No mapfile/readarray (Bash 4.0)"

start_test_case "bc_03_no_case_fallthrough"
assert_absent ';;&' \
    "No ;;& case fall-through (Bash 4.0)"

start_test_case "bc_04_no_coproc_or_new_redirects"
assert_absent '(^|[^[:alnum:]_])coproc([^[:alnum:]_]|$)|\|&|&>>' \
    "No coproc / |& / &>> (Bash 4.0)"

start_test_case "bc_05_no_case_modification"
assert_absent '\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,|\^|,)[^}]*\}' \
    'No ${v^^} / ${v,,} case modification (Bash 4.0)'

start_test_case "bc_06_no_globstar"
assert_absent 'shopt[[:space:]]+-s[[:space:]]+globstar' \
    "No globstar (Bash 4.0)"

start_test_case "bc_07_no_declare_g"
assert_absent '(declare|typeset)[[:space:]]+-[A-Za-z]*g([[:space:]]|$)' \
    "No declare -g (Bash 4.2)"

start_test_case "bc_08_no_v_test"
assert_absent '\[\[[^]]*[[:space:]]-v[[:space:]]' \
    "No [[ -v var ]] (Bash 4.2)"

start_test_case "bc_09_no_namerefs"
assert_absent '(declare|local|typeset)[[:space:]]+-[A-Za-z]*n([[:space:]]|$)' \
    "No namerefs (local -n — Bash 4.3)"

start_test_case "bc_10_no_negative_index_or_wait_n"
assert_absent '\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]|(^|[^[:alnum:]_])wait[[:space:]]+-n([[:space:]]|$)' \
    "No negative array index / wait -n (Bash 4.3)"

# ---------------------------------------------------------------------------
# BC_11 — set -u is a RUNTIME trap on 3.2, not a syntax error.
#   bash 3.2: set -u; a=(); echo "${a[@]}"  -> unbound variable
#   bash 4.4: same code                     -> expands to nothing
# Banned in the runtime (bin/ lib/ hooks/). Entry-point scripts that are not
# sourced (install.sh, build.sh, scripts/) may use it, but must expand
# possibly-empty arrays as ${a[@]+"${a[@]}"}.
# ---------------------------------------------------------------------------
start_test_case "bc_11_no_set_u_in_runtime"
runtime_set_u=""
for f in bin/* lib/*.sh hooks/*; do
    [ -f "$f" ] || continue
    hit="$(grep -nE '^[[:space:]]*set[[:space:]]+[-+][a-zA-Z]*u' "$f" 2>/dev/null)"
    [ -n "$hit" ] && runtime_set_u="$runtime_set_u$f: $hit"$'\n'
done
if [ -z "$runtime_set_u" ]; then
    assert_success 0 "No 'set -u' in bin/ lib/ hooks/ (unsafe on Bash 3.2 — see CONTRIBUTING.md)"
else
    test_log "${RED}     offending lines:${NC}"; echo "$runtime_set_u" | sed 's/^/       /'
    assert_success 1 "No 'set -u' in bin/ lib/ hooks/"
fi

# ---------------------------------------------------------------------------
# BC_12 — CRLF line endings break bash everywhere ("bad interpreter: ^M").
# Windows checkouts produce these unless .gitattributes forces eol=lf.
# ---------------------------------------------------------------------------
start_test_case "bc_12_no_crlf_line_endings"
crlf_files=""
for f in $SHELL_FILES; do
    if LC_ALL=C grep -q "$(printf '\r')" "$f" 2>/dev/null; then
        crlf_files="$crlf_files  $f"$'\n'
    fi
done
if [ -z "$crlf_files" ]; then
    assert_success 0 "All shell files use LF line endings (Windows/Git Bash safe)"
else
    test_log "${RED}     CRLF found in:${NC}"; echo "$crlf_files"
    assert_success 1 "All shell files use LF line endings"
fi

start_test_case "bc_13_gitattributes_forces_lf"
[ -f "$PROJECT_ROOT/.gitattributes" ] && grep -qE 'eol=lf' "$PROJECT_ROOT/.gitattributes"
assert_success "$?" ".gitattributes pins eol=lf (protects Windows checkouts)"

# ---------------------------------------------------------------------------
# BC_14 — Executable bits must be correct in the GIT INDEX, not just on disk.
# Windows cannot represent the bit in the filesystem, so the index is the
# only portable source of truth. Without it, `exec`-ing a subcommand fails
# with "Permission denied" for anyone running from a clone.
# ---------------------------------------------------------------------------
start_test_case "bc_14_exec_bits_in_git_index"
if git rev-parse --git-dir >/dev/null 2>&1; then
    not_exec="$(git ls-files -s bin hooks 2>/dev/null | awk '$1!="100755"{print "  "$1"  "$4}')"
    if [ -z "$not_exec" ]; then
        assert_success 0 "All bin/ and hooks/ files are mode 100755 in the git index"
    else
        test_log "${RED}     not executable in index:${NC}"; echo "$not_exec"
        assert_success 1 "All bin/ and hooks/ files are mode 100755 in the git index"
    fi
else
    test_log "  ⏭️  SKIP: not a git checkout (running from a release tarball)"
fi

# ---------------------------------------------------------------------------
# BC_15 — every shipped script needs a shebang (Windows has no binfmt fallback)
# ---------------------------------------------------------------------------
start_test_case "bc_15_shebang_present"
missing_shebang=""
for f in bin/* hooks/*; do
    [ -f "$f" ] || continue
    head -n 1 "$f" | grep -qE '^#!' || missing_shebang="$missing_shebang  $f"$'\n'
done
if [ -z "$missing_shebang" ]; then
    assert_success 0 "Every bin/ and hooks/ file starts with a shebang"
else
    test_log "${RED}     missing shebang:${NC}"; echo "$missing_shebang"
    assert_success 1 "Every bin/ and hooks/ file starts with a shebang"
fi

print_summary
