#!/usr/bin/env bash
# Minimal test harness. No bats, no npm, no pip: the things under test are shell
# scripts that have to run on a bare Git Bash install, and the tests must run in
# the same places.
#
# A test file is a plain script that sources this and calls `check <name> <cmd…>`
# or uses the assertions below. Failures accumulate; the file exits non-zero if
# any failed.

set -uo pipefail

T_PASS=0
T_FAIL=0
T_NAME="$(basename "${BASH_SOURCE[1]:-tests}" .sh)"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

t_pass() { T_PASS=$((T_PASS + 1)); printf '    ok    %s\n' "$1"; }
t_fail() { T_FAIL=$((T_FAIL + 1)); printf '    FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '          %s\n' "$2"; return 0; }

assert_eq() { # assert_eq NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then t_pass "$1"; else t_fail "$1" "expected [$2], got [$3]"; fi
}

assert_ne() {
  if [ "$2" != "$3" ]; then t_pass "$1"; else t_fail "$1" "expected something other than [$2]"; fi
}

assert_contains() { # assert_contains NAME HAYSTACK NEEDLE
  case "$2" in *"$3"*) t_pass "$1" ;; *) t_fail "$1" "output does not contain [$3]" ;; esac
}

assert_not_contains() {
  case "$2" in *"$3"*) t_fail "$1" "output unexpectedly contains [$3]" ;; *) t_pass "$1" ;; esac
}

assert_file_exists()  { if [ -f "$2" ]; then t_pass "$1"; else t_fail "$1" "missing file $2"; fi; }
assert_file_absent()  { if [ ! -e "$2" ]; then t_pass "$1"; else t_fail "$1" "$2 still exists"; fi; }
assert_dir_exists()   { if [ -d "$2" ]; then t_pass "$1"; else t_fail "$1" "missing directory $2"; fi; }

# assert_same_file NAME A B — byte-for-byte equality.
assert_same_file() {
  if cmp -s "$2" "$3"; then t_pass "$1"; else t_fail "$1" "$(diff -u "$2" "$3" 2>&1 | head -10)"; fi
}

# Fingerprint of a whole tree: every path plus the hash of every file. Used to
# prove a dry run changed nothing at all — not just that the files it names are
# unchanged.
tree_fingerprint() {
  ( cd "$1" 2>/dev/null || return 0
    find . -print | LC_ALL=C sort
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum 2>/dev/null
  ) | sha256sum | cut -d' ' -f1
}

# A throwaway $AGENT_HOME. Printed on stdout, removed by t_cleanup.
T_SANDBOXES=""
sandbox_new() {
  _d="$(mktemp -d)"
  T_SANDBOXES="$T_SANDBOXES$_d
"
  printf '%s\n' "$_d"
}

t_cleanup() {
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    chmod -R u+w "$d" 2>/dev/null
    rm -rf "$d" 2>/dev/null
  done <<EOF
$T_SANDBOXES
EOF
}

t_summary() {
  printf '  %s: %d passed, %d failed\n' "$T_NAME" "$T_PASS" "$T_FAIL"
  t_cleanup
  [ "$T_FAIL" -eq 0 ]
}
