---
name: qmd
description: Set up local markdown search with qmd as one global index that every Claude Code profile and project on the machine shares. Adds the folders the user picks, then wires the active profile with the qmd MCP server, an edit hook, a scheduled refresh, and CLAUDE.md search guidance. Use for /keel:qmd, "set up qmd", or "search my notes/vault across projects".
disable-model-invocation: true
---

# qmd

Set up [qmd](https://github.com/tobi/qmd) so agents in every profile and project can search the user's markdown through one index. qmd keeps that index at its default locations, `${XDG_CONFIG_HOME:-$HOME/.config}/qmd/index.yml` for the collection list and `~/.cache/qmd` for the database and models. Nothing here sets `QMD_CONFIG_DIR` or makes a per-profile index.

`scripts/setup-qmd.sh` makes every change and is safe to re-run. Your job is to choose its inputs with the user, run it, check the result, and report. Call it as `bash "${CLAUDE_SKILL_DIR}/scripts/setup-qmd.sh"`.

## Steps

### 1. Detect

1. Run the script with `--dry-run` and no other flags. It finds qmd on `PATH`, then at `~/.bun/bin/qmd`, then under `$(npm prefix -g)/bin`.
2. Exit code 3 means qmd is missing. Ask the user before you install it. Offer `bun install -g @tobilu/qmd` when `command -v bun` succeeds, else `npm install -g @tobilu/qmd`. Install only on a yes, then run step 1 again.
3. Tell the user which profile the run wires, from `echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`. Each profile needs its own run. The index is shared, so a second profile's run needs no `--root`.
4. Run `<qmd> collection list` with the absolute path the script printed, so the user sees what the index already holds. If it fails with `node: not found` or `bun: not found`, the runtime qmd was installed with is not on `PATH`. Fix that before you go on.
5. Look for an earlier qmd setup. List `~/Library/LaunchAgents/*qmd*` on macOS or `crontab -l | grep qmd` elsewhere, and grep the profile's `settings.json` for `qmd` and `on-edit-hook`. The dry run also warns about another LaunchAgent that mentions qmd, and keeps a hook that already runs `on-edit-hook.sh` instead of adding a second one. If you find a scheduler or hook this script did not make, ask the user whether to remove it or keep it before the real run.

### 2. Pick what to index

1. Run the script with `--discover`. It counts `*.md` under each folder in `$HOME` and one level below, skipping `node_modules`, `.git`, `dist`, `build`, `vendor`, and dot folders.
2. Suggest roots from that list and ask with AskUserQuestion, `multiSelect: true`, at most four options. Prefer one collection per root folder, such as a code folder with one subfolder per project, so a new project under it gets indexed without a re-run. The script skips a root that sits inside an existing collection.
3. Ask whether to index this profile's Claude Code auto-memory too (`--memory`). It adds `<profile>/projects` with the pattern `*/memory/**/*.md` and ignores the `-private-tmp-*` and `-tmp-*` project folders that scratch sessions leave.
4. Offer a one-line description per root. qmd shows it to agents next to search results.

### 3. Run

Run with `--dry-run` and the chosen flags, then read the output. If it would change anything the user did not choose, stop and ask. Otherwise run the same command without `--dry-run`.

| Flag | Effect |
|---|---|
| `--root PATH[:NAME]` | Add a collection of every `*.md` under `PATH`. `NAME` defaults to the folder name, lowercased, with each character outside `a-z0-9_-` turned into `-`. A `PATH` that is itself a folder is never split at a colon. Repeat per root. |
| `--context NAME:TEXT` | Attach a description to collection `NAME`. Repeat per collection. Pass an explicit `PATH:NAME` on the matching `--root`, so the two names agree. |
| `--memory` | Add this profile's auto-memory folders as `<profile-dir-name>-memory`. |
| `--no-schedule` | Skip the scheduled refresh. `QMD_SCHEDULE=0` does the same. |
| `--dry-run` | Print what would change and write nothing. |

`QMD_LAUNCHD_LABEL` overrides the LaunchAgent label, `local.qmd.reconcile` by default.

### 4. Verify

1. `<qmd> collection list` shows each chosen root, or the script printed why it skipped one.
2. `claude mcp get qmd` finds the server. Without the `claude` CLI, check that `mcpServers.qmd` exists in the `.claude.json` path the script printed.
3. The profile's `settings.json` has a `PostToolUse` entry whose command runs `on-edit-hook.sh`, as the script's `PostToolUse hook` line reported.
4. `tail -n 5` on the log path the script printed shows a `start (...)` line within a minute. On macOS the LaunchAgent runs it at load.
5. `<qmd> status` shows documents waiting for embeddings, and its Device section shows whether qmd found a GPU.

### 5. Report

Tell the user what each collection holds, which profile you wired, and that Claude Code needs a restart to load the MCP server and hook. Give the two commands the script printed for watching progress. On a CPU-only machine the first embed can take hours for about 1000 documents. Searches work before it ends, and lexical results come first.

## What the script writes

| What | Where |
|---|---|
| Collections | `index.yml`, through `qmd collection add` and `qmd context add` only. `collection add` builds the keyword index for that root before it returns, which takes a while on a big root. It skips a name that exists and a path inside an existing collection. The one direct edit adds an `ignore:` list to the memory collection, since the CLI cannot set one. qmd keeps that list when it rewrites the file. |
| `reconcile.sh`, `on-edit-hook.sh` | Next to `index.yml`. `reconcile.sh` runs `qmd update` then `qmd embed` at `nice 15`, one run at a time, with up to five passes while edits keep arriving. qmd's launcher runs under `node` or `bun` and launchd passes a bare `PATH`, so it puts qmd's own folder, the folders where setup found `node` and `bun`, `~/.bun/bin`, `/usr/local/bin`, and `/opt/homebrew/bin` on `PATH`. It logs to `~/Library/Logs/qmd/reconcile.log` on macOS, else `${XDG_STATE_HOME:-~/.local/state}/qmd/reconcile.log`. The hook starts it in the background when a Write or Edit touches a `.md` file inside a collection, and returns at once. |
| MCP server `qmd` | User scope, through `claude mcp add -s user qmd -- <qmd> mcp`. Claude Code keeps it in `$CLAUDE_CONFIG_DIR/.claude.json` when that variable is set, else `~/.claude.json`. Without the `claude` CLI the script merges the entry into that file itself. |
| PostToolUse hook | `<profile>/settings.json`, matcher `Write\|Edit`, timeout 10. |
| Search guidance | `<profile>/CLAUDE.md`, between `<!-- keel:qmd start -->` and `<!-- keel:qmd end -->`. A re-run replaces the block in place. |
| Scheduled refresh | macOS gets `~/Library/LaunchAgents/<label>.plist`, every 1800 s, `RunAtLoad`, `Nice 15`, `LowPriorityIO`. The script bootstraps it only when `launchctl print gui/$UID/<label>` fails. Other systems get a cron line to add by hand. |

The first `reconcile.sh` run starts in the background, from the LaunchAgent or from the script, so setup never waits for embeddings.

Before it rewrites `settings.json`, `CLAUDE.md`, `.claude.json`, `index.yml`, `reconcile.sh`, or `on-edit-hook.sh`, the script copies the old file next to it as `<file>.qmd-backup-<timestamp>`. The plist's backup goes next to `reconcile.sh`, because launchd may load any file in `LaunchAgents`. A rewrite follows a symlink to its target and keeps the file's mode. A config file that is not valid JSON stops the run with an error that names it, and nothing in that file changes.

The CLAUDE.md block's rerank line follows the Device section of `qmd status`, which takes under a second. With `GPU: none` it tells agents to always pass `rerank: false`, because on a CPU-only Intel i7 a reranked query took over 240 s, while lex took about 3 s and vec about 7 s. With a GPU it leaves the line out. When status names neither, as under `--dry-run`, the line says to pass `rerank: false` when `qmd status` shows no GPU. A re-run on new hardware rewrites the line.

## Undo

Run these for each profile you wired, with `P="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`.

1. Run `claude mcp remove -s user qmd`. Without the `claude` CLI, delete `mcpServers.qmd` from `$CLAUDE_CONFIG_DIR/.claude.json` when that variable is set, else from `~/.claude.json`.
2. Delete the `PostToolUse` entry whose command runs `on-edit-hook.sh` from `$P/settings.json`.
3. Delete the block between the `keel:qmd` markers in `$P/CLAUDE.md`.

Then once per machine:

1. On macOS, run `launchctl bootout gui/$(id -u)/<label>` and delete `~/Library/LaunchAgents/<label>.plist`. The label is `local.qmd.reconcile` unless `QMD_LAUNCHD_LABEL` set another at setup. Elsewhere, remove the cron line.
2. Delete `reconcile.sh`, `on-edit-hook.sh`, and any `*.qmd-backup-*` files from `${XDG_CONFIG_HOME:-$HOME/.config}/qmd/`, and the log folder, `~/Library/Logs/qmd` on macOS or `${XDG_STATE_HOME:-$HOME/.local/state}/qmd` elsewhere.
3. To drop the index too, run `qmd collection remove <name>` for each collection, or delete `index.yml` and `~/.cache/qmd`, which also holds the downloaded models.
