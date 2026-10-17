#!/bin/bash
# Set up one global qmd index for every Claude Code profile and project on this machine,
# and wire the active profile to it. Safe to re-run. See ../SKILL.md.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: setup-qmd.sh [options]
  --root PATH[:NAME]   index every *.md under PATH as collection NAME (repeatable)
  --context NAME:TEXT  attach a description to collection NAME (repeatable)
  --memory             index this profile's Claude auto-memory dirs
  --no-schedule        skip the scheduled refresh (same as QMD_SCHEDULE=0)
  --dry-run            print what would change and write nothing
  --discover           list folders under $HOME by markdown file count, then exit
Environment: CLAUDE_CONFIG_DIR, XDG_CONFIG_HOME, XDG_CACHE_HOME, QMD_LAUNCHD_LABEL, LAUNCHCTL.
EOF
}

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOTS=() CONTEXTS=()
MEMORY=0 DRY=0 SCHEDULE="${QMD_SCHEDULE:-1}"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOTS+=("${2:?--root needs PATH[:NAME]}"); shift 2 ;;
    --context) CONTEXTS+=("${2:?--context needs NAME:TEXT}"); shift 2 ;;
    --memory) MEMORY=1; shift ;;
    --no-schedule) SCHEDULE=0; shift ;;
    --dry-run) DRY=1; shift ;;
    --discover)
      find "$HOME" -mindepth 1 -maxdepth 1 -type d ! -name '.*' ! -name Library ! -name Applications \
        ! -name Movies ! -name Music ! -name Pictures -print0 2>/dev/null |
        xargs -0 -I{} find {} \( -name node_modules -o -name .git -o -name dist -o -name build -o -name vendor \
          -o -name '.*' \) -prune -o -type f -name '*.md' -print 2>/dev/null |
        awk -v home="$HOME/" '{ p = substr($0, length(home) + 1); n = split(p, a, "/");
          c[home a[1]]++; if (n > 2) c[home a[1] "/" a[2]]++ }
          END { for (d in c) printf "%7d  %s\n", c[d], d }' | sort -rn | head -25 || true
      exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$1" >&2; exit "${2:-1}"; }
cfg() { python3 "$HERE/qmd-config.py" "$@" $([ "$DRY" = 1 ] && echo --dry-run); }
run() { if [ "$DRY" = 1 ]; then say "dry-run: would run $*"; else "$@" >/dev/null; fi; }

if [ -n "${QMD_CONFIG_DIR:-}" ]; then
  warn "ignoring QMD_CONFIG_DIR=$QMD_CONFIG_DIR. This setup uses the one global index."
  unset QMD_CONFIG_DIR
fi
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_JSON="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"
XDG_CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
QCFG="$XDG_CFG/qmd"
INDEX="$QCFG/index.yml"
LABEL="${QMD_LAUNCHD_LABEL:-local.qmd.reconcile}"
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
OS="$(uname -s)"
if [ "$OS" = Darwin ]; then LOG="$HOME/Library/Logs/qmd/reconcile.log"; else LOG="${XDG_STATE_HOME:-$HOME/.local/state}/qmd/reconcile.log"; fi

QMD=""
if c="$(command -v qmd 2>/dev/null)" && [ -x "$c" ]; then QMD="$c"
elif [ -x "$HOME/.bun/bin/qmd" ]; then QMD="$HOME/.bun/bin/qmd"
elif command -v npm >/dev/null 2>&1 && c="$(npm prefix -g 2>/dev/null)/bin/qmd" && [ -x "$c" ]; then QMD="$c"
fi
[ -n "$QMD" ] || die "qmd not found. Install it with 'bun install -g @tobilu/qmd' or 'npm install -g @tobilu/qmd', then re-run." 3
say "qmd: $QMD"
case ":$PATH:" in *":$(dirname "$QMD"):"*) ;; *) warn "$(dirname "$QMD") is not on PATH. Everything here uses the absolute path, but add it to PATH to run qmd by hand." ;; esac

realdir() { (cd -P "$1" 2>/dev/null && pwd); }
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | sed 's/^-*//; s/-*$//'; }

ADD_PATHS=() ADD_NAMES=()
for spec in "${ROOTS[@]+"${ROOTS[@]}"}"; do
  path="$spec" name=""
  if [ ! -d "$spec" ] && [[ "$spec" == *:* && "${spec##*:}" =~ ^[A-Za-z0-9_-]+$ ]]; then path="${spec%:*}" name="${spec##*:}"; fi
  real="$(realdir "$path")" || die "--root $path is not a directory" 2
  name="${name:-$(slug "$(basename "$real")")}"
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die "cannot derive a collection name from $path. Pass --root $path:NAME" 2
  ADD_PATHS+=("$real") ADD_NAMES+=("$name")
done
for spec in "${CONTEXTS[@]+"${CONTEXTS[@]}"}"; do
  [[ "$spec" == *:* && "${spec%%:*}" =~ ^[A-Za-z0-9_-]+$ ]] || die "--context $spec is not NAME:TEXT" 2
done

