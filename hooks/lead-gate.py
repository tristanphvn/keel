#!/usr/bin/env python3
# Turns the lead reminder into a gate. Until keel:lead is loaded in a session, every tool call is denied except
# the ones that load it (Skill, a Read of the lead's SKILL.md) and the ones that cannot touch the workspace
# (ToolSearch, AskUserQuestion). A reply that needs no tool is never gated. The gate fails open when it cannot
# know the session or cannot write its marker, so a broken install never locks an agent out. Set KEEL_LEAD_GATE=off
# to disable it.
#
#   lead-gate.py prompt   UserPromptSubmit: a typed /keel:lead opens the gate
#   lead-gate.py mark     PostToolUse on Skill|Read: loading the lead opens the gate
#   lead-gate.py gate     PreToolUse on every tool
import json, os, pathlib, posixpath, re, sys, time

ALWAYS_ALLOWED = {"Skill", "ToolSearch", "AskUserQuestion"}
LEAD_SKILL = "keel:lead"
LEAD_SKILL_FILE = re.compile(r"/keel[^/]*/.*skills/lead/skill\.md$")
TYPED_LEAD = re.compile(r"^\s*/keel:lead\b", re.IGNORECASE)
STALE_SECONDS = 30 * 24 * 3600

DENY_REASON = (
    "keel lead gate: load the keel:lead skill before any other tool in this session "
    '(Skill tool, skill="keel:lead"), then follow its playbook. Set KEEL_LEAD_GATE=off to disable the gate.'
)


def marker_dir():
    root = os.environ.get("CLAUDE_CONFIG_DIR") or str(pathlib.Path.home() / ".claude")
    return pathlib.Path(root) / ".keel-lead-gate"


def marker(data):
    session = re.sub(r"[^A-Za-z0-9_-]", "_", str(data.get("session_id") or ""))
    return marker_dir() / (session + ".open") if session else None


def normalized(path):
    return posixpath.normpath(str(path).replace("\\", "/")).lower()


def is_lead_skill_file(path):
    root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if root:
        return normalized(path) == normalized(root + "/skills/lead/SKILL.md")
    return bool(LEAD_SKILL_FILE.search(normalized(path)))


def loads_lead(data):
    tool = data.get("tool_name") or ""
    args = data.get("tool_input") or {}
    if tool == "Skill":
        return str(args.get("skill", "")).strip().lower() == LEAD_SKILL
    if tool == "Read":
        return is_lead_skill_file(args.get("file_path", ""))
    return False


def open_gate(data):
    directory = marker_dir()
    try:
        directory.mkdir(parents=True, exist_ok=True)
        marker(data).write_text("1", encoding="utf-8")
    except OSError:
        return
    cutoff = time.time() - STALE_SECONDS
    for old in directory.glob("*.open"):
        try:
            if old.stat().st_mtime < cutoff:
                old.unlink()
        except OSError:
            pass


def writable(directory):
    try:
        directory.mkdir(parents=True, exist_ok=True)
    except OSError:
        return False
    return os.access(directory, os.W_OK)


def main():
    if os.environ.get("KEEL_LEAD_GATE", "on") == "off":
        return
    mode = sys.argv[1] if len(sys.argv) > 1 else "gate"
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
    except ValueError:
        return
    if not isinstance(data, dict) or marker(data) is None:
        return

    if mode == "prompt":
        if TYPED_LEAD.match(str(data.get("prompt") or "")):
            open_gate(data)
        return
    if mode == "mark":
        if loads_lead(data):
            open_gate(data)
        return

    if (data.get("tool_name") or "") in ALWAYS_ALLOWED or loads_lead(data) or marker(data).exists():
        return
    if not writable(marker_dir()):
        return
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": DENY_REASON,
    }}, sys.stdout)


if __name__ == "__main__":
    main()
