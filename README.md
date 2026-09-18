# agent-skills

Version control for my Claude Code global configuration: the always-on rules, the lazy-loaded skills, and the registry that manages their lifecycle.

The machine at `~/.claude/` stays the live system. This repo is a **mirror plus history** — it does not change how anything loads at runtime.

## Structure

| Path | Mirrors | What it is |
| --- | --- | --- |
| `rules/` | `~/.claude/rules/` | Always-on behavior rules, split by concern, imported by `CLAUDE.md` |
| `skills/` | `~/.claude/skills/` | Lazy-loaded skills, flat `<name>/SKILL.md` — the layout Claude Code discovers |
| `registry/` | `~/.claude/skill-registry/` | Lifecycle metadata: ids, domains, status, dependencies, rule linkage |
| `config/` | `~/.claude/CLAUDE.md`, `~/.claude/learned-rules.md` | The entrypoint that imports the rules, and the post-split redirect shim |
| `commands/` | `~/.claude/commands/` | Slash commands. `setup-vault` is a documented dependency of the `vault-rules` skill |
| `docs/` | — | Architecture notes and the migration log |
| `scripts/` | — | Install, sync, and validate helpers |

## Architecture, unchanged

Three layers, deliberately separate:

- **Rules — always on.** Every file in `rules/` is imported by `config/CLAUDE.md` and loads in every session. Short behavior statements, no procedures. 28 rule IDs across 10 families: `VERIFY-*`, `SCOPE-*`, `ROOT-*`, `CODE-*`, `TEST-*`, `API-*`, `REVIEW-*`, `CORRECTION-*`, `UI-*`, `CONSENSUS-*`. Each ID is defined exactly once.
- **Skills — lazy.** Loaded only when the task matches. Multi-step workflows live here, never in rules. Runtime discovery requires the flat layout `~/.claude/skills/<name>/SKILL.md`, so the repo keeps that shape verbatim — **no domain subdirectories**, even though registry ids are domain-prefixed.
- **Registry — management only.** `registry/registry.yaml` carries what `SKILL.md` frontmatter cannot: canonical id, domain, status, `depends_on`, and the `rules:` linkage back into `rules/`. `legacy_name` records the on-disk directory when it does not yet match the `<domain>-<skill-name>` convention.

The id/directory split is intentional. Registry ids are the target names; most directories still carry their legacy names because migration is deliberate and done one skill at a time. `scripts/validate.sh` accepts both and tells you which is which.

## Source of data

Everything under `rules/`, `skills/`, `registry/`, `config/`, and `commands/` was copied byte-for-byte from the live machine — not rewritten, not reformatted. Copy fidelity was verified by `sha256sum` before the first commit.

`skills/workos/` and `skills/workos-widgets/` are **vendor skills**, externally maintained and refreshed by the WorkOS installer (`npx skills add workos/skills`). They are mirrored here so a restore is complete, but do not hand-edit them — the installer overwrites. `skills/.workos-skill-version` is their version marker.

## Install / sync

Scripts are bash; on Windows run them from Git Bash, or `bash scripts/<name>.sh` from PowerShell. Both directions default to a **dry run** and print exactly what would change.

```bash
# repo -> machine (restore onto a new machine, or apply an update)
bash scripts/install.sh              # preview
bash scripts/install.sh --apply      # writes, after backing up to ~/.claude/backups/install-<timestamp>/

# machine -> repo (capture live edits before committing)
bash scripts/sync-from-local.sh              # preview
bash scripts/sync-from-local.sh --apply      # copies into the working tree only
git diff                                     # review before staging
```

Neither script deletes. `install.sh` reports machine-only files and leaves them alone; `sync-from-local.sh` reports repo-only files so a rename does not leave a stale copy unnoticed. Override the target with `CLAUDE_HOME=/some/path`.

After `install.sh --apply`, restart Claude Code so the imports and the skill list reload.

## Validate

```bash
bash scripts/validate.sh
```

Read-only. Exits non-zero on failure. Checks:

1. All seven rule files present.
2. Rule IDs unique — no ID defined twice.
3. All ten rule families present.
4. Every skill's frontmatter opens on line 1, has a `description`, and its `name:` matches its directory.
5. Every `status: active` registry entry resolves to a directory (by id or `legacy_name`); non-active entries must *not* have one.
6. No orphan skill directories missing from the registry.
7. Every rule ID referenced by the registry is actually defined in `rules/`.
8. Every `@~/.claude/...` import in `config/CLAUDE.md` resolves inside the repo.

What it does **not** do: prove runtime discoverability. A skill is only confirmed live when a fresh Claude Code session lists it.

## What is deliberately not here

Machine-local and private state, excluded by `.gitignore` and never copied: credentials and tokens, `.env` files, `logs/`, `backups/`, `projects/`, `sessions/`, `history.jsonl`, `file-history/`, `paste-cache/`, `plans/`, the `plugins/` cache, and `config.json` / `settings.local.json`, which carry machine paths and per-user permissions.

This repo is private. `skills/vault-rules/` and `commands/setup-vault.md` reference client and project naming conventions; keep it that way.