EXISTING="$(cfg collections "$INDEX")"
has_name() { grep -q "^$2"$'\t' <<<"$1"; }
path_of() { grep -m1 "^$1"$'\t' <<<"$EXISTING" | cut -f2- || true; }
covered_by() { # covered_by NAME PATH: print why NAME/PATH needs no new collection
  local n p real
  while IFS=$'\t' read -r n p; do
    [ -n "$n" ] || continue
    [ "$n" = "$1" ] && { say "name $n already exists"; return 0; }
    real="$(realdir "$p")" || real="$p"
    case "$2/" in "$real/"*) say "inside collection $n ($p)"; return 0 ;; esac
  done <<<"$EXISTING"
  return 1
}
add_collection() { # add_collection NAME PATH MASK
  local why
  if why="$(covered_by "$1" "$2")"; then say "collection $1: skipped, $why"; return 0; fi
  while IFS=$'\t' read -r n p; do
    [ -n "$n" ] || continue
    case "$(realdir "$p" || echo "$p")/" in "$2/"?*) warn "collection $n ($p) sits inside $2, so its files will be indexed twice" ;; esac
  done <<<"$EXISTING"
  run "$QMD" collection add "$2" --name "$1" --mask "$3"
  EXISTING="$EXISTING"$'\n'"$1"$'\t'"$2"
  [ "$DRY" = 1 ] || say "collection $1: added $2 ($3)"
}

i=0
while [ "$i" -lt "${#ADD_PATHS[@]}" ]; do add_collection "${ADD_NAMES[$i]}" "${ADD_PATHS[$i]}" '**/*.md'; i=$((i + 1)); done
if [ "$MEMORY" = 1 ]; then
  # Two profiles can share a dir name, so fall back to a name that adds the parent dir.
  mem_base="$(slug "$(basename "$CLAUDE_DIR")")-memory"
  mem_names=("$mem_base" "$(slug "$(basename "$(dirname "$CLAUDE_DIR")")")-$mem_base")
  mem_name=""
  if ! mem_path="$(realdir "$CLAUDE_DIR/projects")"; then
    warn "$CLAUDE_DIR/projects does not exist yet, so --memory added nothing. Re-run after Claude Code has saved a memory."
  else
    for n in "${mem_names[@]}"; do
      p="$(path_of "$n")"
      [ -n "$p" ] && [ "$(realdir "$p" || echo "$p")" = "$mem_path" ] && { mem_name="$n"; break; }
    done
    if [ -z "$mem_name" ]; then
      for n in "${mem_names[@]}"; do [ -z "$(path_of "$n")" ] && { mem_name="$n"; break; }; done
    fi
    [ -n "$mem_name" ] || warn "collections ${mem_names[*]} already index other folders, so --memory added nothing. Remove one, or add $mem_path with --root."
  fi
  if [ -n "$mem_name" ]; then
    add_collection "$mem_name" "$mem_path" '*/memory/**/*.md'
    indexed="$(cfg collections "$INDEX")"
    if has_name "$indexed" "$mem_name"; then
      st="$(cfg add-ignore "$INDEX" "$mem_name" '-private-tmp-*/**' '-tmp-*/**')" || exit 1
      say "collection $mem_name ignore list: $st"
      CONTEXTS+=("$mem_name:Claude Code auto-memory notes, one folder per project")
    elif has_name "$EXISTING" "$mem_name"; then
      say "dry-run: would add ignore patterns to collection $mem_name"
      CONTEXTS+=("$mem_name:Claude Code auto-memory notes, one folder per project")
    else
      say "collection $mem_name: no ignore list, since no collection of that name was added. The parent collection still indexes the -private-tmp-* and -tmp-* project notes."
    fi
  fi
fi
for spec in "${CONTEXTS[@]+"${CONTEXTS[@]}"}"; do
  if has_name "$EXISTING" "${spec%%:*}"; then
    run "$QMD" context add "qmd://${spec%%:*}" "${spec#*:}"
    [ "$DRY" = 1 ] || say "context for ${spec%%:*}: set"
  else
    warn "no collection named ${spec%%:*}, so its context was not set"
  fi
done

install_script() { # install_script SRC DEST [CONTENT]
  local content="${3:-$(cat "$1")}"
  if [ -f "$2" ] && [ "$(cat "$2")" = "$content" ]; then say "$(basename "$2"): unchanged"; return 0; fi
  if [ "$DRY" = 1 ]; then say "dry-run: would install $2"; return 0; fi
  mkdir -p "$(dirname "$2")"
  [ ! -f "$2" ] || cp -p "$2" "$2.qmd-backup-$(date +%Y%m%d%H%M%S)"
  printf '%s\n' "$content" >"$2.tmp.$$" && chmod 755 "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"
  say "$(basename "$2"): installed at $2"
}
runtime_path="$(for b in node bun; do c="$(command -v "$b")" && dirname "$c"; done | awk '!seen[$0]++' | paste -sd: -)" || true
reconcile="$(python3 "$HERE/qmd-config.py" render "$HERE/reconcile.sh" \
  QMD_BINARY="$QMD" RUNTIME_PATH="$runtime_path" XDG_CONFIG_HOME="$XDG_CFG" XDG_CACHE_HOME="$XDG_CACHE")"
