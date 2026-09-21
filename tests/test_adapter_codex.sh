#!/usr/bin/env bash
# Codex adapter: managed block, materialised rules, and the instruction budget.
#
# These test what the adapter WRITES. They do not test that Codex reads it —
# the Codex CLI is not installed here, and no shell test can stand in for that.
# See docs/runtime-capabilities.md for what is measured versus documented.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

INSTALL="bash $REPO_ROOT/scripts/install.sh"
ADAPTER="bash $REPO_ROOT/scripts/adapters/codex.sh"

USER_TEXT='# my codex notes

project preferences I wrote myself
'

H="$(sandbox_new)"          # shared config home
C="$(sandbox_new)/codex"    # CODEX_HOME
mkdir -p "$C"
printf '%s' "$USER_TEXT" > "$C/AGENTS.md"
orig="$(sandbox_new)/AGENTS.md.orig"; printf '%s' "$USER_TEXT" > "$orig"
AGENT_HOME="$H" $INSTALL --apply >/dev/null 2>&1

run() { AGENT_HOME="$H" CODEX_HOME="$C" CODEX_SKILLS_DIR="$C/skills-view" $ADAPTER "$@"; }

# --- dry run -----------------------------------------------------------------
before="$(tree_fingerprint "$C")"
out="$(run 2>&1)"; rc=$?
after="$(tree_fingerprint "$C")"
assert_eq "dry run exits 0" 0 "$rc"
assert_eq "dry run mutates nothing" "$before" "$after"

# --- apply -------------------------------------------------------------------
out="$(run --apply 2>&1)"; rc=$?
assert_eq "apply exits 0" 0 "$rc"
body="$(cat "$C/AGENTS.md")"
assert_contains "user content preserved" "$body" "project preferences I wrote myself"
assert_contains "managed block written"  "$body" "agent-skills:begin"

# The point of this adapter: Codex expands no imports, so the rule TEXT has to
# be present. An import line would leave the rules unloaded.
assert_contains "rule bodies are materialised, not imported" "$body" "VERIFY-001"
assert_contains "…for every rule family too" "$body" "CONSENSUS-001"
assert_not_contains "no @import lines" "$body" '@{{AGENT_HOME}}'
assert_not_contains "no unresolved token" "$body" '{{AGENT_HOME}}'
assert_contains "block records its source files" "$body" "source: rules/00-operating-principles.md"

# --- idempotent --------------------------------------------------------------
fp1="$(sha256sum < "$C/AGENTS.md")"
out="$(run --apply 2>&1)"
fp2="$(sha256sum < "$C/AGENTS.md")"
assert_eq "second apply changes nothing" "$fp1" "$fp2"
assert_contains "…and says so" "$out" "idempotent"

# --- check -------------------------------------------------------------------
out="$(run --check 2>&1)"
assert_contains "check confirms the block" "$out" "managed block present"
assert_contains "check reports the budget" "$out" "project_doc_max_bytes budget"

# --- the instruction budget is a hard boundary -------------------------------
# Codex truncates the instruction chain silently at project_doc_max_bytes, which
# would cut the block off mid-rule. The adapter must refuse rather than write.
fp_before="$(sha256sum < "$C/AGENTS.md")"
out="$(AGENT_HOME="$H" CODEX_HOME="$C" CODEX_DOC_MAX_BYTES=2048 $ADAPTER --remove --apply 2>&1)"
out="$(AGENT_HOME="$H" CODEX_HOME="$C" CODEX_DOC_MAX_BYTES=2048 $ADAPTER --apply 2>&1)"; rc=$?
assert_ne "writing past the budget fails" 0 "$rc"
assert_contains "…and explains the limit" "$out" "project_doc_max_bytes"
assert_contains "…and offers a supported option" "$out" "raise the budget"
assert_not_contains "…and the oversized block is not present" "$(cat "$C/AGENTS.md")" "agent-skills:begin"

# --- remove restores the file byte-for-byte ----------------------------------
run --apply >/dev/null 2>&1
out="$(run --remove --apply 2>&1)"; rc=$?
assert_eq "remove exits 0" 0 "$rc"
assert_same_file "remove restores AGENTS.md byte-for-byte" "$C/AGENTS.md" "$orig"

# --- print-config is inert ---------------------------------------------------
before="$(tree_fingerprint "$C")"
out="$(run --print-config 2>&1)"; rc=$?
after="$(tree_fingerprint "$C")"
assert_eq "print-config exits 0" 0 "$rc"
assert_eq "print-config writes nothing" "$before" "$after"
assert_contains "print-config emits a TOML table header" "$out" "[agents]"
assert_contains "…and warns about duplicate tables" "$out" "TOML rejects duplicates"

# --- refuses to run before the shared config is installed --------------------
EMPTY="$(sandbox_new)"
out="$(AGENT_HOME="$EMPTY" CODEX_HOME="$C" $ADAPTER --apply 2>&1)"; rc=$?
assert_ne "refuses when \$AGENT_HOME/rules is missing" 0 "$rc"
assert_contains "…and points at the installer" "$out" "install.sh"

t_summary
