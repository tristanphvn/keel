# agent-skills

Version-controlled global configuration for a coding agent: the always-on rules, the lazy-loaded skills, and the registry that manages their lifecycle.

Vendor-neutral by design. Nothing here is tied to one agent product — paths resolve through `AGENT_HOME`, and the entrypoint is a plain `AGENTS.md`. Point it at whichever agent you use.

The configuration directory on your machine stays the live system. This repo is a **mirror plus history** — it does not change how anything loads at runtime.

## AGENT_HOME

Every path in this repo resolves against `AGENT_HOME`: the directory your coding agent reads its global configuration from. Set it to that directory; it defaults to `~/.agent`, which is a neutral placeholder rather than any particular product's location.

Files that get installed carry the literal token `{{AGENT_HOME}}` wherever they need an absolute path. `install.sh` renders it to the real path on the way in, and `sync-from-local.sh` folds it back on the way out — so the repo never accumulates one machine's filesystem layout.

## Structure

| Path | Mirrors | What it is |
| --- | --- | --- |
| `rules/` | `$AGENT_HOME/rules/` | Always-on behavior rules, split by concern, imported by `AGENTS.md` (and auto-loaded directly by runtimes that scan the directory) |
| `skills/` | `$AGENT_HOME/skills/` | Lazy-loaded skills, flat `<name>/SKILL.md` — the layout the agent runtime discovers |
| `registry/` | `$AGENT_HOME/skill-registry/` | Lifecycle metadata: ids, domains, status, dependencies, rule linkage |
| `config/` | `$AGENT_HOME/AGENTS.md`, `$AGENT_HOME/learned-rules.md` | The entrypoint that imports the rules, and the post-split redirect shim |
| `config/claude/` | `$AGENT_HOME/CLAUDE.md` (a managed block) | Claude Code adapter: the one place a vendor assumption is allowed |
| `commands/` | `$AGENT_HOME/commands/` | Slash commands. `setup-vault` is a documented dependency of the `vault-rules` skill |
| `docs/` | — | Architecture notes and the migration log |
| `scripts/` | — | Install, sync, and validate helpers |
| `scripts/adapters/` | — | Per-runtime integration, run after `install.sh` |

## Architecture, unchanged

Three layers, deliberately separate:

- **Rules — always on.** Every file in `rules/` is imported by `config/AGENTS.md` and loads in every session. Short behavior statements, no procedures. 28 rule IDs across 10 families: `VERIFY-*`, `SCOPE-*`, `ROOT-*`, `CODE-*`, `TEST-*`, `API-*`, `REVIEW-*`, `CORRECTION-*`, `UI-*`, `CONSENSUS-*`. Each ID is defined exactly once.
- **Skills — lazy.** Loaded only when the task matches. Multi-step workflows live here, never in rules. Runtime discovery requires the flat layout `$AGENT_HOME/skills/<name>/SKILL.md`, so the repo keeps that shape verbatim — **no domain subdirectories**, even though registry ids are domain-prefixed.
- **Registry — management only.** `registry/registry.yaml` carries what `SKILL.md` frontmatter cannot: canonical id, domain, status, `depends_on`, and the `rules:` linkage back into `rules/`. `legacy_name` records the on-disk directory when it does not yet match the `<domain>-<skill-name>` convention.

The id/directory split is intentional. Registry ids are the target names; most directories still carry their legacy names because migration is deliberate and done one skill at a time. `scripts/validate.sh` accepts both and tells you which is which.

## Source of data

Everything under `rules/`, `skills/`, `registry/`, `config/`, and `commands/` originates from a live machine configuration, copied rather than rewritten. The only systematic edits are neutralization: absolute machine paths replaced by `{{AGENT_HOME}}`, and product-specific naming replaced by vendor-neutral terms. Rule logic, skill behavior, constraints, and the validation mechanism are unchanged.

`skills/workos/` and `skills/workos-widgets/` are **vendor skills**, externally maintained and refreshed by the WorkOS installer (`npx skills add workos/skills`). They are mirrored here so a restore is complete, but do not hand-edit them — the installer overwrites. `skills/.workos-skill-version` is their version marker.

