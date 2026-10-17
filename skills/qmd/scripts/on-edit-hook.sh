#!/bin/bash
# Claude Code PostToolUse (Write|Edit) hook. When a .md file under a collection path in the
# index.yml next to this script changes, start reconcile.sh in the background.
# It returns at once and never fails the session.
INPUT=$(cat 2>/dev/null || true)
HERE="$(cd "$(dirname "$0")" && pwd)"
printf '%s' "$INPUT" | python3 -c '
import json, os, re, sys
try:
    f = (json.load(sys.stdin).get("tool_input") or {}).get("file_path", "")
except Exception:
    sys.exit(1)
if not f.endswith(".md"):
    sys.exit(1)
f = os.path.realpath(f)
cfg = os.path.join(sys.argv[1], "index.yml")
def unquote(v):
    if len(v) >= 2 and v[0] == v[-1] == "\x27":
        return v[1:-1].replace("\x27\x27", "\x27")
    if len(v) >= 2 and v[0] == v[-1] == "\"":
        try:
            return json.loads(v)
        except ValueError:
            return v[1:-1]
    return v
roots = [unquote(v) for v in re.findall(r"^\s+path:\s*(.+?)\s*$", open(cfg).read(), re.M)]
sys.exit(0 if any(f.startswith(os.path.realpath(os.path.expanduser(r)) + "/") for r in roots) else 1)
' "$HERE" 2>/dev/null || exit 0
nohup bash "$HERE/reconcile.sh" hook >/dev/null 2>&1 &
exit 0
