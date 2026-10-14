#!/bin/bash
# Git Trident Tag Grammar
#
# Single place that owns how tag names are COMPOSED and MATCHED.
#
# The prefixes and the RC suffix are user-configurable (STAGING_TAG_PREFIX,
# PRODUCTION_TAG_PREFIX, STAGING_TAG_SUFFIX), and they were being interpolated
# raw into `[[ =~ ]]` patterns in roughly eight places. Any value containing a
# regex metacharacter therefore matched the wrong things — a suffix of ".rc."
# matches "Xrc1" as happily as ".rc.", because "." means "any character":
#
#     suffix=".rc."
#     [[ "1.2.3Xrc1" =~ .*${suffix}[0-9]+$ ]]   # true — wrong
#     [[ "1.2.3Xrc1" =~ .*\.rc\.[0-9]+$ ]]      # false — correct
#
# Globs passed to `git tag -l` have the opposite requirement: they must NOT be
# regex-escaped, since git uses fnmatch. Keeping both forms here makes the
# distinction explicit instead of accidental.

# Escape a literal string for use inside a POSIX ERE / bash [[ =~ ]] pattern.
#
# Replacement is '\\&' (sed receives two characters: a backslash, then '&'),
# producing ONE backslash before the matched character. Writing '\\\\&' here
# would emit two backslashes, which matches a literal backslash instead.
gt_regex_escape() {
    printf '%s' "$1" | sed 's/[].[^$(){}*+?|\\]/\\&/g'
}

# Escape a literal string for use in a sed BRE, with '#' as the delimiter.
# BRE treats ( ) { } + ? | as ordinary, so only . * [ ] ^ $ \ and the delimiter
# need escaping. Over-escaping in a BRE turns ordinary characters into
# operators, so the two escapers cannot be shared.
gt_bre_escape() {
    printf '%s' "$1" | sed 's/[].[^$*\\#]/\\&/g'
}

# The configured RC suffix, defaulting to "-rc-".
gt_rc_suffix() {
    printf '%s' "${STAGING_TAG_SUFFIX:--rc-}"
}

# ---------------------------------------------------------------------------
# Composition (literal text — for creating tags and for `git tag -l` globs)
# ---------------------------------------------------------------------------

# gt_tag_staging <version> <rc_number>   ->  staging/1.2.3-rc-01
gt_tag_staging() {
    printf '%s%s%s%s' "$STAGING_TAG_PREFIX" "$1" "$(gt_rc_suffix)" "$2"
}

# gt_tag_production <version>            ->  production/1.2.3
gt_tag_production() {
    printf '%s%s' "$PRODUCTION_TAG_PREFIX" "$1"
}

# gt_glob_staging_rcs <version>          ->  staging/1.2.3-rc-*
gt_glob_staging_rcs() {
    printf '%s%s%s*' "$STAGING_TAG_PREFIX" "$1" "$(gt_rc_suffix)"
}

# ---------------------------------------------------------------------------
# Matching (regex — every metacharacter in the configured values escaped)
# ---------------------------------------------------------------------------

# Anchored pattern matching "<anything><suffix><digits>" — used to pull the RC
# number off a tag or version string.
gt_re_rc_tail() {
    printf '.*%s([0-9][0-9]*)$' "$(gt_regex_escape "$(gt_rc_suffix)")"
}

# Optional RC part, for validating a version that may or may not carry one.
gt_re_rc_optional() {
    printf '(%s[0-9]+)?' "$(gt_regex_escape "$(gt_rc_suffix)")"
}

# sed expression that strips a trailing RC suffix + number.
gt_sed_strip_rc() {
    printf 's#%s[0-9]*$##' "$(gt_bre_escape "$(gt_rc_suffix)")"
}

# sed expression that strips a leading tag prefix.
gt_sed_strip_prefix() {
    printf 's#^%s##' "$(gt_bre_escape "$1")"
}