install_script "$HERE/reconcile.sh" "$QCFG/reconcile.sh" "$reconcile"
install_script "$HERE/on-edit-hook.sh" "$QCFG/on-edit-hook.sh"

if python3 "$HERE/qmd-config.py" has-mcp "$CLAUDE_JSON"; then
  say "MCP server qmd: already in $CLAUDE_JSON"
elif command -v claude >/dev/null 2>&1; then
  run claude mcp add -s user qmd -- "$QMD" mcp
  [ "$DRY" = 1 ] || say "MCP server qmd: added with claude mcp add (user scope, $CLAUDE_JSON)"
else
  st="$(cfg mcp "$CLAUDE_JSON" "$QMD")" || exit 1
  say "MCP server qmd: claude CLI not found, $CLAUDE_JSON $st"
fi
st="$(cfg hook "$CLAUDE_DIR/settings.json" "$QCFG/on-edit-hook.sh")" || exit 1
say "PostToolUse hook in $CLAUDE_DIR/settings.json: $st"
if [ "$DRY" = 1 ]; then
  say "dry-run: would run $QMD status to check for GPU acceleration"
  device=unknown
else
  status="$("$QMD" status 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' || true)"
  if grep -Eq 'GPU: +none|no GPU acceleration' <<<"$status"; then device=cpu
  elif grep -Eq 'GPU: +[^ ]' <<<"$status"; then device=gpu
  else device=unknown; fi
  say "qmd status device: $device"
fi
measured="On a CPU-only Intel i7, a reranked query took over 240 s, while lex took about 3 s and vec about 7 s."
case "$device" in
  cpu) rerank="- This machine has no GPU acceleration, so always pass \`rerank: false\` to \`query\`. $measured" ;;
  gpu) rerank="" ;;
  *) rerank="- Pass \`rerank: false\` to \`query\` when \`qmd status\` shows no GPU. $measured" ;;
esac
block="$(cat <<'EOF'
<!-- keel:qmd start -->
## Local markdown search (qmd)

One qmd index on this machine holds the markdown collections the qmd `status` tool lists. Search it before you grep folders by hand.

- Use the qmd MCP tools. `query` searches, `get` and `multi_get` read documents, and `status` lists collections and their health.
- Pass `collections: ["<name>"]` to `query` when you know which collection holds the answer.
@RERANK@
- Edits to `.md` files inside a collection reach the index in the background. On CPU, embeddings can lag by hours after a large change.
<!-- keel:qmd end -->
EOF
)"
if [ -n "$rerank" ]; then block="${block/@RERANK@/$rerank}"; else block="$(grep -vx '@RERANK@' <<<"$block")"; fi
st="$(cfg claude-md "$CLAUDE_DIR/CLAUDE.md" <<<"$block")" || exit 1
say "qmd block in $CLAUDE_DIR/CLAUDE.md: $st"

BOOTSTRAPPED=0
if [ "$SCHEDULE" = 0 ]; then
  say "schedule: skipped. The edit hook still refreshes the index."
elif [ "$OS" = Darwin ]; then
  plist="$HOME/Library/LaunchAgents/$LABEL.plist"
  for other in "$HOME"/Library/LaunchAgents/*.plist; do
    if [ -f "$other" ] && [ "$other" != "$plist" ] && grep -qi qmd "$other"; then
      warn "$other also mentions qmd. Remove it if it refreshes this index, or the index gets two schedulers."
    fi
  done
  plist_state="$(cfg plist "$plist" "$LABEL" "$QCFG/reconcile.sh")"
  say "LaunchAgent $plist: $plist_state"
  loaded=0
  "$LAUNCHCTL" print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 && loaded=1
  if [ "$loaded" = 1 ] && [ "$plist_state" != unchanged ]; then
    run "$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL"
    loaded=0
  fi
  if [ "$loaded" = 1 ]; then
    say "LaunchAgent $LABEL: already loaded"
  else
    run "$LAUNCHCTL" bootstrap "gui/$(id -u)" "$plist"
    BOOTSTRAPPED=1
    [ "$DRY" = 1 ] || say "LaunchAgent $LABEL: loaded. It runs every 30 minutes and once now."
  fi
else
  say "schedule: add this line with 'crontab -e' to refresh every 30 minutes:"
  say "*/30 * * * * /bin/bash $(printf '%q' "$QCFG/reconcile.sh") cron"
fi
if [ "$BOOTSTRAPPED" = 0 ]; then
  if [ "$DRY" = 1 ]; then say "dry-run: would start reconcile.sh in the background"
  else nohup /bin/bash "$QCFG/reconcile.sh" setup >/dev/null 2>&1 & say "reconcile: started in the background"; fi
fi

say ""
say "The first embed runs in the background and can take hours on CPU. Watch it with:"
say "  $(printf '%q' "$QMD") status"
say "  tail -f $(printf '%q' "$LOG")"
say "Restart Claude Code so this profile loads the qmd MCP server and the hook."
