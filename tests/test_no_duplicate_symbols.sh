#!/bin/bash
# tests/test_no_duplicate_symbols.sh
# Guards against two libraries defining the same function name.
#
# lib/ files are SOURCED into one shell, and several of them cross-source each
# other at runtime (check_hotfix_impact pulls in sync-from-staging.sh,
# check_staging_synchronization pulls in sync-from-production.sh). When two libs
# define the same name, whichever loads last silently wins.
#
# That was not hypothetical: sync-from-staging.sh and sync-from-production.sh
# both defined show_detection_analysis with DIFFERENT parameter orders, and
# staging.sh and production.sh shared seven more names between them.
#
# bin/ scripts are separate PROCESSES, so `main` and `parse_arguments` repeating
# across them is correct and expected — only lib/ is checked for collisions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

start_suite "Library Symbol Uniqueness"

# ---------------------------------------------------------------------------
# DS_01 — no function name defined by two different lib/ files
# ---------------------------------------------------------------------------
start_test_case "ds_01_no_cross_library_duplicates"

collisions=""
# Emit "name<TAB>file" for every top-level function definition in lib/
pairs=$(for f in lib/*.sh; do
            grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$f" 2>/dev/null \
                | sed 's/()//' | sort -u | sed "s|\$|	$f|"
        done)

# Group by name; report any defined in more than one file.
collisions=$(printf '%s\n' "$pairs" | awk -F'\t' '
    { files[$1] = files[$1] " " $2; count[$1]++ }
    END { for (k in count) if (count[k] > 1) printf "  %s ->%s\n", k, files[k] }
' | sort)

if [ -z "$collisions" ]; then
    assert_success 0 "No function name is defined by two different lib/ files"
else
    test_log "${RED}     colliding symbols:${NC}"
    printf '%s\n' "$collisions"
    assert_success 1 "No function name is defined by two different lib/ files"
fi

# ---------------------------------------------------------------------------
# DS_02 — no function defined twice within a single file
# ---------------------------------------------------------------------------
start_test_case "ds_02_no_duplicates_within_a_file"

dupes_in_file=""
for f in lib/*.sh bin/git-trident* hooks/*; do
    [ -f "$f" ] || continue
    d=$(grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$f" 2>/dev/null | sed 's/()//' | sort | uniq -d)
    if [ -n "$d" ]; then
        dupes_in_file="$dupes_in_file  $f: $(printf '%s' "$d" | tr '\n' ' ')"$'\n'
    fi
done

if [ -z "$dupes_in_file" ]; then
    assert_success 0 "No function is defined twice within the same file"
else
    test_log "${RED}     duplicates:${NC}"; printf '%s' "$dupes_in_file"
    assert_success 1 "No function is defined twice within the same file"
fi

# ---------------------------------------------------------------------------
# DS_03 — the two sync libraries can be loaded together safely
# ---------------------------------------------------------------------------
# This is the concrete failure the rename prevents: both files get sourced into
# one shell by verify-sync, so a shared name means one implementation is lost.
start_test_case "ds_03_sync_libraries_coexist"

both=$(
    { grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' lib/git-trident-staging-sync-from-staging.sh | sed 's/()//' | sort -u
      grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' lib/git-trident-staging-sync-from-production.sh | sed 's/()//' | sort -u
    } | sort | uniq -d
)
[ -z "$both" ]
assert_success "$?" "sync-from-staging and sync-from-production share no symbols"
[ -n "$both" ] && printf '%s\n' "$both" | sed 's/^/       /'

# ---------------------------------------------------------------------------
# DS_04 — staging and production release libraries likewise
# ---------------------------------------------------------------------------
start_test_case "ds_04_release_libraries_coexist"

both=$(
    { grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' lib/git-trident-staging.sh | sed 's/()//' | sort -u
      grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' lib/git-trident-production.sh | sed 's/()//' | sort -u
    } | sort | uniq -d
)
[ -z "$both" ]
assert_success "$?" "staging.sh and production.sh share no symbols"
[ -n "$both" ] && printf '%s\n' "$both" | sed 's/^/       /'

print_summary
