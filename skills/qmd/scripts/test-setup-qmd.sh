#!/bin/bash
# Tests for setup-qmd.sh, reconcile.sh, and on-edit-hook.sh. Every case gets a fresh HOME
# under QMD_TEST_DIR (default: a new temp dir), stub qmd, claude, launchctl, and uname
# binaries, and an empty environment. On macOS each run also goes through sandbox-exec,
# which denies network access and every write under /Users and the real HOME except
# inside QMD_TEST_DIR. PYTHONDONTWRITEBYTECODE keeps python3 from caching bytecode.
set -u
export PYTHONDONTWRITEBYTECODE=1
HERE="$(cd "$(dirname "$0")" && pwd)"
SB="${QMD_TEST_DIR:-$(mktemp -d)}"
SB="$(mkdir -p "$SB" && cd -P "$SB" && pwd)"
[ -n "$SB" ] && [ "$SB" != / ] && [ -d "$SB" ] || { echo "cannot create QMD_TEST_DIR" >&2; exit 2; }
REAL_HOME="$(cd -P "$HOME" && pwd)"
case "$REAL_HOME/" in "$SB/"*) echo "QMD_TEST_DIR must not contain HOME" >&2; exit 2 ;; esac
if command -v sandbox-exec >/dev/null 2>&1; then
  PROFILE="(version 1)(allow default)(deny network-outbound (remote ip))"
  PROFILE+="(deny file-write* (subpath \"/Users\") (subpath \"$REAL_HOME\"))(allow file-write* (subpath \"$SB\"))"
  probe="$REAL_HOME/.qmd-test-probe-$$"
  if sandbox-exec -p "$PROFILE" /bin/sh -c "touch '$probe'" 2>/dev/null; then
    rm -f "$probe"; echo "sandbox profile did not block a write to $probe" >&2; exit 2
  fi
  sandbox-exec -p "$PROFILE" /bin/sh -c "touch '$SB/.probe' && rm '$SB/.probe'" ||
    { echo "sandbox profile blocked a write under $SB" >&2; exit 2; }
  SANDBOX=(sandbox-exec -p "$PROFILE")
else
  SANDBOX=()
fi
fail=0
check() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

write_stubs() { # write_stubs DIR OS: stub binaries that log their calls to $STUB_CALLS
  mkdir -p "$1"
  cat >"$1/qmd" <<'EOF'
#!/bin/bash
echo "$*" >>"$STUB_CALLS/qmd.calls"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/qmd/index.yml"
case "$1 ${2:-}" in
  "collection add")
    path="$3" name="" mask="**/*.md"; shift 3
    while [ $# -gt 0 ]; do case "$1" in --name) name="$2"; shift 2 ;; --mask) mask="$2"; shift 2 ;; *) shift ;; esac; done
    mkdir -p "$(dirname "$cfg")"; [ -f "$cfg" ] || echo "collections:" >"$cfg"
    printf '  %s:\n    path: %s\n    pattern: "%s"\n' "$name" "$path" "$mask" >>"$cfg"
    echo "Collection '$name' created" ;;
  "context add") echo "Context added" ;;
  status*)
    case "${QMD_STUB_GPU:-}" in
      "") echo "qmd stub" ;;
      none) printf 'Device\n  GPU:      \033[33mnone\033[0m (running on CPU)\n' ;;
      *) printf 'Device\n  GPU:      \033[32m%s\033[0m (offloading: yes)\n' "$QMD_STUB_GPU" ;;
    esac ;;
  update*) sleep "${QMD_STUB_SLEEP:-0}"; echo "Indexed: 3 new, 1 updated, 0 unchanged, 0 removed" ;;
  embed*) printf 'Embedding...\r\xe2\x9c\x93 Done! Embedded 4 chunks\n' ;;
  *) echo "qmd stub" ;;
esac
EOF
  cat >"$1/claude" <<'EOF'
#!/bin/bash
echo "$*" >>"$STUB_CALLS/claude.calls"
[ "$1 $2 $3 $4 $5 $6" = "mcp add -s user qmd --" ] || exit 1
file="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"
python3 - "${file:-$HOME/.claude.json}" "$7" "$8" <<'PY'
import json, os, sys
path, cmd, arg = sys.argv[1:]
data = json.load(open(path)) if os.path.exists(path) else {}
data.setdefault("mcpServers", {})["qmd"] = {"type": "stdio", "command": cmd, "args": [arg], "env": {}}
json.dump(data, open(path, "w"), indent=2)
PY
EOF
  cat >"$1/launchctl" <<'EOF'
#!/bin/bash
echo "$*" >>"$STUB_CALLS/launchctl.calls"
case "$1" in
  print) [ -f "$STUB_CALLS/launchctl.loaded" ] ;;
  bootstrap) touch "$STUB_CALLS/launchctl.loaded" ;;
