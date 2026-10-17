#!/usr/bin/env python3
"""Small, idempotent edits to the files setup-qmd.sh touches. Each write subcommand prints
"changed", "unchanged", or under --dry-run "would change". A rewrite goes through a symlink to
its target, keeps the file's mode, and leaves a backup next to it."""

from __future__ import annotations

import json
import os
import plistlib
import re
import shlex
import shutil
import stat
import sys
import time

DRY = "--dry-run" in sys.argv
ARGS = [a for a in sys.argv[1:] if a != "--dry-run"]


def indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def collection_blocks(lines: list[str]) -> dict[str, tuple[int, int]]:
    """Map each collection name to its [start, end) line span in index.yml."""
    try:
        top = next(i for i, l in enumerate(lines) if re.match(r"collections:\s*$", l))
    except StopIteration:
        return {}
    blocks: dict[str, tuple[int, int]] = {}
    name_indent = None
    current = None
    end = len(lines)
    for i in range(top + 1, len(lines)):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if indent(line) == 0:
            end = i
            break
        if name_indent is None:
            name_indent = indent(line)
        if indent(line) == name_indent:
            if current:
                blocks[current[0]] = (current[1], i)
            current = (unquote(line.strip().rstrip(":")), i)
    if current:
        blocks[current[0]] = (current[1], end)
    return blocks


def read_lines(path: str) -> list[str]:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def backup(path: str, into: str | None = None) -> None:
    name = f"{os.path.basename(path)}.qmd-backup-{time.strftime('%Y%m%d%H%M%S')}"
    shutil.copy2(path, os.path.join(into or os.path.dirname(path), name))


def write(path: str, data: str | bytes, backup_dir: str | None = None) -> None:
    if DRY:
        print("would change")
        return
    path = os.path.realpath(path)
    if os.path.exists(path):
        mode = stat.S_IMODE(os.stat(path).st_mode)
        backup(path, backup_dir)
    else:
        # .claude.json holds account data, so a new one is private like Claude Code's own.
        mode = 0o600 if os.path.basename(path) == ".claude.json" else 0o666 & ~current_umask()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp-{os.getpid()}"
    with open(tmp, "wb") as f:
        f.write(data.encode("utf-8") if isinstance(data, str) else data)
    os.chmod(tmp, mode)
    os.replace(tmp, path)
    print("changed")


def current_umask() -> int:
    mask = os.umask(0)
    os.umask(mask)
    return mask


def collections(index: str) -> None:
    lines = read_lines(index)
    for name, (start, end) in collection_blocks(lines).items():
        for line in lines[start + 1:end]:
            m = re.match(r"\s+path:\s*(.+?)\s*$", line)
            if m:
                print(f"{name}\t{unquote(m.group(1))}")
                break


def add_ignore(index: str, name: str, *patterns: str) -> None:
    lines = read_lines(index)
    span = collection_blocks(lines).get(name)
    if not span:
        raise SystemExit(f"collection {name} not found in {index}")
    start, end = span
    while end > start + 1 and not lines[end - 1].strip():
        end -= 1
    prop = indent(lines[start + 1]) if end > start + 1 else indent(lines[start]) + 2
    body = lines[start + 1:end]
    have = {unquote(l.strip()[1:]) for l in body if l.strip().startswith("- ")}
    missing = [p for p in patterns if p not in have]
    if not missing:
        print("unchanged")
        return
    items = [" " * (prop + 2) + "- " + json.dumps(p) for p in missing]
    at = next((start + 1 + i for i, l in enumerate(body) if indent(l) == prop and l.strip() == "ignore:"), None)
    if at is None:
        insert, new = end, [" " * prop + "ignore:"] + items
    else:
        insert = at + 1
        while insert < end and (indent(lines[insert]) > prop or lines[insert].strip().startswith("- ")):
            insert += 1
        new = items
    lines[insert:insert] = new
    write(index, "\n".join(lines) + "\n")


