---
name: qmd
description: "Set up qmd (https://github.com/tobi/qmd, npm @tobilu/qmd) as keel's local memory layer, so the agent searches recorded memory and task history before answering instead of guessing or rereading whole folders. Walks through installing qmd, choosing collections, embedding, starting the daemon, registering the MCP server, autostarting the watch hook, and wiring hooks/qmd.py's env vars into settings.json and CLAUDE.md. Use for /keel:qmd, or when the user wants memory-first search set up."
disable-model-invocation: true
---

# Set up qmd

[`hooks/qmd.py`](../../hooks/qmd.py) is already part of this plugin: `start` ensures the daemon and the session index are warm every session, `stop` nudges once when a turn searched or read without ever querying qmd. Neither does anything until qmd itself is installed and configured on this machine. This skill does that setup, on the user's machine, outside the plugin, so ask before writing any of their files: propose the exact content, show the diff or command, wait for a yes, the way [`/keel:setup`](../setup/SKILL.md) does. Reversible read-only checks (`--version`, `status`, `--help`) need no ask.

## 1. Check prerequisites

qmd needs Node.js >= 22, or Bun >= 1.0.0. Check with `node --version` (or `bun --version` if the user prefers Bun). If neither clears the floor, stop and report it; installing or upgrading a runtime is the user's call, not this skill's.

Check whether qmd is already on PATH: `command -v qmd` (`where qmd` on Windows). If missing, propose:

```sh
npm install -g @tobilu/qmd
# or, if they use Bun:
bun install -g @tobilu/qmd
```

Verify with `qmd --version`.

## 2. Propose collections

qmd indexes folders of markdown as named collections, each with a glob mask, an optional `ignore` list, and a human-written `context` string that steers which results it returns. Ask what the user has, and propose one `qmd collection add` + `qmd context add` pair per collection they accept:

**A notes vault or second brain**, if they have one (Obsidian, a plain markdown folder, anything similar):

```sh
qmd collection add "<their notes path>" --name vault --mask "**/*.md"
qmd context add qmd://vault "<one line describing what's in it>"
```

**Claude Code's own per-project memory files** (the kind the memory tool writes: user, feedback, project, reference facts), at `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/memory/**/*.md`. Resolve that prefix the way other keel skills do; never hard-code `~/.claude`:

```sh
qmd collection add "<resolved CLAUDE_CONFIG_DIR>/projects" --name claude-memory --mask "*/memory/**/*.md"
qmd context add qmd://claude-memory "Claude Code auto-memory files per project (user, feedback, project, reference facts)."
```

**Each repo's own docs.** Start with the current repo, then ask whether there are others to add. One `repo-<name>` collection per repo:

```sh
qmd collection add "<repo path>" --name repo-<name> --mask "**/*.md"
qmd context add qmd://repo-<name> "Docs of the <name> repo: README, docs, specs. Code itself is not indexed; use grep/LSP."
```

A repo collection also needs an `ignore` list, so a git worktree checked out alongside the repo doesn't get double-indexed. `ignore` has no CLI flag; it is YAML-only, in `~/.config/qmd/index.yml`. After `qmd collection add`, show the user this addition under that collection before writing it:

```yaml
    ignore:
      - "**/wt-*/**"
      - "**/.claude/worktrees/**"
      - "**/.worktrees/**"
```

Keep every `context` string free of literal backslashes inside its double quotes; a pasted Windows path (`C:\Users\...`) breaks the quoting. Describe the content, not a path.

Run `qmd update` once after adding or changing any collection, path, pattern, or `ignore` list.

## 3. Generate embeddings

```sh
qmd embed
```

This downloads the embedding model on first run and can take a while. Let it finish before step 4, so the first real query is not the one stuck waiting on it.

## 4. Start the daemon

```sh
qmd mcp --http --daemon
```

Binds `localhost:8181`, writes its PID to `~/.cache/qmd/mcp.pid`, and serves `POST /mcp` plus `GET /health`. Confirm with `qmd status`, which reports `MCP: running (PID ...)` once it is up.