esac
EOF
  printf '#!/bin/sh\necho %s\n' "$2" >"$1/uname"
  chmod +x "$1"/*
}

new_case() { # new_case NAME OS: sets C (case dir), H (HOME), ST (stubs), CL (call logs)
  C="$SB/$1"; rm -rf "$C"; H="$C/home"; ST="$C/stubs"; CL="$C/calls"
  mkdir -p "$H/tmp" "$CL"; write_stubs "$ST" "$2"
  mkdir -p "$H/code/app/docs" "$H/code/lib" "$H/my notes" "$H/.claude/projects/-code-app/memory" "$H/.claude/projects/-private-tmp-x/memory"
  echo "# app" >"$H/code/app/docs/a.md"; echo "# lib" >"$H/code/lib/README.md"; echo "# n" >"$H/my notes/n.md"
  echo "# mem" >"$H/.claude/projects/-code-app/memory/m.md"
}
setup() { # setup [VAR=VALUE...] -- ARGS...: run setup-qmd.sh in the case's sandbox
  local vars=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do vars+=("$1"); shift; done; shift
  "${SANDBOX[@]+"${SANDBOX[@]}"}" env -i HOME="$H" PATH="$ST:/usr/bin:/bin" TMPDIR="$H/tmp/" STUB_CALLS="$CL" PYTHONDONTWRITEBYTECODE=1 \
    "${vars[@]+"${vars[@]}"}" /bin/bash "$HERE/setup-qmd.sh" "$@" >"$C/out" 2>&1
}
run_sh() { "${SANDBOX[@]+"${SANDBOX[@]}"}" env -i HOME="$H" PATH="/usr/bin:/bin" /bin/sh -c "$1"; }
calls() { if [ -f "$CL/$1.calls" ]; then grep -c -- "$2" "$CL/$1.calls" || true; else echo 0; fi; }
snapshot() { (cd "$1" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort); }
wait_for() { for _ in $(seq 1 50); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
mode() { python3 -c 'import os, sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$1"; }
json() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps($2))" "$1" 2>/dev/null; }

echo "== setup: fresh install"
new_case fresh Darwin
setup -- --root "$H/code" --root "$H/my notes:notes" --memory; rc=$?
check "exit 0" '[ $rc = 0 ]'
check "three collections added" '[ "$(calls qmd "collection add")" = 3 ]'
check "index has code, notes, claude-memory" '[ "$(python3 "$HERE/qmd-config.py" collections "$H/.config/qmd/index.yml" | cut -f1 | tr "\n" " ")" = "code notes claude-memory " ]'
check "memory collection uses the memory pattern" 'grep -q "pattern: \"\*/memory/\*\*/\*.md\"" "$H/.config/qmd/index.yml"'
check "memory collection ignores tmp project dirs" 'grep -q "\"-private-tmp-\*/\*\*\"" "$H/.config/qmd/index.yml" && grep -q "\"-tmp-\*/\*\*\"" "$H/.config/qmd/index.yml"'
check "context set for the memory collection" 'grep -q "^context add qmd://claude-memory " "$CL/qmd.calls"'
check "reconcile.sh filled in and valid" '! grep -q "{{" "$H/.config/qmd/reconcile.sh" && grep -qx "QMD=$ST/qmd" "$H/.config/qmd/reconcile.sh" && bash -n "$H/.config/qmd/reconcile.sh" && [ -x "$H/.config/qmd/reconcile.sh" ]'
check "reconcile.sh pins the XDG dirs" "grep -qx 'export XDG_CONFIG_HOME=$H/.config XDG_CACHE_HOME=$H/.cache' \"\$H/.config/qmd/reconcile.sh\""
check "on-edit-hook.sh installed" 'cmp -s "$HERE/on-edit-hook.sh" "$H/.config/qmd/on-edit-hook.sh"'
check "MCP added through claude mcp add" '[ "$(cat "$CL/claude.calls")" = "mcp add -s user qmd -- $ST/qmd mcp" ]'
check "MCP server in ~/.claude.json" '[ "$(json "$H/.claude.json" "d[\"mcpServers\"][\"qmd\"]")" = "{\"type\": \"stdio\", \"command\": \"$ST/qmd\", \"args\": [\"mcp\"], \"env\": {}}" ]'
check "PostToolUse hook in settings.json" '[ "$(json "$H/.claude/settings.json" "[(e[\"matcher\"], h[\"command\"], h[\"timeout\"]) for e in d[\"hooks\"][\"PostToolUse\"] for h in e[\"hooks\"]]")" = "[[\"Write|Edit\", \"bash $H/.config/qmd/on-edit-hook.sh\", 10]]" ]'
check "CLAUDE.md block with rerank guidance" '[ "$(grep -c "keel:qmd start" "$H/.claude/CLAUDE.md")" = 1 ] && grep -q "rerank: false" "$H/.claude/CLAUDE.md"'
check "LaunchAgent plist" '[ "$(python3 -c "import plistlib,sys; p=plistlib.load(open(sys.argv[1],\"rb\")); print(p[\"Label\"], p[\"StartInterval\"], p[\"RunAtLoad\"], p[\"Nice\"], p[\"LowPriorityIO\"], *p[\"ProgramArguments\"])" "$H/Library/LaunchAgents/local.qmd.reconcile.plist")" = "local.qmd.reconcile 1800 True 15 True /bin/bash $H/.config/qmd/reconcile.sh launchd" ]'
check "launchctl printed then bootstrapped once" '[ "$(calls launchctl print)" = 1 ] && [ "$(calls launchctl bootstrap)" = 1 ]'
check "prints how to watch progress" 'grep -q "status$" "$C/out" && grep -q "tail -f .*reconcile.log" "$C/out"'
sed 's/^/    /' "$C/out"

