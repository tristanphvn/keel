#!/usr/bin/env bash
# Codex CLI adapter: make the shared configuration visible to Codex.
# Run AFTER scripts/install.sh.
#
#   AGENT_HOME=~/.agent bash scripts/adapters/codex.sh                  # dry run
#   AGENT_HOME=~/.agent bash scripts/adapters/codex.sh --apply          # writes, after backing up
#   AGENT_HOME=~/.agent bash scripts/adapters/codex.sh --check          # verify an existing install
#   AGENT_HOME=~/.agent bash scripts/adapters/codex.sh --remove         # take the managed block back out
#   AGENT_HOME=~/.agent bash scripts/adapters/codex.sh --link-skills    # expose skills at Codex's skills path
#   AGENT_HOME=~/.agent bash scripts/adapters/codex.sh --print-config   # TOML to paste into config.toml
#
# Why this adapter cannot simply point Codex at config/AGENTS.md:
#
#   * Codex reads global instructions from $CODEX_HOME/AGENTS.md, concatenating
#     it with the project AGENTS.md chain. No import/include mechanism is
#     documented, so the `@.../rules/*.md` lines in the shared entrypoint would
#     arrive as literal text and the rules would never load. This adapter
#     therefore MATERIALISES the rule bodies into the managed block.
#   * Codex discovers skills at $HOME/.agents/skills, not under its own config
#     directory, so the skills tree is linked there rather than copied.
#   * The combined instruction budget is capped by `project_doc_max_bytes`
#     (32 KiB by default). This adapter measures the block against that budget
#     and refuses to write past it rather than letting Codex silently truncate.
#
# Sources for the above are recorded in docs/runtime-capabilities.md, with the
# verification status of each line. The Codex CLI is not installed on the
# machine where this adapter was written, so its runtime behaviour is
# DOCUMENTED-NOT-MEASURED; the file states that explicitly.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/scripts/lib/common.sh"
# shellcheck source=../lib/links.sh
. "$ROOT/scripts/lib/links.sh"

as_preflight sed awk grep find cmp cp mv rm mkdir mktemp date basename dirname wc || exit 1

DEST="${AGENT_HOME:-$HOME/.agent}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
# Codex's documented user-scope skills root. Deliberately not under CODEX_HOME.
CODEX_SKILLS_VIEW="${CODEX_SKILLS_DIR:-$HOME/.agents/skills}"
SKILLS_SRC="${AGENT_SKILLS_DIR:-$DEST/skills}"
TARGET="$CODEX_HOME/AGENTS.md"
MANIFEST="${CODEX_LINKS_MANIFEST:-$CODEX_HOME/.agent-skills-links.manifest}"
# Mirror of Codex's own project_doc_max_bytes default; override if you raised it.
DOC_MAX_BYTES="${CODEX_DOC_MAX_BYTES:-32768}"

BEGIN='<!-- agent-skills:begin -->'
END='<!-- agent-skills:end -->'

APPLY=0
ACTION=install
for arg in "$@"; do
  case "$arg" in
    --apply)         APPLY=1 ;;
    --check)         ACTION=check ;;
    --remove)        ACTION=remove ;;
    --link-skills)   ACTION=link ;;
    --unlink-skills) ACTION=unlink ;;
    --print-config)  ACTION=printconfig ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

