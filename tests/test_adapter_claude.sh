#!/usr/bin/env bash
# Claude Code adapter: managed-block boundaries and the managed-link lifecycle.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

INSTALL="bash $REPO_ROOT/scripts/install.sh"
ADAPTER="bash $REPO_ROOT/scripts/adapters/claude.sh"

USER_TEXT='# my own notes

a line I wrote myself
'

H="$(sandbox_new)"
printf '%s' "$USER_TEXT" > "$H/CLAUDE.md"
orig="$(sandbox_new)/CLAUDE.md.orig"; printf '%s' "$USER_TEXT" > "$orig"
AGENT_HOME="$H" $INSTALL --apply >/dev/null 2>&1

# --- dry run -----------------------------------------------------------------
before="$(tree_fingerprint "$H")"
out="$(AGENT_HOME="$H" $ADAPTER 2>&1)"; rc=$?
after="$(tree_fingerprint "$H")"
assert_eq "dry run exits 0" 0 "$rc"
assert_eq "dry run mutates nothing" "$before" "$after"
assert_contains "dry run shows the diff it would write" "$out" "proposed diff"

# --- apply -------------------------------------------------------------------
out="$(AGENT_HOME="$H" $ADAPTER --apply 2>&1)"; rc=$?
assert_eq "apply exits 0" 0 "$rc"
assert_contains "user content still present" "$(cat "$H/CLAUDE.md")" "a line I wrote myself"
assert_contains "managed block written"      "$(cat "$H/CLAUDE.md")" "agent-skills:begin"
# Rendered in the native spelling install.sh uses (drive-rooted on Windows).
H_NATIVE="$(cygpath -m "$H" 2>/dev/null || printf '%s' "$H")"
assert_contains "block is rendered, not tokenised" "$(cat "$H/CLAUDE.md")" "$H_NATIVE/rules"
assert_not_contains "no unresolved token"    "$(cat "$H/CLAUDE.md")" '{{AGENT_HOME}}'
# Claude Code auto-loads rules/, so importing them here would load each twice.
assert_not_contains "block adds no rule imports" "$(cat "$H/CLAUDE.md")" '@'

# --- idempotent --------------------------------------------------------------
fp1="$(sha256sum < "$H/CLAUDE.md")"
out="$(AGENT_HOME="$H" $ADAPTER --apply 2>&1)"
fp2="$(sha256sum < "$H/CLAUDE.md")"
assert_eq "second apply changes nothing" "$fp1" "$fp2"
assert_contains "…and says so" "$out" "idempotent"

# --- check -------------------------------------------------------------------
out="$(AGENT_HOME="$H" $ADAPTER --check 2>&1)"; rc=$?
assert_eq "check passes on a good install" 0 "$rc"
assert_contains "check confirms the block" "$out" "managed block present"

# --- remove restores the file byte-for-byte ----------------------------------
out="$(AGENT_HOME="$H" $ADAPTER --remove --apply 2>&1)"; rc=$?
assert_eq "remove exits 0" 0 "$rc"
assert_same_file "remove restores CLAUDE.md byte-for-byte" "$H/CLAUDE.md" "$orig"

out="$(AGENT_HOME="$H" $ADAPTER --remove --apply 2>&1)"; rc=$?
assert_eq "remove is safe to repeat" 0 "$rc"
assert_contains "…and says there is nothing to remove" "$out" "nothing to remove"

out="$(AGENT_HOME="$H" $ADAPTER --check 2>&1)"; rc=$?
assert_ne "check fails once the block is gone" 0 "$rc"

# --- a CLAUDE.md that does not exist yet -------------------------------------
H2="$(sandbox_new)"
AGENT_HOME="$H2" $INSTALL --apply >/dev/null 2>&1
rm -f "$H2/CLAUDE.md"
out="$(AGENT_HOME="$H2" $ADAPTER --apply 2>&1)"; rc=$?
assert_eq "creates CLAUDE.md when absent" 0 "$rc"
assert_file_exists "…and the file is there" "$H2/CLAUDE.md"

# --- duplicate rule imports are removed only on request, and only those ------
# Claude Code auto-loads rules/, so `@.../rules/x.md` in CLAUDE.md is a second
# copy. --dedupe-rule-imports drops exactly those lines, whatever spelling the
# user wrote (~/, absolute), and keeps every other line byte for byte.
HD="$(sandbox_new)"
AGENT_HOME="$HD" $INSTALL --apply >/dev/null 2>&1
AGENT_HOME="$HD" $ADAPTER --apply >/dev/null 2>&1
DUP_HOME="$(dirname "$HD")"; DUP_REL="$(basename "$HD")"
{
  printf '# Global instructions\n\n@~/%s/learned-rules.md\n\n## Always-on rules\n\n' "$DUP_REL"
  printf '@~/%s/rules/00-operating-principles.md\n' "$DUP_REL"
  printf '@%s/rules/10-scope-control.md\n' "$HD"
  printf '@%s/rules/99-not-installed.md\n' "$HD"
  printf '@%s/notes/rules/extra.md\n\nmy own line\n\n' "$HD"
  cat "$HD/CLAUDE.md"
} > "$HD/CLAUDE.md.new" && mv "$HD/CLAUDE.md.new" "$HD/CLAUDE.md"
expected="$(grep -v -e '/rules/00-operating-principles.md$' -e '/rules/10-scope-control.md$' "$HD/CLAUDE.md")"