echo "== setup: re-run is idempotent"
before="$(snapshot "$H")"
setup -- --root "$H/code" --root "$H/my notes:notes" --memory; rc=$?
check "exit 0" '[ $rc = 0 ]'
check "no new collection" '[ "$(calls qmd "collection add")" = 3 ]'
check "no second claude mcp add" '[ "$(wc -l <"$CL/claude.calls" | tr -d " ")" = 1 ]'
check "plist not re-bootstrapped" '[ "$(calls launchctl bootstrap)" = 1 ] && [ "$(calls launchctl print)" = 2 ]'
check "background reconcile started" 'wait_for "$H/Library/Logs/qmd/reconcile.log" "start (setup)" || wait_for "$H/.local/state/qmd/reconcile.log" "start (setup)"'
wait_for "$H/Library/Logs/qmd/reconcile.log" "done" || wait_for "$H/.local/state/qmd/reconcile.log" "done"
check "config files unchanged, no backups" '[ "$(snapshot "$H" | grep -v -e "/Library/Logs" -e "/.local/state" -e "/tmp")" = "$(printf "%s\n" "$before" | grep -v -e "/Library/Logs" -e "/.local/state" -e "/tmp")" ]'
check "outputs say unchanged and skipped" 'grep -q "collection code: skipped, name code already exists" "$C/out" && grep -q "settings.json: unchanged" "$C/out" && grep -q "CLAUDE.md: unchanged" "$C/out"'

echo "== setup: a changed plist is reloaded"
printf '<!-- edited -->\n' >>"$H/Library/LaunchAgents/local.qmd.reconcile.plist"
setup -- --root "$H/code"; rc=$?
check "exit 0, booted out and bootstrapped again" '[ $rc = 0 ] && [ "$(calls launchctl bootout)" = 1 ] && [ "$(calls launchctl bootstrap)" = 2 ]'
check "plist rewritten" '! grep -q edited "$H/Library/LaunchAgents/local.qmd.reconcile.plist"'
check "plist backup kept outside LaunchAgents" 'grep -q edited "$H/.config/qmd"/local.qmd.reconcile.plist.qmd-backup-* && [ "$(ls "$H/Library/LaunchAgents")" = local.qmd.reconcile.plist ]'

echo "== setup: the rerank line follows qmd status"
new_case gpu Darwin
block() { sed -n '/keel:qmd start/,/keel:qmd end/p' "$H/.claude/CLAUDE.md"; }
setup QMD_STUB_GPU=none -- --no-schedule
check "CPU only: always pass rerank false" '[ "$(block | grep -c rerank)" = 1 ] && block | grep -q "no GPU acceleration, so always pass \`rerank: false\`"'
setup QMD_STUB_GPU=metal -- --no-schedule
check "GPU found: no rerank line, one block" '! block | grep -q rerank && [ "$(grep -c "keel:qmd start" "$H/.claude/CLAUDE.md")" = 1 ]'
setup -- --no-schedule
check "unknown: conditional rerank line" 'block | grep -q "when \`qmd status\` shows no GPU"'

echo "== setup: existing index.yml, settings.json, and CLAUDE.md are kept"
new_case existing Darwin
mkdir -p "$H/.config/qmd" "$H/vault" "$H/.claude"
printf 'collections:\n  vault:\n    path: %s\n    pattern: "**/*.md"\n    ignore:\n      - drafts/**\n    context:\n      "": My vault\n' "$H/vault" >"$H/.config/qmd/index.yml"
vault_block="$(cat "$H/.config/qmd/index.yml")"
printf '# My rules\n\nBe brief.\n' >"$H/.claude/CLAUDE.md"
printf '{"model": "opus", "hooks": {"PostToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo hi"}]}]}}\n' >"$H/.claude/settings.json"
setup -- --root "$H/code"; rc=$?
check "exit 0" '[ $rc = 0 ]'
check "vault collection untouched" '[ "$(head -8 "$H/.config/qmd/index.yml")" = "$vault_block" ]'
check "user CLAUDE.md text kept above the block" '[ "$(head -3 "$H/.claude/CLAUDE.md")" = "$(printf "# My rules\n\nBe brief.")" ] && grep -q "keel:qmd end" "$H/.claude/CLAUDE.md"'
check "settings keep model and the Bash hook" '[ "$(json "$H/.claude/settings.json" "[d[\"model\"]] + [e[\"matcher\"] for e in d[\"hooks\"][\"PostToolUse\"]]")" = "[\"opus\", \"Bash\", \"Write|Edit\"]" ]'
check "backups of the edited files" 'ls "$H/.claude"/settings.json.qmd-backup-* "$H/.claude"/CLAUDE.md.qmd-backup-* >/dev/null 2>&1'

