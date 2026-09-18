# Architecture

Why the configuration is split the way it is. Decisions recorded here are already in effect on the machine; this file explains them, it does not propose them.

## Layer separation

```
config/AGENTS.md          always loaded — imports every rule file
  └── rules/*.md          always on: short behavior statements, no procedures
skills/<name>/SKILL.md    lazy: loaded only when the task matches the description
registry/registry.yaml    management metadata only: never loaded at runtime
```

The boundary that matters: **rules state behavior, skills carry procedure.** A multi-step workflow in a rule file would load on every single turn and pay its token cost whether or not it is relevant. A behavior rule inside a skill would only apply when that skill happened to trigger, which defeats the point of a rule.

## Why rules are split into files

They were one file (`learned-rules.md`). Split by concern on 2026-09-17 into seven numbered files so that a rule can be found and edited by topic, and so the always-on cost stays legible file by file.

Rule IDs did not change across the split. `config/learned-rules.md` is the redirect shim left in place at the old path: a pointer table, zero rule definitions, so nothing is shadowed and no ID is defined twice.

## Why the skills directory stays flat

The agent runtime discovers skills at `$AGENT_HOME/skills/<name>/SKILL.md`. Grouping them into `skills/review/`, `skills/core/` etc. would break discovery. So domains live in the registry as id prefixes (`review-code`, `core-self-correction`) while the filesystem stays flat. The repo mirrors the runtime layout exactly rather than imposing a tidier one that would not load.

## Registry ids vs directory names

`registry.yaml` holds the canonical target id. `legacy_name` holds the current on-disk directory when it has not been renamed yet.

Migration is one skill at a time, each with backup, reference updates, and validation — not a bulk rename. Until a skill is migrated, its id and its directory differ, and that difference is data, not drift. `scripts/validate.sh` resolves an active entry by id first, then `legacy_name`.

## Rule traceability

Each registry entry has a `rules:` list naming the global rule IDs that govern the skill. The migrated skill carries the matching IDs in a `## Governing global rules` section — IDs only, never copies of the rule text, since `rules/` stays the single definition site.

This gives a bidirectional chain: `registry ↔ skill ↔ rules`. `validate.sh` checks the registry half (every referenced ID exists). The skill half is only populated for skills that have been migrated.

## Backup discipline

Every structural change backs up first, under `$AGENT_HOME/backups/<change>-<date>/`, hash-verified before anything is deleted. Backups stay on the machine and are excluded from this repo — they are recovery state, not architecture.