out="$(HOME="$DUP_HOME" AGENT_HOME="$HD" $ADAPTER --check 2>&1)"
assert_contains "check flags the duplicate imports" "$out" "imports rules/ explicitly"
assert_contains "…and names the fix" "$out" "--dedupe-rule-imports"

before="$(tree_fingerprint "$HD")"
out="$(HOME="$DUP_HOME" AGENT_HOME="$HD" $ADAPTER --dedupe-rule-imports 2>&1)"; rc=$?
assert_eq "dedupe dry run exits 0" 0 "$rc"
assert_eq "…mutates nothing" "$before" "$(tree_fingerprint "$HD")"
assert_contains "…lists the ~/ import it would drop" "$out" "drop  @~/$DUP_REL/rules/00-operating-principles.md"
assert_contains "…and the absolute one" "$out" "drop  @$HD/rules/10-scope-control.md"

out="$(HOME="$DUP_HOME" AGENT_HOME="$HD" $ADAPTER --dedupe-rule-imports --apply 2>&1)"; rc=$?
assert_eq "dedupe apply exits 0" 0 "$rc"
assert_eq "…every other line is kept byte for byte" "$expected" "$(cat "$HD/CLAUDE.md")"
assert_contains "…a non-rule import stays" "$(cat "$HD/CLAUDE.md")" "learned-rules.md"
assert_contains "…an import of a file not in rules/ stays" "$(cat "$HD/CLAUDE.md")" "rules/99-not-installed.md"
assert_contains "…an unrelated nested rules/ path stays" "$(cat "$HD/CLAUDE.md")" "notes/rules/extra.md"
assert_contains "…the managed block stays" "$(cat "$HD/CLAUDE.md")" "agent-skills:begin"
bk="$(find "$HD/backups" -maxdepth 2 -path '*claude-adapter-*' -name CLAUDE.md | tail -1)"
assert_contains "…after a verified backup of the original" "$(cat "$bk")" "rules/10-scope-control.md"

out="$(HOME="$DUP_HOME" AGENT_HOME="$HD" $ADAPTER --dedupe-rule-imports --apply 2>&1)"; rc=$?
assert_eq "dedupe is idempotent" 0 "$rc"
assert_contains "…and says there is nothing left" "$out" "nothing to dedupe"
out="$(HOME="$DUP_HOME" AGENT_HOME="$HD" $ADAPTER --check 2>&1)"
assert_contains "check passes the imports afterwards" "$out" "no duplicate rule imports"

# The default action never touches lines outside its markers.
printf '@%s/rules/20-verification.md\n' "$HD" >> "$HD/CLAUDE.md"
AGENT_HOME="$HD" $ADAPTER --apply >/dev/null 2>&1
assert_contains "the plain adapter run leaves imports it did not write" "$(cat "$HD/CLAUDE.md")" "rules/20-verification.md"

# --- managed links -----------------------------------------------------------
# Skipped where the host cannot link at all: that is a supported configuration,
# and the adapter's own fallback path is asserted instead.
HL="$(sandbox_new)"
EXT="$(sandbox_new)/skills-elsewhere"
mkdir -p "$EXT"
AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $INSTALL --apply >/dev/null 2>&1

. "$REPO_ROOT/scripts/lib/common.sh"
mkdir -p "$HL/skills"
MECH="$(as_link_support "$HL/skills")"

if [ "$MECH" = none ]; then
  out="$(AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $ADAPTER --link-skills --apply 2>&1)"; rc=$?
  assert_ne "linking fails loudly on a host without link support" 0 "$rc"
  assert_contains "…and names the supported fallback" "$out" "install the skills where the runtime already looks"
else
  out="$(AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $ADAPTER --link-skills --apply 2>&1)"; rc=$?
  assert_eq "link exits 0" 0 "$rc"
  n_links=0
  for p in "$HL/skills"/*; do [ -L "$p" ] && n_links=$((n_links + 1)); done
  assert_ne "at least one real link was created" 0 "$n_links"
  assert_file_exists "content is readable through the link" "$HL/skills/review-code/SKILL.md"

  out="$(AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $ADAPTER --link-skills --apply 2>&1)"
  assert_contains "re-linking is idempotent" "$out" "already linked"

  out="$(AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $ADAPTER --check 2>&1)"
  assert_not_contains "check sees the links as healthy" "$out" "broken managed link"

  # A user directory occupying the view must never be overwritten.
  AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $ADAPTER --unlink-skills --apply >/dev/null 2>&1
  mkdir -p "$HL/skills/review-code"
  printf 'user content\n' > "$HL/skills/review-code/SKILL.md"
  out="$(AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $ADAPTER --link-skills --apply 2>&1)"; rc=$?
  assert_ne "a collision fails the run" 0 "$rc"
  assert_contains "…and is reported" "$out" "COLLISION"
  assert_eq "…and the user's file is untouched" "user content" "$(cat "$HL/skills/review-code/SKILL.md")"

  # Unlink removes its own links and leaves the user's directory alone.
  out="$(AGENT_HOME="$HL" AGENT_SKILLS_DIR="$EXT" $ADAPTER --unlink-skills --apply 2>&1)"
  assert_eq "user directory survives unlink" "user content" "$(cat "$HL/skills/review-code/SKILL.md")"
  assert_file_exists "source tree survives unlink" "$EXT/review-code/SKILL.md"
fi

t_summary