## Install / sync

Scripts are bash; on Windows run them from Git Bash, or `bash scripts/<name>.sh` from PowerShell. Both directions default to a **dry run** and print exactly what would change.

```bash
export AGENT_HOME=~/.your-agent-config-dir

# repo -> machine (restore onto a new machine, or apply an update)
bash scripts/install.sh              # preview
bash scripts/install.sh --apply      # writes, after backing up to $AGENT_HOME/backups/install-<timestamp>/

# machine -> repo (capture live edits before committing)
bash scripts/sync-from-local.sh              # preview
bash scripts/sync-from-local.sh --apply      # copies into the working tree only
git diff                                     # review before staging
```

Neither script deletes. `install.sh` reports machine-only files and leaves them alone; `sync-from-local.sh` reports repo-only files so a rename does not leave a stale copy unnoticed. Override the target with `AGENT_HOME=/some/path`.

Both scripts exit non-zero if any write fails or is refused; a dry run writes nothing at all,
not even a directory. `install.sh` backs up to `$AGENT_HOME/backups/install-<timestamp>/` and
**verifies the backup** before the first write — including `CLAUDE.md`, `settings.json` and
`hooks/`, which it never writes but an adapter might.

### Runtime adapters

`rules/`, `skills/`, `registry/` and `config/AGENTS.md` stay vendor-neutral. Anything true of
exactly one runtime lives in an adapter:

```bash
AGENT_HOME=~/.claude bash scripts/adapters/claude.sh            # preview
AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --apply    # writes, after backing up CLAUDE.md
AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --check    # verify an installed setup
AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --remove   # reverse it exactly
```

Claude Code auto-loads `$AGENT_HOME/rules/*.md` and does **not** read `$AGENT_HOME/AGENTS.md`
at user scope, so the adapter deliberately adds no rule imports — that would load every rule
twice. See `config/claude/README.md` for how that was measured.

After `install.sh --apply`, restart your coding agent so the imports and the skill list reload.

## Validate

```bash
bash scripts/validate.sh
```

Read-only. Exits non-zero on failure. Checks:

1. All eight rule files present.
2. Rule IDs unique — no ID defined twice.
3. All ten rule families present.
4. Every skill's frontmatter opens on line 1, has a `description`, and its `name:` matches its directory.
5. Every `status: active` registry entry resolves to a directory (by id or `legacy_name`); non-active entries must *not* have one.
6. No orphan skill directories missing from the registry.
7. Every rule ID referenced by the registry is actually defined in `rules/`.
8. Every `@{{AGENT_HOME}}/...` import in `config/AGENTS.md` resolves inside the repo — and the entrypoint imports *something*, and every `rules/*.md` on disk is imported by it. An entrypoint with its imports deleted used to pass this section vacuously.
9. Portability — no tracked file hardcodes a home directory, a drive letter, or a single vendor's config directory, and installed files use the `{{AGENT_HOME}}` token rather than a shell variable.
10. `registry/registry.yaml` and every `SKILL.md` frontmatter parse under a real YAML parser. `grep`/`awk` accept files PyYAML rejects, which is how an unquoted `{{AGENT_HOME}}` sat in the registry undetected.

What it does **not** do: prove runtime discoverability. A skill is only confirmed live when a fresh agent session lists it.

## What is deliberately not here

Machine-local and private state, excluded by `.gitignore` and never copied: credentials and tokens, `.env` files, `logs/`, `backups/`, `projects/`, `sessions/`, `history.jsonl`, `file-history/`, `paste-cache/`, `plans/`, the `plugins/` cache, and `config.json` / `settings.local.json`, which carry machine paths and per-user permissions.

Also kept out of the tracked content: absolute developer paths, and customer or employer names in examples. Examples use placeholders such as `<customer>` and `<an-existing-slug>` so the instructions stay usable without carrying anyone's identity.

`skills/vault-rules/` and `commands/setup-vault.md` describe a vault convention that lives outside any repo, addressed through `$VAULT_ROOT`. Set that variable to your own location; no default path is assumed.
