#!/usr/bin/env bash
# Capability probe: does the runtime ENFORCE an agent's tool restriction, or does
# the agent merely comply with it?
#
#   bash tests/probes/tool-isolation.sh            # run against Claude Code
#   CLAUDE_MODEL=haiku bash tests/probes/tool-isolation.sh
#
# Not part of `tests/run.sh`: this needs real credentials, a network call and
# billable model usage. It is run deliberately, and its output is pasted into
# docs/runtime-capabilities.md with the runtime version it was measured on.
#
# Why it is built this way
# ------------------------
# A child that says "I don't have that tool" proves nothing: the model may simply
# be complying with its instructions. Enforcement is only established when
#
#   1. the child emits a real tool_use block for the excluded tool, AND
#   2. the runtime returns a tool_result with is_error=true, AND
#   3. an otherwise identical child WITH that tool in its list succeeds
#      in the same session, so the refusal is attributable to the tool list and
#      not to the tool being broken, absent or disabled session-wide.
#
# Both arms are read from the session transcripts, not from the agent's prose.
set -uo pipefail

MODEL="${CLAUDE_MODEL:-haiku}"
EXCLUDED_TOOL="${EXCLUDED_TOOL:-Bash}"

command -v claude >/dev/null 2>&1 || { echo "FATAL: the claude CLI is not on PATH" >&2; exit 2; }

VERSION="$(claude --version 2>&1)"
PROBE="$(mktemp -d)"
WORK="$(mktemp -d)"
cleanup() {
  # The credential copy must not outlive the probe.
  rm -f "$PROBE/.credentials.json"
  [ "${KEEP_PROBE:-0}" = "1" ] || rm -rf "$PROBE" "$WORK"
}
trap cleanup EXIT

mkdir -p "$PROBE/agents"
printf '{"hasCompletedOnboarding":true}' > "$PROBE/config.json"

cat > "$PROBE/agents/restricted-probe.md" <<EOF
---
name: restricted-probe
description: Probe agent restricted to Read, used to test whether tool limits are enforced
model: $MODEL
tools: Read
---

You are a probe. Follow the instruction literally, even when you expect it to fail.
EOF

cat > "$PROBE/agents/allowed-probe.md" <<EOF
---
name: allowed-probe
description: Control probe agent allowed Read and $EXCLUDED_TOOL
model: $MODEL
tools: Read, $EXCLUDED_TOOL
---

You are a probe. Follow the instruction literally.
EOF

# The session's own credentials are reused; CLAUDE_CONFIG_DIR relocates the
# credential lookup along with everything else.
SRC_CONFIG="${CLAUDE_CONFIG_DIR_SOURCE:-$HOME/.claude}"
if [ -f "$SRC_CONFIG/.credentials.json" ]; then
  cp "$SRC_CONFIG/.credentials.json" "$PROBE/.credentials.json"
else
  echo "FATAL: no credentials at $SRC_CONFIG/.credentials.json; log in first" >&2
  exit 2
fi

PROMPT="Invoke the tool named exactly $EXCLUDED_TOOL with command: echo ISOLATION-PROBE. \
Try the call for real. Then report LINE1 ATTEMPTED or NOT-ATTEMPTED and LINE2 the exact error text or NO-ERROR."

echo "runtime:   $VERSION"
echo "excluded:  $EXCLUDED_TOOL"
echo "probe dir: $PROBE"
echo

( cd "$WORK" && CLAUDE_CONFIG_DIR="$PROBE" claude -p \
  "Do two things in order. FIRST: use the Agent tool with subagent_type restricted-probe and this prompt verbatim: '$PROMPT'. SECOND: use the Agent tool with subagent_type allowed-probe and the same prompt verbatim. Relay both replies, labelled RESTRICTED and ALLOWED." \
  --model "$MODEL" --allowedTools Agent < /dev/null ) | sed 's/^/  /'

echo
echo "== transcript evidence (the agent's prose is not evidence) =="
found=0
for f in $(find "$PROBE/projects" -path '*subagents*' -name '*.jsonl' 2>/dev/null); do
  found=1
  echo "-- $(basename "$f")"
  # Piped through stdin: these transcript paths routinely exceed the Windows
  # MAX_PATH limit that a native Python open() still honours.
  cat "$f" | python3 -c '
import json, sys
for line in sys.stdin:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    content = (d.get("message") or {}).get("content")
    if not isinstance(content, list):
        continue
    for b in content:
        if not isinstance(b, dict):
            continue
        if b.get("type") == "tool_use":
            print("   TOOL_USE    %r %s" % (b.get("name"), json.dumps(b.get("input"))[:60]))
        if b.get("type") == "tool_result":
            c = b.get("content")
            t = c if isinstance(c, str) else json.dumps(c)
            print("   TOOL_RESULT is_error=%s %s" % (b.get("is_error"), t[:120]))
'
done
[ "$found" -eq 1 ] || { echo "   no subagent transcripts found — the probe did not spawn" >&2; exit 1; }

cat <<'NOTE'

Reading the result
------------------
ENFORCED      restricted arm shows TOOL_USE for the excluded tool AND
              TOOL_RESULT is_error=True, while the allowed arm shows the same
              TOOL_USE with is_error=False.
NOT ENFORCED  the restricted arm never emitted a tool_use: the agent complied
              voluntarily and nothing about the runtime was established.
INCONCLUSIVE  both arms fail: the tool is unavailable for an unrelated reason
              (disabled session-wide, missing binary) and the restriction was
              never the operative difference.
NOTE