echo "== setup: a path inside an existing collection is skipped"
new_case covered Darwin
mkdir -p "$H/.config/qmd"
printf 'collections:\n  code:\n    path: %s\n    pattern: "**/*.md"\n' "$H/code" >"$H/.config/qmd/index.yml"
setup -- --root "$H/code/app" --root "$H/my notes:code"; rc=$?
check "exit 0, no collection add" '[ $rc = 0 ] && [ "$(calls qmd "collection add")" = 0 ]'
check "reasons printed" 'grep -q "collection app: skipped, inside collection code" "$C/out" && grep -q "collection code: skipped, name code already exists" "$C/out"'

echo "== setup: qmd installed with bun, not on PATH"
new_case bun Darwin
mkdir -p "$H/.bun/bin"; mv "$ST/qmd" "$H/.bun/bin/qmd"
setup -- --root "$H/code"; rc=$?
check "exit 0" '[ $rc = 0 ]'
check "warns that the bun dir is not on PATH" 'grep -q "$H/.bun/bin is not on PATH" "$C/out"'
check "absolute bun path in reconcile.sh and MCP" 'grep -qx "QMD=$H/.bun/bin/qmd" "$H/.config/qmd/reconcile.sh" && grep -q "mcp add -s user qmd -- $H/.bun/bin/qmd mcp" "$CL/claude.calls"'

echo "== setup: reconcile.sh pins the node and bun dirs setup saw"
new_case runtime Darwin
mkdir -p "$C/node bin" "$C/bun"; printf '#!/bin/sh\n' >"$C/node bin/node"; printf '#!/bin/sh\n' >"$C/bun/bun"; chmod +x "$C/node bin/node" "$C/bun/bun"
setup PATH="$ST:$C/node bin:$C/bun:/usr/bin:/bin" -- --root "$H/code" --no-schedule; rc=$?
check "RUNTIME_PATH holds both dirs, quoted" '[ $rc = 0 ] && [ "$(bash -c "$(grep "^RUNTIME_PATH=" "$H/.config/qmd/reconcile.sh"); echo \"\$RUNTIME_PATH\"")" = "$C/node bin:$C/bun" ]'
check "empty RUNTIME_PATH adds no empty PATH entry" '[ "$(env -i HOME=/h PATH=/usr/bin:/bin /bin/bash -c "QMD=/q/qmd RUNTIME_PATH=; $(grep "^export PATH=" "$HERE/reconcile.sh"); echo \$PATH")" = "/q:/h/.bun/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/bin:/bin" ]'

echo "== setup: CLAUDE_CONFIG_DIR profile"
new_case profile Darwin
P="$H/.claude-work"; mkdir -p "$P/projects/-code-app/memory"; echo "# w" >"$P/projects/-code-app/memory/w.md"
setup CLAUDE_CONFIG_DIR="$P" -- --root "$H/code" --memory; rc=$?
check "exit 0" '[ $rc = 0 ]'
check "profile files written" '[ -f "$P/settings.json" ] && [ -f "$P/CLAUDE.md" ] && [ "$(json "$P/.claude.json" "d[\"mcpServers\"][\"qmd\"][\"command\"]")" = "\"$ST/qmd\"" ]'
check "default profile untouched" '[ ! -e "$H/.claude.json" ] && [ ! -e "$H/.claude/settings.json" ] && [ ! -e "$H/.claude/CLAUDE.md" ]'
check "memory collection named for the profile" 'grep -q "^  claude-work-memory:" "$H/.config/qmd/index.yml" && grep -q "path: $P/projects" "$H/.config/qmd/index.yml"'
check "shared index, not per profile" '[ ! -e "$P/qmd" ] && [ -f "$H/.config/qmd/index.yml" ]'

echo "== setup: no claude CLI falls back to a JSON merge"
new_case nocli Darwin
rm "$ST/claude"; printf '{"numStartups": 7, "mcpServers": {"other": {"command": "x"}}}\n' >"$H/.claude.json"; chmod 600 "$H/.claude.json"
setup -- --root "$H/code"; rc=$?
check "exit 0" '[ $rc = 0 ]'
check "qmd added, other keys kept" '[ "$(json "$H/.claude.json" "[d[\"numStartups\"], sorted(d[\"mcpServers\"]), d[\"mcpServers\"][\"qmd\"][\"args\"]]")" = "[7, [\"other\", \"qmd\"], [\"mcp\"]]" ]'
check "backup written" 'ls "$H"/.claude.json.qmd-backup-* >/dev/null 2>&1'
check "0600 .claude.json stays 0600" '[ "$(mode "$H/.claude.json")" = 600 ]'

echo "== setup: non-macOS prints a cron line"
new_case linux Linux
mkdir -p "$H/.bun/bin"; cp "$ST/uname" "$H/.bun/bin/uname"
setup -- --root "$H/code"; rc=$?
check "exit 0" '[ $rc = 0 ]'
check "no plist, no launchctl" '[ ! -e "$H/Library/LaunchAgents" ] && [ ! -e "$CL/launchctl.calls" ]'
check "cron line printed" 'grep -qx "\*/30 \* \* \* \* /bin/bash $H/.config/qmd/reconcile.sh cron" "$C/out"'
check "first reconcile runs in the background" 'wait_for "$H/.local/state/qmd/reconcile.log" "start (setup)"'
check "QMD_SCHEDULE=0 prints no cron line" 'setup QMD_SCHEDULE=0 -- --root "$H/code"; ! grep -q "crontab" "$C/out" && grep -q "schedule: skipped" "$C/out"'

