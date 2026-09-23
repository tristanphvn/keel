#!/usr/bin/env bash
# Shared helpers for the installer, the uninstaller and the runtime adapters.
# Sourced, never executed. Every function is prefixed `as_` so a script that
# sources this cannot have its own names shadowed.
#
# Nothing here writes outside a caller-supplied path, and nothing here assumes
# GNU-only tools beyond what as_preflight verifies first.

# --- diagnostics -------------------------------------------------------------

as_die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
as_warn() { printf 'warning: %s\n' "$*" >&2; }

# --- dependency preflight ----------------------------------------------------

# as_preflight cmd...
# Verifies every named command exists before the caller writes anything.
# Returns 1 and prints the full missing list, rather than failing halfway
# through an install on the first tool that turns out to be absent.
as_preflight() {
  _missing=""
  for _c in "$@"; do
    command -v "$_c" >/dev/null 2>&1 || _missing="$_missing $_c"
  done
  [ -z "$_missing" ] && return 0
  printf 'FATAL: missing required command(s):%s\n' "$_missing" >&2
  printf 'Install them (Git Bash / coreutils on Windows, coreutils+diffutils on Linux) and re-run.\n' >&2
  return 1
}

# --- paths -------------------------------------------------------------------

# as_realpath PATH
# Physical, symlink-resolved absolute path. Falls back through realpath,
# readlink -f, then a pure-shell `cd -P`, so it works on hosts where GNU
# coreutils is absent. A non-existent leaf is resolved against its parent.
as_realpath() {
  _p="$1"
  if command -v realpath >/dev/null 2>&1; then realpath "$_p" 2>/dev/null && return 0; fi
  if readlink -f "$_p" >/dev/null 2>&1; then readlink -f "$_p" && return 0; fi
  if [ -d "$_p" ]; then (cd "$_p" 2>/dev/null && pwd -P) && return 0; fi
  _d="$(dirname "$_p")"; _b="$(basename "$_p")"
  if [ -d "$_d" ]; then printf '%s/%s\n' "$(cd "$_d" && pwd -P)" "$_b"; return 0; fi
  printf '%s\n' "$_p"
}

# as_canon_path PATH — the comparison form of a path.
#
# Resolving is not enough on MSYS: one directory resolves to /tmp/app/x through
# a junction and to its drive-rooted spelling directly, because /tmp is a mount
# alias. cygpath -m maps both onto a single Windows spelling, and Windows paths
# are case-insensitive, so the comparison form is lowercased there — never on a
# POSIX host, where case is significant.
as_canon_path() {
  _r="$(as_realpath "$1")"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$_r" 2>/dev/null | tr '[:upper:]' '[:lower:]' || printf '%s\n' "$_r"
  else
    printf '%s\n' "$_r"
  fi
}

# as_same_path A B — true when both resolve to the same physical location.
as_same_path() {
  [ "$(as_canon_path "$1")" = "$(as_canon_path "$2")" ]
}

# as_sed_replacement TEXT
# Escape TEXT for use as the replacement half of `sed s|…|TEXT|`: backslash,
# the delimiter, and & (which sed expands to the whole match).
as_sed_replacement() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# as_is_within PARENT CHILD — true when CHILD resolves inside PARENT.
# Used to refuse writes that a symlink would redirect outside $AGENT_HOME.
as_is_within() {
  _parent="$(as_realpath "$1")"; _child="$(as_realpath "$2")"
  case "$_child" in
    "$_parent") return 0 ;;
    "$_parent"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- hashing -----------------------------------------------------------------

# as_sha256 FILE — hex digest only. Empty output means no usable hasher.
as_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum  >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" 2>/dev/null | sed 's/.*= //'
  fi
}

# --- link capability ---------------------------------------------------------

# as_link_support DIR
# Prints the strongest directory-linking mechanism that actually works in DIR:
#
#   symlink   POSIX symlink; ln -s produced a real link
#   junction  Windows directory junction via mklink /J (no privilege needed)
#   none      neither — the caller must fall back to a direct install
#
# This is measured, not assumed. On Windows without Developer Mode, MSYS `ln -s`
# silently DEEP-COPIES the target instead of failing, so a bare `ln -s` exit code
# proves nothing; the probe checks that the result is a link.
as_link_support() {
  _dir="$1"
  [ -d "$_dir" ] || return 1
  _probe="$_dir/.as-linkprobe.$$"
  _target="$_dir/.as-linktarget.$$"
  rm -rf "$_probe" "$_target" 2>/dev/null
  mkdir -p "$_target" 2>/dev/null || { printf 'none\n'; return 0; }

  if ln -s "$_target" "$_probe" 2>/dev/null && [ -L "$_probe" ]; then
    rm -rf "$_probe" "$_target" 2>/dev/null
    printf 'symlink\n'; return 0
  fi
  # ln -s may have left a copy behind; clear it before the next attempt.
  rm -rf "$_probe" 2>/dev/null

  if command -v cygpath >/dev/null 2>&1 && command -v cmd >/dev/null 2>&1; then
    if cmd //c mklink //J "$(cygpath -w "$_probe")" "$(cygpath -w "$_target")" >/dev/null 2>&1 \
       && [ -L "$_probe" ]; then
      rm -rf "$_probe" "$_target" 2>/dev/null
      printf 'junction\n'; return 0
    fi
    rm -rf "$_probe" 2>/dev/null
  fi

  rm -rf "$_target" 2>/dev/null
  printf 'none\n'
}

# as_make_link MECHANISM TARGET LINK — create one directory link. Non-zero on failure.
as_make_link() {
  case "$1" in
    symlink)  ln -s "$2" "$3" 2>/dev/null && [ -L "$3" ] ;;
    junction) cmd //c mklink //J "$(cygpath -w "$3")" "$(cygpath -w "$2")" >/dev/null 2>&1 && [ -L "$3" ] ;;
    *) return 1 ;;
  esac
}

# as_link_points_at LINK TARGET
# True when LINK is a link that resolves to TARGET. Compares resolved physical
# paths, because readlink output is not comparable across path spellings: on
# MSYS a junction created with a drive-rooted path reads back through the
# /tmp mount alias.
as_link_points_at() {
  [ -L "$1" ] || return 1
  as_same_path "$1" "$2"
}
