#!/usr/bin/env python3
# Make every turn dig before it answers and review before it ends.
#   think.py start  (UserPromptSubmit) injects the dig protocol on every prompt.
#   think.py stop   (Stop) blocks the first stop of each turn with the review checklist. Claude Code sets
#                   stop_hook_active on the continuation, so the turn ends on the second stop.
# Set KEEL_THINK=off to silence both.
import json, os, sys

DIG = (
    "keel think: before you answer, dig, scaled to the request. "
    "An acknowledgement or small talk gets a direct reply, with no tool calls. "
    "1. Restate what the operator actually needs, including the goal behind the literal ask. "
    "2. Gather evidence from the real source (files, commands, docs, tool output) instead of answering from memory. "
    "3. Weigh at least two approaches and pick one for a stated reason. "
    "4. Trace causes to the root, not the first symptom. "
    "5. Check edge cases and what could make the answer wrong. "
    "6. Decide how you will verify the result before you call it done."
)

REVIEW = (
    "keel think: review the answer you just gave. Check it against each point: "
    "1. Does it answer what the operator actually needs, not only the literal words? "
    "2. Is every claim backed by evidence you gathered this turn, or labeled as inferred or a guess? "
    "3. Did you reach the root cause, or stop at a symptom? "
    "4. Is there a better approach, a missed edge case, or a risk you did not state? "
    "5. Is there a quick read-only check you could still run instead of asking the operator to run it? "
    "This review covers only that answer. Do not start new work, do not act past a stop or approval gate the "
    "operator set, and do not poll or redo work that running subagents own. A turn that waits on the operator or "
    "on subagents only confirms its state. "
    "If something fails, fix it now and send the corrected answer in full. "
    "If everything holds, end with one line that restates the key result and names what you verified, so a reader "
    "who sees only this last message still has the answer. Do not repeat the rest of an unchanged answer."
)


def read_event():
    try:
        event = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    except ValueError:
        return {}
    return event if isinstance(event, dict) else {}


def start():
    read_event()
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": DIG}}


def stop():
    active = read_event().get("stop_hook_active")
    if active is False:
        return {"decision": "block", "reason": REVIEW}
    if active is not True:
        print("keel think: Stop event has no boolean stop_hook_active; skipped the review.", file=sys.stderr)
    return None


MODES = {"start": start, "stop": stop}


def main():
    mode = MODES.get(sys.argv[1] if len(sys.argv) > 1 else "")
    if mode is None or os.environ.get("KEEL_THINK", "on") == "off":
        return
    output = mode()
    if output:
        json.dump(output, sys.stdout)


if __name__ == "__main__":
    main()