echo "== setup: --dry-run writes nothing"
new_case dry Darwin
before="$(snapshot "$H")"
setup -- --root "$H/code" --memory --dry-run; rc=$?
check "exit 0 and reports would-changes" '[ $rc = 0 ] && grep -q "dry-run: would run $ST/qmd collection add $H/code" "$C/out" && grep -q "dry-run: would run claude mcp add -s user qmd -- $ST/qmd mcp" "$C/out" && grep -q "would change" "$C/out"'
check "HOME unchanged" '[ "$(snapshot "$H")" = "$before" ]'
check "no qmd writes, no claude, no bootstrap" '[ "$(calls qmd "collection add")" = 0 ] && [ ! -e "$CL/claude.calls" ] && [ "$(calls launchctl bootstrap)" = 0 ]'

echo "== setup: missing qmd and bad input"
new_case missing Darwin
rm "$ST/qmd"; before="$(snapshot "$H")"
setup -- --root "$H/code"; rc=$?
check "exit 3 with install hint, nothing written" '[ $rc = 3 ] && grep -q "bun install -g @tobilu/qmd" "$C/out" && [ "$(snapshot "$H")" = "$before" ]'
check "error message does not end with the exit code" 'grep -q "then re-run\.$" "$C/out"'
new_case badroot Darwin
setup -- --root "$H/nope"; rc=$?
check "missing root exits 2 before any write" '[ $rc = 2 ] && [ ! -e "$H/.config/qmd" ] && grep -qx "error: --root $H/nope is not a directory" "$C/out"'

echo "== setup: --discover"
new_case discover Darwin
mkdir -p "$H/code/app/node_modules/x" "$H/code/.hidden" "$H/code/locked"; echo x >"$H/code/app/node_modules/x/r.md"; echo x >"$H/code/.hidden/h.md"
chmod 000 "$H/code/locked"
setup -- --discover; rc=$?
chmod 755 "$H/code/locked"
check "counts markdown, skips node_modules and dot dirs, survives an unreadable folder" '[ $rc = 0 ] && grep -Eq "^ +2  $H/code$" "$C/out" && grep -Eq "^ +1  $H/code/app$" "$C/out" && ! grep -q "\.claude" "$C/out"'

echo "== setup: a broken config file fails the run"
new_case badjson Darwin
mkdir -p "$H/.claude"; printf '{"model": "opus",}\n' >"$H/.claude/settings.json"
setup -- --root "$H/code" --no-schedule; rc=$?
check "invalid settings.json: nonzero exit, named in the error, file kept" '[ $rc != 0 ] && grep -q "error: .*settings.json is not valid JSON" "$C/out" && ! grep -q "Restart Claude Code" "$C/out" && [ "$(cat "$H/.claude/settings.json")" = "{\"model\": \"opus\",}" ]'
new_case badcj Darwin
rm "$ST/claude"; printf '{bad' >"$H/.claude.json"
setup -- --root "$H/code" --no-schedule; rc=$?
check "invalid .claude.json without the CLI: nonzero exit" '[ $rc != 0 ] && grep -q "error: .*\.claude\.json is not valid JSON" "$C/out"'
new_case nullhooks Darwin
mkdir -p "$H/.claude"; printf '{"hooks": null}\n' >"$H/.claude/settings.json"
setup -- --root "$H/code" --no-schedule; rc=$?
check "\"hooks\": null is replaced by the hook" '[ $rc = 0 ] && [ "$(json "$H/.claude/settings.json" "len(d[\"hooks\"][\"PostToolUse\"])")" = 1 ]'
new_case badhooks Darwin
mkdir -p "$H/.claude"; printf '{"hooks": {"PostToolUse": {"matcher": "x"}}}\n' >"$H/.claude/settings.json"
setup -- --root "$H/code" --no-schedule; rc=$?
check "PostToolUse that is not a list: nonzero exit" '[ $rc != 0 ] && grep -q "error: .*PostToolUse" "$C/out"'

echo "== setup: symlinked config files and file modes are kept"
new_case links Darwin
mkdir -p "$H/dotfiles" "$H/.claude"; printf '# dot\n' >"$H/dotfiles/CLAUDE.md"; printf '{"env": {"K": "secret"}}\n' >"$H/dotfiles/settings.json"
chmod 600 "$H/dotfiles/settings.json"
ln -s "$H/dotfiles/CLAUDE.md" "$H/.claude/CLAUDE.md"; ln -s "$H/dotfiles/settings.json" "$H/.claude/settings.json"
setup -- --root "$H/code" --no-schedule; rc=$?
check "exit 0, links still links" '[ $rc = 0 ] && [ -L "$H/.claude/CLAUDE.md" ] && [ -L "$H/.claude/settings.json" ]'
check "edits reached the link targets" 'grep -q "keel:qmd start" "$H/dotfiles/CLAUDE.md" && grep -q on-edit-hook "$H/dotfiles/settings.json"'
check "0600 settings.json stays 0600" '[ "$(mode "$H/dotfiles/settings.json")" = 600 ]'
new_case modes Darwin
rm "$ST/claude"
setup -- --root "$H/code" --no-schedule; rc=$?
check "new .claude.json is 0600" '[ $rc = 0 ] && [ "$(mode "$H/.claude.json")" = 600 ]'

