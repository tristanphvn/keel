#!/usr/bin/env bash
# Claude Code adapter: integrate the shared configuration with a Claude Code
# config directory (repo -> machine). Run AFTER scripts/install.sh.
#
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh            # dry run
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --apply    # writes, after backing up
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --check    # verify an existing install
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --remove   # take the block back out
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --dedupe-rule-imports  # drop @rules/ imports
#
# Claude Code auto-loads $AGENT_HOME/rules/*.md, so the rules need no imports.
# The only thing this adapter writes is a marker-delimited block inside
# $AGENT_HOME/CLAUDE.md — everything the user wrote there is preserved.
# See config/claude/README.md for the measurements behind that.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT/scripts/lib/common.sh"
# shellcheck source=../lib/links.sh
. "$ROOT/scripts/lib/links.sh"

as_preflight sed awk grep find cmp diff cp mv rm mkdir mktemp date basename dirname || exit 1

# Same native spelling as install.sh, so the rendered block matches what it installed.
DEST="$(as_native_path "${AGENT_HOME:-$HOME/.agent}")"
BLOCK_SRC="$ROOT/config/claude/CLAUDE.md.block"
TARGET="$DEST/CLAUDE.md"
BEGIN='<!-- agent-skills:begin -->'
END='<!-- agent-skills:end -->'

# Where the skills were actually installed (see AGENT_SKILLS_DIR in install.sh),
# and where Claude Code insists on finding them.
SKILLS_SRC="${AGENT_SKILLS_DIR:-$DEST/skills}"
SKILLS_VIEW="$DEST/skills"
# Every link this adapter owns, so an update or removal touches nothing else.
MANIFEST="${AGENT_LINKS_MANIFEST:-$(dirname "$SKILLS_SRC")/links.manifest}"
EXCLUDE_TAG='# agent-skills managed symlinks'

# Flags compose: --remove --apply actually removes; --remove alone previews.
APPLY=0
ACTION=install
for arg in "$@"; do
  case "$arg" in
    --apply)         APPLY=1 ;;
    --check)         ACTION=check ;;
    --remove)        ACTION=remove ;;
    --link-skills)   ACTION=link ;;
    --unlink-skills) ACTION=unlink ;;
    --dedupe-rule-imports) ACTION=dedupe ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done
if [ "$ACTION" = check ]; then MODE=check
elif [ "$APPLY" -eq 1 ]; then MODE="$ACTION (apply)"
else MODE="$ACTION (dry run — pass --apply to write)"
fi

fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

echo "repo:        $ROOT"
echo "destination: $DEST"
echo "mode:        $MODE"
echo

[ -f "$BLOCK_SRC" ] || { echo "FATAL: missing $BLOCK_SRC" >&2; exit 1; }

DEST_ESC="$(printf '%s' "$DEST" | sed -e 's/[\\&|]/\\&/g')"
render_block() { LC_ALL=C sed "s|{{AGENT_HOME}}|$DEST_ESC|g" "$BLOCK_SRC"; }

# rule_imports FILE — print each `@` import line in FILE whose target is an
# installed $DEST/rules/*.md. Claude Code auto-loads those files, so such a line
# is a second copy. Matched by location, not spelling: ~/, /c/ and C:/ forms of
# the same path all count; a different directory never does.
rule_imports() {
  [ -f "$1" ] || return 0
  _rules_key="$(printf '%s\n' "$DEST/rules" | as_path_keys)"
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in @*) ;; *) continue ;; esac
    _ref="${_line#@}"; _ref="${_ref%"${_ref##*[![:space:]]}"}"
    case "$_ref" in "~/"*) _ref="$HOME/${_ref#"~/"}" ;; esac
    case "$_ref" in *.md) ;; *) continue ;; esac
    [ "$(as_native_path "$(dirname "$_ref")" | as_path_keys)" = "$_rules_key" ] || continue
    [ -f "$DEST/rules/$(basename "$_ref")" ] || continue
    printf '%s\n' "$_line"
  done < "$1"
}

