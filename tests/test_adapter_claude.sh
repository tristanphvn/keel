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
assert_contains "block is rendered, not tokenised" "$(cat "$H/CLAUDE.md")" "$H/rules"
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
