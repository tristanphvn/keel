#!/usr/bin/env bash
# Capability probe: does a spawned child start WITHOUT the parent's conversation
# state, or does it inherit it?
#
#   bash tests/probes/fresh-context.sh
#
# Not part of `tests/run.sh`: needs credentials, network and billable usage.
#
# Why two canaries
# ----------------
# Asking a child "do you remember X" establishes nothing on its own: a child that
# has X may decline to say so, and a child that lacks X may guess. So the probe
# runs two canaries through two different channels in one session:
#
#   SESSION canary  stated only in the parent's conversation. Never written to
#                   disk, never in the agent definition, never in the child's
#                   prompt, never in the environment or argv.
#   PROMPT canary   passed to the child in its own prompt.
#
# The child is asked to report every canary it can see.
#
#   fresh      PROMPT reported, SESSION absent — the child reports canaries it
#              genuinely has, and the session one is not among them.
#   leaking    SESSION reported — parent conversation state reached the child.
#   inconclusive
#              PROMPT also absent — the child is not reporting what it has, so
#              the SESSION absence proves nothing about context isolation.
#
# Both canaries are random per run, so neither can be guessed or memorised.
set -uo pipefail

MODEL="${CLAUDE_MODEL:-haiku}"
command -v claude >/dev/null 2>&1 || { echo "FATAL: the claude CLI is not on PATH" >&2; exit 2; }

VERSION="$(claude --version 2>&1)"
PROBE="$(mktemp -d)"
WORK="$(mktemp -d)"
cleanup() {
  rm -f "$PROBE/.credentials.json"
  [ "${KEEP_PROBE:-0}" = "1" ] || rm -rf "$PROBE" "$WORK"
}
trap cleanup EXIT

rand() { head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | tr 'a-f' 'A-F'; }
SESSION_CANARY="SESSION-$(rand)"
PROMPT_CANARY="PROMPT-$(rand)"

mkdir -p "$PROBE/agents"
printf '{"hasCompletedOnboarding":true}' > "$PROBE/config.json"
cat > "$PROBE/agents/context-probe.md" <<EOF
---
name: context-probe
description: Probe agent used to measure whether a child inherits parent conversation state
model: $MODEL
tools: Read
---

You are a probe. Report exactly what is asked, from your own context only.
EOF

SRC_CONFIG="${CLAUDE_CONFIG_DIR_SOURCE:-$HOME/.claude}"
[ -f "$SRC_CONFIG/.credentials.json" ] || { echo "FATAL: no credentials at $SRC_CONFIG" >&2; exit 2; }
cp "$SRC_CONFIG/.credentials.json" "$PROBE/.credentials.json"

echo "runtime:  $VERSION"
echo "platform: $(uname -s)"
echo "session canary: $SESSION_CANARY"
echo "prompt canary:  $PROMPT_CANARY"
echo

# The session canary enters the parent's conversation and nothing else. The
# child's prompt carries only the prompt canary.
OUT="$( cd "$WORK" && CLAUDE_CONFIG_DIR="$PROBE" claude -p \
  "Remember this value for later in our conversation: $SESSION_CANARY. Do not write it to any file. \
Now use the Agent tool once with subagent_type context-probe, and give it exactly this prompt, \
with no additions: 'Your prompt canary is $PROMPT_CANARY. From your own context only, list every \
token you can see that starts with SESSION- or PROMPT-, one per line. If you can see none of a \
kind, write NONE for that kind. Do not guess.' Relay the child's reply verbatim and add nothing." \
  --model "$MODEL" --allowedTools Agent < /dev/null 2>&1 )"

printf '%s\n' "$OUT" | sed 's/^/  /'
echo
echo "== verdict =="
saw_prompt=0; saw_session=0
printf '%s' "$OUT" | grep -qF "$PROMPT_CANARY"  && saw_prompt=1
printf '%s' "$OUT" | grep -qF "$SESSION_CANARY" && saw_session=1

# The parent relays the child's reply, so the parent's own echo of the session
# canary would be indistinguishable from leakage in the combined output. Confirm
# against the child's transcript instead.
child_has_session=0
for f in $(find "$PROBE/projects" -path '*subagents*' -name '*.jsonl' 2>/dev/null); do
  cat "$f" | grep -qF "$SESSION_CANARY" && child_has_session=1
done

echo "  prompt canary visible to child: $saw_prompt"
echo "  session canary in child transcript: $child_has_session"
if [ "$child_has_session" -eq 1 ]; then
  echo "  RESULT: LEAKING — parent conversation state reached the child"
  exit 1
fi
if [ "$saw_prompt" -eq 0 ]; then
  echo "  RESULT: INCONCLUSIVE — the child did not report the canary it was given,"
  echo "          so its silence about the session canary establishes nothing"
  exit 3
fi
echo "  RESULT: FRESH — the child reported the canary it had and never held the session canary"