if [ "$ACTION" = check ]; then
  echo "== Claude Code integration =="
  [ -d "$DEST/rules" ] && ok "$DEST/rules exists (auto-loaded by Claude Code)" \
                       || bad "$DEST/rules missing — run scripts/install.sh --apply first"
  n_rules=$(find "$DEST/rules" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c . || true)
  [ "${n_rules:-0}" -gt 0 ] && ok "$n_rules rule file(s) installed" || bad "no rule files in $DEST/rules"

  # Skills must be flat: Claude Code does not recurse past <name>/SKILL.md.
  # -L so a symlinked skill directory is followed, the way the runtime follows it.
  n_flat=$(find -L "$DEST/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | grep -c . || true)
  n_deep=$(find -L "$DEST/skills" -mindepth 3 -name SKILL.md 2>/dev/null | grep -c . || true)
  [ "${n_flat:-0}" -gt 0 ] && ok "$n_flat skill(s) at the discoverable depth" || bad "no skills found at $DEST/skills/<name>/SKILL.md"
  [ "${n_deep:-0}" -gt 0 ] && echo "  note  $n_deep SKILL.md deeper than one level — Claude Code will not discover those"

  if [ -f "$TARGET" ]; then
    if grep -qF "$BEGIN" "$TARGET"; then ok "managed block present in $TARGET"; else bad "managed block absent from $TARGET"; fi
    if [ -n "$(rule_imports "$TARGET")" ]; then
      bad "$TARGET imports rules/ explicitly — they already auto-load, so each rule loads twice (fix: --dedupe-rule-imports)"
    else
      ok "no duplicate rule imports in $TARGET"
    fi
  else
    bad "$TARGET does not exist"
  fi

  # Managed symlinks, if the skills tree was installed elsewhere.
  if [ "$SKILLS_SRC" != "$SKILLS_VIEW" ]; then
    if [ -f "$MANIFEST" ]; then
      n_ok=0; n_bad=0
      while IFS="$(printf '\t')" read -r link target; do
        [ -z "${link:-}" ] && continue
        if as_link_points_at "$link" "$target" && [ -f "$link/SKILL.md" ]; then
          n_ok=$((n_ok + 1))
        else
          n_bad=$((n_bad + 1)); echo "  FAIL  broken managed link: $link"
        fi
      done < "$MANIFEST"
      [ "$n_bad" -eq 0 ] && ok "$n_ok managed symlink(s) resolve to a readable SKILL.md" || fail=$((fail + n_bad))
    else
      bad "skills installed at $SKILLS_SRC but no link manifest at $MANIFEST"
    fi
  fi

  # Unresolved placeholders anywhere the installer wrote.
  leftover=$(grep -rlF '{{AGENT_HOME}}' "$DEST/rules" "$SKILLS_SRC" "$DEST/skill-registry" "$DEST/commands" "$TARGET" 2>/dev/null | grep -c . || true)
  [ "${leftover:-0}" -eq 0 ] && ok "no unresolved {{AGENT_HOME}} placeholders" || bad "$leftover installed file(s) still contain {{AGENT_HOME}}"

  echo
  [ "$fail" -eq 0 ] && { echo "ADAPTER CHECK: PASS"; exit 0; } || { echo "ADAPTER CHECK: FAIL ($fail problem(s))"; exit "$fail"; }
fi

if [ "$ACTION" = link ] || [ "$ACTION" = unlink ]; then
  if [ "$SKILLS_SRC" = "$SKILLS_VIEW" ]; then
    echo "  skills are already installed at $SKILLS_VIEW; nothing to link."
    exit 0
  fi
  [ -d "$SKILLS_SRC" ] || { echo "FATAL: $SKILLS_SRC does not exist — run install.sh with AGENT_SKILLS_DIR first" >&2; exit 1; }
  echo "  source: $SKILLS_SRC"
  echo "  view:   $SKILLS_VIEW"
  echo "  manifest: $MANIFEST"
  echo

  # Is the view directory someone else's checkout? Then a local exclude keeps our
  # links out of its status without touching a single tracked file.
  gitdir=""
  [ -e "$SKILLS_VIEW/.git" ] && gitdir="$SKILLS_VIEW/.git"

  if [ "$ACTION" = unlink ]; then
    as_links_unlink "$MANIFEST" "$APPLY"
    if [ "$APPLY" -eq 1 ]; then
      # The exclude entries stay while any managed link is still in place.
      if [ -z "${AS_LINKS_KEPT:-}" ] && [ -n "$gitdir" ] && [ -f "$gitdir/info/exclude" ]; then
        awk -v tag="$EXCLUDE_TAG" '
          index($0,tag) {inblk=1; next}
          inblk && /^\// {next}
          {inblk=0; print}' "$gitdir/info/exclude" > "$gitdir/info/exclude.tmp$$"           && mv -f "$gitdir/info/exclude.tmp$$" "$gitdir/info/exclude"
        echo "  cleaned our entries from $gitdir/info/exclude"
      fi
      echo; echo "Removed ${AS_LINKS_REMOVED:-0} link(s)."
    else
      echo; echo "Nothing written. Re-run with --apply to remove."
    fi
    exit 0
  fi

  # link — shared implementation, so the Claude and Codex adapters cannot drift
  # apart on the parts that decide whether a user's directory survives.
  if as_links_link "$SKILLS_SRC" "$SKILLS_VIEW" "$MANIFEST" "$APPLY"; then
    collisions=0
  else
    collisions=1
  fi

  if [ "$APPLY" -eq 1 ] && [ -n "$gitdir" ] && [ -f "$MANIFEST" ]; then
    exc="$gitdir/info/exclude"
    mkdir -p "$gitdir/info"
    [ -f "$exc" ] || : > "$exc"
    cp -p "$exc" "$exc.agent-skills.bak" 2>/dev/null || true
    grep -qF "$EXCLUDE_TAG" "$exc" || printf '
%s
' "$EXCLUDE_TAG" >> "$exc"
    while IFS="$(printf '	')" read -r link target; do
      [ -z "${link:-}" ] && continue
      # No trailing slash: these are links, and git matches a link as a file.
      # A "dir/" pattern would not match them.
      entry="/$(basename "$link")"
      grep -qxF "$entry" "$exc" || printf '%s
' "$entry" >> "$exc"
    done < "$MANIFEST"
    echo "  local exclude updated: $exc (tracked files untouched)"
  fi

  echo
  if [ "$collisions" -gt 0 ]; then
    echo "collision(s) — nothing was overwritten." >&2
    exit 1
  fi
  [ "$APPLY" -eq 1 ] && echo "Linked. Restart Claude Code, then: bash scripts/adapters/claude.sh --check"                      || echo "Nothing written. Re-run with --apply to create the links."
  exit 0
fi

if [ ! -f "$TARGET" ]; then
  echo "  $TARGET does not exist yet; it will be created with the managed block only."
  existing=""
else
  existing="$(cat "$TARGET")"
fi

has_block=0
printf '%s\n' "$existing" | grep -qF "$BEGIN" && has_block=1

# Build the new content: replace between markers if present, else append.
tmp="$(mktemp)"; trap 'rm -f "$tmp" "$tmp.blk" "$tmp.drop"' EXIT
if [ "$ACTION" = dedupe ]; then
  # Claude Code already loads $DEST/rules/*.md, so an `@` import of one of those
  # files — anywhere in CLAUDE.md, however it was spelled — is a second copy.
  # Only such import lines go; every other line, including headings around
  # them and imports of anything else, is kept byte for byte.
  if [ -z "$existing" ]; then echo "  $TARGET is absent or empty; nothing to dedupe."; exit 0; fi
  rule_imports "$TARGET" > "$tmp.drop"
  if [ ! -s "$tmp.drop" ]; then
    echo "  no rule imports in $TARGET; nothing to dedupe."
    exit 0
  fi
  sed 's/^/  drop  /' "$tmp.drop"
  printf '%s\n' "$existing" | awk 'NR == FNR { d[$0] = 1; next } !($0 in d) { print }' "$tmp.drop" - > "$tmp"
  action="DROP duplicate rule imports from"
elif [ "$ACTION" = remove ]; then
  if [ "$has_block" -eq 0 ]; then
    echo "  managed block not present; nothing to remove."
    exit 0
  fi
  printf '%s\n' "$existing" | awk -v b="$BEGIN" -v e="$END" '
    index($0,b) {skip=1; next} index($0,e) {skip=0; next} !skip {print}' > "$tmp"
  # collapse runs of blank lines, then drop any trailing blank the block left behind,
  # so --remove restores the file byte-for-byte.
  awk 'BEGIN{n=0} /^$/{n++; if(n>1) next} !/^$/{n=0} {print}' "$tmp" > "$tmp.blk" && mv "$tmp.blk" "$tmp"
  awk 'NF {last=NR} {line[NR]=$0} END {for (i=1; i<=last; i++) print line[i]}' "$tmp" > "$tmp.blk" && mv "$tmp.blk" "$tmp"
  action="REMOVE block from"
else
  render_block > "$tmp.blk"
  if [ "$has_block" -eq 1 ]; then
    printf '%s\n' "$existing" | awk -v b="$BEGIN" -v e="$END" -v f="$tmp.blk" '
      index($0,b) {skip=1; while ((getline line < f) > 0) print line; close(f); next}
      index($0,e) {skip=0; next}
      !skip {print}' > "$tmp"
    action="UPDATE block in"
  else
    { [ -n "$existing" ] && { printf '%s\n' "$existing"; echo; }; cat "$tmp.blk"; } > "$tmp"
    action="APPEND block to"
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

# Back up the real file and verify the copy before replacing it.
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$DEST/backups/claude-adapter-$stamp"
mkdir -p "$backup" || { echo "FATAL: cannot create $backup" >&2; exit 1; }
if [ -f "$TARGET" ]; then
  cp -p "$TARGET" "$backup/CLAUDE.md" || { echo "FATAL: backup failed" >&2; exit 1; }
  cmp -s "$TARGET" "$backup/CLAUDE.md" || { echo "FATAL: backup did not verify" >&2; exit 1; }
  echo "  backup:  $backup/CLAUDE.md (verified)"
fi

# mktemp creates 0600; moving it in would silently tighten the file's mode.
# Capture the original and restore it after the move.
mode=""
[ -f "$TARGET" ] && mode="$(stat -f '%Lp' "$TARGET" 2>/dev/null || stat -c '%a' "$TARGET" 2>/dev/null)"
mv -f "$tmp" "$TARGET" || { echo "FATAL: write failed" >&2; exit 1; }
if [ -n "$mode" ]; then
  chmod "$mode" "$TARGET" || echo "  warning: could not restore mode $mode on $TARGET" >&2
else
  chmod 644 "$TARGET" 2>/dev/null || true
fi
trap - EXIT; rm -f "$tmp.blk" "$tmp.drop"
echo "  written: $TARGET"
echo
echo "Applied. Restart Claude Code, then: bash scripts/adapters/claude.sh --check"