echo "== setup: memory folder inside a parent collection"
new_case memparent Darwin
mkdir -p "$H/.config/qmd"; printf 'collections:\n  home:\n    path: %s\n    pattern: "**/*.md"\n' "$H" >"$H/.config/qmd/index.yml"
setup -- --memory --no-schedule; rc=$?
check "exit 0, no dry-run line, says why no ignore list" '[ $rc = 0 ] && ! grep -q "dry-run" "$C/out" && grep -q "claude-memory: no ignore list" "$C/out" && ! grep -q "no collection named claude-memory" "$C/out"'

echo "== setup: --memory when its collection name belongs to another folder"
new_case memname Darwin
mkdir -p "$H/.config/qmd" "$H/notes"
printf 'collections:\n  claude-memory:\n    path: %s\n    pattern: "**/*.md"\n' "$H/notes" >"$H/.config/qmd/index.yml"
orig="$(cat "$H/.config/qmd/index.yml")"
setup -- --memory --no-schedule; rc=$?
check "exit 0, the other collection and its context untouched" '[ $rc = 0 ] && [ "$(head -4 "$H/.config/qmd/index.yml")" = "$orig" ] && ! grep -q "^context add qmd://claude-memory " "$CL/qmd.calls"'
check "memory added as home-claude-memory with its ignore list and context" '[ "$(python3 "$HERE/qmd-config.py" collections "$H/.config/qmd/index.yml" | tail -1)" = "home-claude-memory$(printf "\t")$H/.claude/projects" ] && [ "$(sed -n "5,\$p" "$H/.config/qmd/index.yml" | grep -c -e "-private-tmp-" -e "\"-tmp-")" = 2 ] && grep -q "^context add qmd://home-claude-memory " "$CL/qmd.calls"'
setup -- --memory --no-schedule; rc=$?
check "re-run keeps the same name, adds nothing" '[ $rc = 0 ] && [ "$(calls qmd "collection add")" = 1 ] && grep -q "ignore list: unchanged" "$C/out"'
new_case memtaken Darwin
mkdir -p "$H/.config/qmd" "$H/a" "$H/b"
printf 'collections:\n  claude-memory:\n    path: %s\n  home-claude-memory:\n    path: %s\n' "$H/a" "$H/b" >"$H/.config/qmd/index.yml"
orig="$(cat "$H/.config/qmd/index.yml")"
setup -- --memory --no-schedule; rc=$?
check "both names taken: warns, changes nothing" '[ $rc = 0 ] && grep -q "warning: .*--memory added nothing" "$C/out" && [ "$(cat "$H/.config/qmd/index.yml")" = "$orig" ] && [ "$(calls qmd "context add")" = 0 ]'

echo "== setup: a root whose folder name has a colon"
new_case colon Darwin
mkdir -p "$H/notes:2024" "$H/notes"; echo "# y" >"$H/notes:2024/y.md"
setup -- --root "$H/notes:2024" --no-schedule; rc=$?
check "the folder itself is indexed" '[ $rc = 0 ] && grep -q "collection notes-2024: added $H/notes:2024 " "$C/out"'

echo "== setup: a config path with shell characters"
new_case shellchars Darwin
X="$H/cfg \$(touch $H/PWNED) \"q\""
setup XDG_CONFIG_HOME="$X" -- --root "$H/code" --no-schedule; rc=$?
cmd="$(json "$H/.claude/settings.json" "d[\"hooks\"][\"PostToolUse\"][0][\"hooks\"][0][\"command\"]" | python3 -c "import json,sys; print(json.load(sys.stdin))")"
check "hook command runs the script without expanding the path" '[ $rc = 0 ] && echo garbage | run_sh "$cmd" && [ ! -e "$H/PWNED" ]'

echo "== setup: an earlier qmd hook or LaunchAgent is reported, not duplicated"
new_case prior Darwin
mkdir -p "$H/.claude" "$H/Library/LaunchAgents"
printf '{"hooks": {"PostToolUse": [{"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "bash ~/.config/qmd/on-edit-hook.sh"}]}]}}\n' >"$H/.claude/settings.json"
printf '<plist><dict><key>Label</key><string>com.me.qmd</string></dict></plist>\n' >"$H/Library/LaunchAgents/com.me.qmd.plist"
setup -- --root "$H/code" --dry-run; rc=$?
check "dry run warns about the other LaunchAgent" '[ $rc = 0 ] && grep -q "warning: .*com.me.qmd.plist" "$C/out"'
setup -- --root "$H/code"; rc=$?
check "existing hook kept, none added" '[ $rc = 0 ] && [ "$(json "$H/.claude/settings.json" "len(d[\"hooks\"][\"PostToolUse\"])")" = 1 ] && grep -q "settings.json: kept existing qmd hook" "$C/out"'