def load_json(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as e:
        raise SystemExit(f"{path} is not valid JSON ({e}). Fix it, then re-run.")
    if not isinstance(data, dict):
        raise SystemExit(f"{path} does not hold a JSON object. Fix it, then re-run.")
    return data


def child(parent: dict, key: str, kind: type, path: str):
    """parent[key], created empty when missing or null, refused when it has another type."""
    if parent.get(key) is None:
        parent[key] = kind()
    if not isinstance(parent[key], kind):
        raise SystemExit(f"{key} in {path} is not a JSON {kind.__name__.replace('dict', 'object')}. Fix it, then re-run.")
    return parent[key]


def has_mcp(path: str) -> None:
    raise SystemExit(0 if "qmd" in (load_json(path).get("mcpServers") or {}) else 1)


def mcp(path: str, qmd: str) -> None:
    data = load_json(path)
    servers = child(data, "mcpServers", dict, path)
    if "qmd" in servers:
        print("unchanged")
        return
    servers["qmd"] = {"type": "stdio", "command": qmd, "args": ["mcp"], "env": {}}
    write(path, json.dumps(data, indent=2) + "\n")


def hook(path: str, script: str) -> None:
    data = load_json(path)
    entries = child(child(data, "hooks", dict, path), "PostToolUse", list, path)
    command = "bash " + shlex.quote(script)
    commands = [h.get("command", "") for e in entries if isinstance(e, dict)
                for h in e.get("hooks") or [] if isinstance(h, dict)]
    if command in commands:
        print("unchanged")
        return
    other = next((c for c in commands if "on-edit-hook.sh" in c), None)
    if other:
        print(f"kept existing qmd hook ({other})")
        return
    entries.append({"matcher": "Write|Edit", "hooks": [{"type": "command", "command": command, "timeout": 10}]})
    write(path, json.dumps(data, indent=2) + "\n")


def claude_md(path: str) -> None:
    block = sys.stdin.read().rstrip("\n") + "\n"
    start, end = block.splitlines()[0], block.splitlines()[-1]
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        text = ""
    m = re.search(re.escape(start) + r".*?" + re.escape(end) + r"\n?", text, re.S)
    if m:
        new = text[:m.start()] + block + text[m.end():]
    elif not text or text.endswith("\n\n"):
        new = text + block
    else:
        new = text + ("\n" if text.endswith("\n") else "\n\n") + block
    if new == text:
        print("unchanged")
        return
    write(path, new)


def plist(path: str, label: str, reconcile: str) -> None:
    data = plistlib.dumps({
        "Label": label,
        "ProgramArguments": ["/bin/bash", reconcile, "launchd"],
        "StartInterval": 1800,
        "RunAtLoad": True,
        "Nice": 15,
        "LowPriorityIO": True,
        "ProcessType": "Background",
        "StandardOutPath": "/dev/null",
        "StandardErrorPath": "/dev/null",
    })
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                print("unchanged")
                return
    except FileNotFoundError:
        pass
    # The backup goes next to reconcile.sh, since launchd may load any file in LaunchAgents.
    write(path, data, os.path.dirname(reconcile))


def render(template: str, *pairs: str) -> None:
    with open(template, encoding="utf-8") as f:
        text = f.read()
    for pair in pairs:
        key, _, value = pair.partition("=")
        text = text.replace("{{" + key + "}}", shlex.quote(value))
    sys.stdout.write(text)


COMMANDS = {"collections": collections, "add-ignore": add_ignore, "has-mcp": has_mcp, "mcp": mcp,
            "hook": hook, "claude-md": claude_md, "plist": plist, "render": render}

if __name__ == "__main__":
    if not ARGS or ARGS[0] not in COMMANDS:
        raise SystemExit(f"usage: qmd-config.py {{{','.join(COMMANDS)}}} ARGS... [--dry-run]")
    try:
        COMMANDS[ARGS[0]](*ARGS[1:])
    except SystemExit as e:
        if isinstance(e.code, str):
            raise SystemExit(f"error: {e.code}")
        raise