# --- the managed block -------------------------------------------------------
# Rule bodies are copied in verbatim, in filename order, under their own
# heading. The rules stay the single source: this block is generated output and
# is regenerated wholesale on every run.
render_block() {
  printf '%s\n' "$BEGIN"
  cat <<'HDR'
# Global rules (agent-skills)

Generated block — do not edit here. Edit the rule files in the agent-skills repo
and re-run `scripts/adapters/codex.sh --apply`. Everything outside the markers is
yours and is never touched.

HDR
  for f in "$DEST"/rules/*.md; do
    [ -f "$f" ] || continue
    printf '<!-- source: rules/%s -->\n' "$(basename "$f")"
    cat "$f"
    printf '\n'
  done
  cat <<HDR
Skill inventory and lifecycle: $DEST/skill-registry/registry.yaml
Skills are discovered by Codex at $CODEX_SKILLS_VIEW/<name>/SKILL.md
HDR
  printf '%s\n' "$END"
}

echo "shared config: $DEST"
echo "codex home:    $CODEX_HOME"
echo "skills view:   $CODEX_SKILLS_VIEW"
case "$ACTION" in
  check)       echo "mode:          check" ;;
  printconfig) echo "mode:          print config" ;;
  *) [ "$APPLY" -eq 1 ] && echo "mode:          $ACTION (apply)" || echo "mode:          $ACTION (dry run — pass --apply to write)" ;;
esac
echo

# --- print-config ------------------------------------------------------------
# config.toml is NOT written automatically. Appending to a TOML file is not
# safe in general: a bare key appended after the user's last table header would
# silently join that table, and a duplicate [agents] header is a parse error.
# So the adapter prints, and the user pastes.
if [ "$ACTION" = printconfig ]; then
  cat <<TOML
# --- agent-skills: paste into $CODEX_HOME/config.toml ---
# Table headers only. If you already define [agents], merge the keys by hand
# rather than pasting a second [agents] header — TOML rejects duplicates.

[agents]
enabled = true

# Role-to-model routing is generated from config/routing/models.yaml by
# scripts/routing/render.sh; it writes one file per role into
# $CODEX_HOME/agents/. Nothing in this snippet is required for that.
TOML
  exit 0
fi

# --- check -------------------------------------------------------------------
if [ "$ACTION" = check ]; then
  echo "== Codex integration =="
  if [ -d "$CODEX_HOME" ]; then ok "$CODEX_HOME exists"; else bad "$CODEX_HOME missing — is the Codex CLI installed?"; fi

  if [ -f "$TARGET" ]; then
    if grep -qF "$BEGIN" "$TARGET"; then ok "managed block present in $TARGET"; else bad "managed block absent from $TARGET"; fi
    size=$(wc -c < "$TARGET" | tr -d ' ')
    if [ "$size" -le "$DOC_MAX_BYTES" ]; then
      ok "$TARGET is ${size}B, within the ${DOC_MAX_BYTES}B project_doc_max_bytes budget"
    else
      bad "$TARGET is ${size}B, over the ${DOC_MAX_BYTES}B budget — Codex will truncate"
    fi
    if grep -qE '^@' "$TARGET"; then
      bad "$TARGET contains @import lines; Codex does not expand them (they load as literal text)"
    else
      ok "no unexpandable @import lines"
    fi
  else
    bad "$TARGET does not exist"
  fi

  n_flat=$(find -L "$CODEX_SKILLS_VIEW" -maxdepth 2 -name SKILL.md 2>/dev/null | grep -c . || true)
  [ "${n_flat:-0}" -gt 0 ] && ok "$n_flat skill(s) visible at $CODEX_SKILLS_VIEW/<name>/SKILL.md" \
                           || bad "no skills at $CODEX_SKILLS_VIEW — run --link-skills --apply"

  if [ -f "$MANIFEST" ]; then
    as_links_check "$MANIFEST" || fail=$((fail + $?))
    [ "${AS_LINKS_OK:-0}" -gt 0 ] && ok "${AS_LINKS_OK} managed link(s) resolve to a readable SKILL.md"
  fi

  leftover=$(grep -rlF '{{AGENT_HOME}}' "$TARGET" 2>/dev/null | grep -c . || true)
  [ "${leftover:-0}" -eq 0 ] && ok "no unresolved {{AGENT_HOME}} placeholders" \
                             || bad "$TARGET still contains {{AGENT_HOME}}"

  echo
  [ "$fail" -eq 0 ] && { echo "ADAPTER CHECK: PASS"; exit 0; } || { echo "ADAPTER CHECK: FAIL ($fail problem(s))"; exit "$fail"; }
fi

# --- skills links ------------------------------------------------------------
if [ "$ACTION" = link ]; then
  [ -d "$SKILLS_SRC" ] || { echo "FATAL: $SKILLS_SRC does not exist — run scripts/install.sh --apply first" >&2; exit 1; }
  if as_same_path "$SKILLS_SRC" "$CODEX_SKILLS_VIEW"; then
    echo "  skills are already installed at $CODEX_SKILLS_VIEW; nothing to link."
    exit 0
  fi
  echo "  source: $SKILLS_SRC"
  echo
  as_links_link "$SKILLS_SRC" "$CODEX_SKILLS_VIEW" "$MANIFEST" "$APPLY" || {
    echo; echo "collision(s) — nothing was overwritten." >&2; exit 1; }
  echo
  [ "$APPLY" -eq 1 ] && echo "Linked. Restart Codex, then: bash scripts/adapters/codex.sh --check" \
                     || echo "Nothing written. Re-run with --apply to create the links."
  exit 0
fi

if [ "$ACTION" = unlink ]; then
  as_links_unlink "$MANIFEST" "$APPLY"
  echo
  [ "$APPLY" -eq 1 ] && echo "Removed ${AS_LINKS_REMOVED:-0} link(s)." \
                     || echo "Nothing written. Re-run with --apply to remove."
  exit 0
fi

# --- managed block in AGENTS.md ----------------------------------------------
[ -d "$DEST/rules" ] || { echo "FATAL: $DEST/rules missing — run scripts/install.sh --apply first" >&2; exit 1; }

if [ ! -f "$TARGET" ]; then
  echo "  $TARGET does not exist yet; it will be created with the managed block only."
  existing=""
else
  existing="$(cat "$TARGET")"
fi

has_block=0
printf '%s\n' "$existing" | grep -qF "$BEGIN" && has_block=1

tmp="$(mktemp)"; blk="$tmp.blk"; trap 'rm -f "$tmp" "$blk"' EXIT

if [ "$ACTION" = remove ]; then
  if [ "$has_block" -eq 0 ]; then
    echo "  managed block not present; nothing to remove."
    exit 0
  fi
  printf '%s\n' "$existing" | awk -v b="$BEGIN" -v e="$END" '
    index($0,b) {skip=1; next} index($0,e) {skip=0; next} !skip {print}' > "$tmp"
  # Collapse the blank run the block leaves behind, then drop trailing blanks,
  # so removal restores the user's file byte-for-byte.
  awk 'BEGIN{n=0} /^$/{n++; if(n>1) next} !/^$/{n=0} {print}' "$tmp" > "$blk" && mv "$blk" "$tmp"
  awk 'NF {last=NR} {line[NR]=$0} END {for (i=1; i<=last; i++) print line[i]}' "$tmp" > "$blk" && mv "$blk" "$tmp"
  action="REMOVE block from"
else
  render_block > "$blk"
  if [ "$has_block" -eq 1 ]; then
    printf '%s\n' "$existing" | awk -v b="$BEGIN" -v e="$END" -v f="$blk" '
      index($0,b) {skip=1; while ((getline line < f) > 0) print line; close(f); next}
      index($0,e) {skip=0; next}
      !skip {print}' > "$tmp"
    action="UPDATE block in"
  else
    { [ -n "$existing" ] && { printf '%s\n' "$existing"; echo; }; cat "$blk"; } > "$tmp"
    action="APPEND block to"
  fi

  # Codex truncates the instruction chain at project_doc_max_bytes. Writing a
  # file that exceeds it would silently drop whatever falls past the limit —
  # possibly half a rule — so refuse instead, and say what to do.
  newsize=$(wc -c < "$tmp" | tr -d ' ')
  if [ "$newsize" -gt "$DOC_MAX_BYTES" ]; then
    cat >&2 <<MSG
FATAL: the result would be ${newsize}B, over the ${DOC_MAX_BYTES}B that Codex reads
       from the instruction chain (project_doc_max_bytes). Codex would truncate
       it silently, cutting the block off mid-rule.

Supported options:
  * raise the budget in $CODEX_HOME/config.toml:  project_doc_max_bytes = $((newsize + 4096))
    then re-run with CODEX_DOC_MAX_BYTES=$((newsize + 4096))
  * or shrink what is installed in $DEST/rules

Nothing was written.
MSG
    exit 1
  fi
fi

if cmp -s "$tmp" "$TARGET" 2>/dev/null; then
  echo "  unchanged: $TARGET already matches (idempotent)."
  echo
  echo "Nothing to do."
  exit 0
fi

echo "  $action $TARGET"
if [ "$APPLY" -ne 1 ]; then
  echo
  echo "--- proposed diff ---"
  diff -u "$TARGET" "$tmp" 2>/dev/null | sed 's/^/  /' || true
  echo
  echo "Nothing written. Re-run with --apply to write."
  exit 0
fi

mkdir -p "$CODEX_HOME" || as_die "cannot create $CODEX_HOME"
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$CODEX_HOME/backups/codex-adapter-$stamp"
mkdir -p "$backup" || as_die "cannot create $backup"
if [ -f "$TARGET" ]; then
  cp -p "$TARGET" "$backup/AGENTS.md" || as_die "backup failed"
  cmp -s "$TARGET" "$backup/AGENTS.md" || as_die "backup did not verify"
  echo "  backup:  $backup/AGENTS.md (verified)"
fi

# mktemp creates 0600; moving it in would silently tighten the file's mode.
mode=""
[ -f "$TARGET" ] && mode="$(stat -f '%Lp' "$TARGET" 2>/dev/null || stat -c '%a' "$TARGET" 2>/dev/null)"
mv -f "$tmp" "$TARGET" || as_die "write failed"
if [ -n "$mode" ]; then
  chmod "$mode" "$TARGET" || as_warn "could not restore mode $mode on $TARGET"
else
  chmod 644 "$TARGET" 2>/dev/null || true
fi
trap - EXIT; rm -f "$blk"
echo "  written: $TARGET ($(wc -c < "$TARGET" | tr -d ' ')B of ${DOC_MAX_BYTES}B budget)"
echo
echo "Applied. Restart Codex, then: bash scripts/adapters/codex.sh --check"