echo "== setup: replaced scripts are backed up"
new_case scriptbak Darwin
mkdir -p "$H/.config/qmd"; printf '#!/bin/bash\n# tuned\n' >"$H/.config/qmd/reconcile.sh"
setup -- --root "$H/code" --no-schedule; rc=$?
check "old reconcile.sh kept as a backup" '[ $rc = 0 ] && grep -q tuned "$H/.config/qmd"/reconcile.sh.qmd-backup-*'

# The reconcile and hook cases below exercise the installed scripts directly.
if [ "$(uname -s)" = Darwin ]; then LOGDIR=Library/Logs/qmd; else LOGDIR=.local/state/qmd; fi
mk() { # mk CASE: fresh HOME with reconcile.sh rendered against a stub qmd
  new_case "$1" Darwin; Q="$H/.config/qmd"; mkdir -p "$Q" "$H/bin"; cp "$ST/qmd" "$H/bin/qmd"
  python3 "$HERE/qmd-config.py" render "$HERE/reconcile.sh" QMD_BINARY="$H/bin/qmd" RUNTIME_PATH= XDG_CONFIG_HOME="$H/.config" XDG_CACHE_HOME="$H/.cache" >"$Q/reconcile.sh"
  cp "$HERE/on-edit-hook.sh" "$Q/on-edit-hook.sh"
  LOG="$H/$LOGDIR/reconcile.log"; LK="$H/$LOGDIR/reconcile.lnk"; RR="$H/$LOGDIR/reconcile.rerun"; mkdir -p "$H/$LOGDIR"
}
run() { "${SANDBOX[@]+"${SANDBOX[@]}"}" env -i HOME="$H" PATH="/usr/bin:/bin" TMPDIR="$H/tmp/" STUB_CALLS="$CL" "$@"; }

echo "== reconcile: three callers make two passes"
mk concurrent
run QMD_STUB_SLEEP=2 bash "$Q/reconcile.sh" test & A=$!
sleep 0.5
t0=$(date +%s); run bash "$Q/reconcile.sh" b; rb=$?; run bash "$Q/reconcile.sh" c; rc=$?; t1=$(date +%s)
check "late callers exit 0 at once" '[ $rb = 0 ] && [ $rc = 0 ] && [ $((t1 - t0)) -le 1 ]'
check "lock held during the run" '[ -L "$LK" ]'
wait $A; check "holder exit 0" '[ $? = 0 ]'
check "exactly 2 passes" '[ "$(tr "\n" " " <"$CL/qmd.calls")" = "update embed update embed " ]'
check "lock and rerun flag cleared" '[ ! -L "$LK" ] && [ ! -e "$RR" ]'
check "log summary" 'grep -q "update#2: 3 new, 1 updated, 0 removed" "$LOG" && grep -q "embed#2: .*Done! Embedded 4 chunks" "$LOG"'

echo "== reconcile: stale lock"
mk stale
ln -s 999999 "$LK"
run bash "$Q/reconcile.sh"; check "exit 0" '[ $? = 0 ]'
check "reclaimed" 'grep -q "reclaimed stale lock from pid 999999" "$LOG"'
check "one pass" '[ "$(tr "\n" " " <"$CL/qmd.calls")" = "update embed " ]'
check "no-arg label is manual" 'grep -q "start (manual)" "$LOG"'
check "lock removed" '[ ! -L "$LK" ]'

echo "== reconcile: a caller that arrives after the last rerun check still gets a pass"
mk late
printf '#!/bin/bash\n[ -e "$HOME/slow" ] && sleep 1\nexec /bin/date "$@"\n' >"$H/bin/date"; chmod +x "$H/bin/date"
printf '#!/bin/bash\necho "$1" >>"$STUB_CALLS/qmd.calls"\n[ "$1" = embed ] && [ ! -e "$HOME/slow" ] && touch "$HOME/slow"\nexit 0\n' >"$H/bin/qmd"
run bash "$Q/reconcile.sh" first & A=$!
for _ in $(seq 1 50); do [ -e "$H/slow" ] && break; sleep 0.05; done
sleep 1.5
run bash "$Q/reconcile.sh" late; rl=$?
wait $A
check "late caller exits 0, holder runs a second pass" '[ $rl = 0 ] && [ "$(tr "\n" " " <"$CL/qmd.calls")" = "update embed update embed " ]'
check "rerun flag and lock cleared" '[ ! -e "$RR" ] && [ ! -L "$LK" ]'

echo "== reconcile: live foreign lock"
mk live
sleep 30 & LIVE=$!; ln -s "$LIVE" "$LK"
run bash "$Q/reconcile.sh"; check "exit 0, no qmd call, flag left" '[ $? = 0 ] && [ ! -e "$CL/qmd.calls" ] && [ -e "$RR" ] && [ "$(readlink "$LK")" = "$LIVE" ]'
kill $LIVE; wait $LIVE 2>/dev/null