## 5. Register the MCP server

```sh
claude mcp add --transport http --scope user qmd http://localhost:8181/mcp
```

`--scope user` makes it available in every project, not only this one.

## 6. Autostart the watch loop

`hooks/qmd.py watch` keeps the daemon warm, re-indexes on a *.md change (debounced 10s), and re-embeds after. SessionStart's `start` mode already covers a one-shot update and embed at the top of every session; `watch` is for a machine left running, so a file saved between sessions is searchable before the next one starts. Ask before writing the autostart entry: it changes the user's OS, not just this plugin.

Resolve the plugin root (`${CLAUDE_PLUGIN_ROOT}` inside a session; ask where keel is installed otherwise) and confirm `python3` (or `pythonw`) is on PATH first.

**Windows** — a `.vbs` launcher in the Startup folder, `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\keel-qmd-watch.vbs`, run hidden via `pythonw` (falls back to `python3` if `pythonw` is not installed):

```vbs
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pythonw ""<plugin root>\hooks\qmd.py"" watch", 0, False
```

**macOS** — a launchd user agent, `~/Library/LaunchAgents/com.keel.qmd-watch.plist`, loaded with `launchctl load ~/Library/LaunchAgents/com.keel.qmd-watch.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.keel.qmd-watch</string>
  <key>ProgramArguments</key>
  <array>
    <string>python3</string>
    <string><plugin root>/hooks/qmd.py</string>
    <string>watch</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

**Linux** — a systemd user unit, `~/.config/systemd/user/keel-qmd-watch.service`, enabled with `systemctl --user enable --now keel-qmd-watch.service`:

```ini
[Unit]
Description=keel qmd watch

[Service]
ExecStart=python3 <plugin root>/hooks/qmd.py watch
Restart=on-failure

[Install]
WantedBy=default.target
```

None of these three inherit a Claude Code session's `settings.json` `env` block, so set `KEEL_QMD_WATCH` (step 7's value) directly in the unit/plist/vbs, or in a one-line wrapper script each one calls.

## 7. Set the env vars for Claude Code sessions

Ask before writing. Add to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`'s `env` block, merged in without touching other keys:

```json
{
  "env": {
    "KEEL_QMD_SESSIONS": "<glob patterns to session .jsonl files, os.pathsep-separated>",
    "KEEL_QMD_WATCH": "<directories to poll for *.md changes, os.pathsep-separated>"
  }
}
```

`KEEL_QMD_SESSIONS` feeds `qmd.py start`'s session-to-markdown conversion; unset, that step is skipped. If the user's vault already has a session-history convention, point at it, e.g. `<vault>/*/memory/sessions/*.jsonl`. `KEEL_QMD_WATCH` feeds the autostarted `watch` loop from step 6; a natural value is the same directories as the collections from step 2, joined with the platform's `os.pathsep` (`;` on Windows, `:` elsewhere).

## 8. Write the agent instruction block

Ask before writing. Add a "Memory and task history (qmd)" section to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md`: before answering about past work, project conventions, decisions, or anything that may already be recorded, search with the qmd MCP tools first instead of guessing or rereading whole folders. Name only the collections actually configured in step 2 (no machine-specific paths beyond what the user chose), and state that results are recorded context, not live truth, to verify against the real files before acting on them.

## 9. Verify

Run a typed query through the registered MCP server, not the slow auto-expansion path:

```
mcp__qmd__query(searches=[{"type": "lex", "query": "<a term you know is indexed>"}], rerank=false, limit=1)
```

A hit confirms the daemon, the collection, and the MCP registration all work together. An empty result means checking `qmd status` for that collection's doc count, and whether it still needs `qmd embed`.

## Reply

Name what got installed, which collections were added and with what context strings, where the autostart entry landed for this OS, and the verification query with its result. List anything the user declined, so they know it is still open.
