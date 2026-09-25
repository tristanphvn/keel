#!/usr/bin/env bash
# Capability probe: are tool PERMISSIONS enforced for a parent session and for a
# general-purpose sub-agent it spawns, and what does each CLI flag control?
#
#   bash tests/probes/permission-enforcement.sh
#   CLAUDE_MODEL=sonnet bash tests/probes/permission-enforcement.sh
#
# Not part of `tests/run.sh`: it needs a signed-in CLI, a network call and
# billable model usage. It runs with the caller's existing sign-in — it copies no
# credential and changes no setting — in a throwaway git repository, and every
# command it asks for is harmless: a version query, a read-only listing, and an
# `echo` into a file inside that repository.
#
# Two properties are kept apart, because they are different mechanisms:
#
#   availability  whether a tool is in the session's tool list at all
#                 (`--tools`, an agent definition's `tools:`)
#   permission    whether a call to an available tool is approved
#                 (`--allowedTools` pre-approves; anything else needs approval,
#                 which a non-interactive session cannot give)
#
# A refusal counts only when a real tool_use is answered by a tool_result with
# is_error=true, read from the stream, not from the model's prose.
set -uo pipefail

MODEL="${CLAUDE_MODEL:-haiku}"
command -v claude >/dev/null 2>&1 || { echo "FATAL: the claude CLI is not on PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 && PY=python3 || PY=python
VERSION="$(claude --version 2>&1)"
WORK="$(mktemp -d)"
cleanup() { [ "${KEEP_PROBE:-0}" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT
cd "$WORK" || exit 2
git init -q . && printf 'synthetic\n' > readme.txt

LISTING='git status --short && find . -path ./.git -prune -o -type f -print'
direct() { printf 'Run exactly these shell commands with the Bash tool, one call each, even if you expect a refusal: (1) git --version (2) %s (3) echo %s > %s.txt . Report each tool result verbatim. Use no other tool.' "$LISTING" "$1" "$1"; }
delegate() { printf 'Use the Agent tool with subagent_type general-purpose. Give the subagent this task verbatim: "%s" Relay its report.' "$(direct "$1")"; }

run() { # run ARM PROMPT FLAGS...
  _arm="$1"; _prompt="$2"; shift 2
  claude -p "$_prompt" --model "$MODEL" --permission-mode default "$@" \
    --output-format stream-json --verbose < /dev/null > "$_arm.jsonl" 2>/dev/null
}

run parent-allow-read  "$(direct parent)" --allowedTools "Read" &
run child-allow-agent  "$(delegate child)" --allowedTools "Agent,Read" &
run child-tools-agent  "$(delegate childtools)" --tools "Agent,Read" --allowedTools "Agent,Read" &
wait

echo "runtime: $VERSION   model: $MODEL"
for arm in parent-allow-read child-allow-agent child-tools-agent; do
  echo
  echo "== $arm =="
  "$PY" - "$arm.jsonl" <<'EOF'
import json, sys
names = {}
for line in open(sys.argv[1], encoding="utf-8"):
    d = json.loads(line)
    who = "child " if d.get("parent_tool_use_id") else "parent"
    if d.get("type") == "system" and d.get("subtype") == "init" and not d.get("parent_tool_use_id"):
        tools = [t for t in d.get("tools", []) if not t.startswith("mcp__")]
        print("  %s mode=%s bash_available=%s" % (who, d.get("permissionMode"), "Bash" in tools))
    if d.get("type") == "assistant":
        for c in d["message"]["content"]:
            if c["type"] == "tool_use":
                names[c["id"]] = (c["name"], json.dumps(c["input"].get("command", ""))[:70])
    if d.get("type") == "user" and isinstance(d["message"].get("content"), list):
        for c in d["message"]["content"]:
            if c.get("type") == "tool_result" and c["tool_use_id"] in names:
                n, cmd = names[c["tool_use_id"]]
                if n == "Bash":
                    print("  %s TOOL_USE Bash %s -> is_error=%s" % (who, cmd, bool(c.get("is_error"))))
EOF
done
echo
for f in parent child childtools; do
  [ -e "$WORK/$f.txt" ] && echo "WRITE $f.txt: EXECUTED" || echo "WRITE $f.txt: not executed"
done