echo "== reconcile: concurrent reclaim of a stale lock (10 trials x 4 callers)"
overlaps=0 left=0
for i in $(seq 1 10); do
  mk "race$i"
  printf '#!/bin/bash\nif [ "$1" = update ]; then mkdir "$HOME/inflight" 2>/dev/null || echo OVERLAP >>"$HOME/overlap"; sleep 0.3; rmdir "$HOME/inflight"; fi\n' >"$H/bin/qmd"
  ln -s 999997 "$LK"
  for _ in 1 2 3 4; do run bash "$Q/reconcile.sh" r & done; wait
  [ -e "$H/overlap" ] && overlaps=$((overlaps + 1))
  [ -L "$LK" ] && left=$((left + 1))
done
check "no overlapping runs ($overlaps/10), lock released ($left left)" '[ $overlaps = 0 ] && [ $left = 0 ]'

echo "== reconcile: qmd failure"
mk failing
printf '#!/bin/sh\necho "boom: db locked"; exit 3\n' >"$H/bin/qmd"
run bash "$Q/reconcile.sh"; rc=$?
check "exit 1, logged, lock released" '[ $rc = 1 ] && grep -q "ERROR update: boom: db locked" "$LOG" && [ ! -L "$LK" ]'

echo "== on-edit-hook"
mk hook
V="$H/vaults/acme"; mkdir -p "$V/notes" "$H/elsewhere" "$H/q dir" "$H/Bob's notes" "$H/it's" "$H/say \"hi\""; ln -s "$V" "$H/vlink"
printf 'collections:\n  acme:\n    path: %s\n    pattern: "**/*.md"\n  quoted:\n    path: "%s"\n  apos:\n    path: %s\n  sq:\n    path: %s\n  dq:\n    path: %s\n' \
  "$V" "$H/q dir" "$H/Bob's notes" "'$H/it''s'" "$H/say \"hi\"" >"$Q/index.yml"
printf '#!/bin/bash\nsleep 5\necho "$1" >>"$HOME/reconcile.calls"\n' >"$Q/reconcile.sh"
now() { python3 -c 'import time; print(time.time())'; }
fire() { rm -f "$H/reconcile.calls"; local t0; t0=$(now)
  printf '%s' "$1" | run bash "$Q/on-edit-hook.sh"; HRC=$?
  ELAPSED=$(python3 -c "print(round($(now) - $t0, 2))"); }
called() { for _ in $(seq 1 70); do [ -f "$H/reconcile.calls" ] && return 0; sleep 0.1; done; return 1; }
fire "{\"tool_input\":{\"file_path\":\"$V/notes/a.md\"}}"
# The stub reconcile sleeps 5 s, so any time under that proves the hook did not wait for it.
# The margin covers sandbox-exec and python3 startup on a loaded machine.
check "md inside a collection returns without waiting for reconcile ($ELAPSED s)" '[ $HRC = 0 ] && python3 -c "import sys; sys.exit(0 if $ELAPSED < 4 else 1)"'
check "md inside a collection triggers reconcile with label hook" 'called && [ "$(cat "$H/reconcile.calls")" = hook ]'
fire "{\"tool_input\":{\"file_path\":\"$H/vlink/notes/b.md\"}}"; check "symlinked path resolves into the collection" 'called'
fire "{\"tool_input\":{\"file_path\":\"$H/q dir/c.md\"}}"; check "quoted path with a space" 'called'
fire "{\"tool_input\":{\"file_path\":\"$H/Bob's notes/a.md\"}}"; check "path with an apostrophe, as qmd writes it" 'called'
fire "{\"tool_input\":{\"file_path\":\"$H/it's/a.md\"}}"; check "single-quoted path with a doubled apostrophe" 'called'
fire "{\"tool_input\":{\"file_path\":\"$H/say \\\"hi\\\"/a.md\"}}"; check "path with double quotes" 'called'
fire "{\"tool_input\":{\"file_path\":\"$H/elsewhere/a.md\"}}"; sleep 6; check "md outside: no trigger" '[ $HRC = 0 ] && [ ! -f "$H/reconcile.calls" ]'
fire "{\"tool_input\":{\"file_path\":\"$V/notes/a.txt\"}}"; sleep 6; check "non-md: no trigger" '[ $HRC = 0 ] && [ ! -f "$H/reconcile.calls" ]'
fire "{\"tool_input\":{\"file_path\":\"${V}x/a.md\"}}"; sleep 6; check "sibling dir with the same prefix: no trigger" '[ ! -f "$H/reconcile.calls" ]'
fire 'not json'; check "garbage stdin: rc 0" '[ $HRC = 0 ]'
rm "$Q/index.yml"; fire "{\"tool_input\":{\"file_path\":\"$V/notes/a.md\"}}"; sleep 6; check "no index.yml: rc 0, no trigger" '[ $HRC = 0 ] && [ ! -f "$H/reconcile.calls" ]'

echo; [ $fail = 0 ] && echo "ALL QMD CASES PASS" || echo "SOME QMD CASES FAILED"
exit $fail
