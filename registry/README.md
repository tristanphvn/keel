# Skill registry

Management layer for the global Claude Code environment. Nothing here is loaded into a session — it exists so the skill library stays inventoried instead of accreting.

| File | Role |
| --- | --- |
| `registry.yaml` | Every global skill: id, domain, status, purpose, dependencies, version. Includes `planned:` entries not yet authored. |
| `domains.md` | The seven canonical domains, the rule-vs-skill split, global-vs-project placement, loading philosophy. |
| `SKILL_TEMPLATE.md` | Starting point for a new skill; lists which fields Claude Code actually reads. |

## Layout

```text
~/.claude/
├── CLAUDE.md                  # thin: always-on rule imports + routing table
├── rules/                     # short always-on behavior, imported by CLAUDE.md
├── skills/<skill-name>/SKILL.md   # flat — the only layout Claude Code loads
├── skill-registry/            # this directory (not loaded)
└── logs/self-correction-log.md    # incident history (not loaded)
```

`skills/` stays **flat**. Claude Code discovers personal skills at `~/.claude/skills/<skill-name>/SKILL.md`; a nested `skills/core/<name>/SKILL.md` does not load. Grouping is expressed by the `<domain>-` name prefix.

## Adding a skill

1. Check `registry.yaml` for an equivalent — merge or set an explicit boundary instead of duplicating.
2. Decide rule vs skill. Short always-on behavior → `~/.claude/rules/`.
3. Copy `SKILL_TEMPLATE.md` → `~/.claude/skills/<domain>-<skill-name>/SKILL.md`.
4. Add the registry record.
5. Confirm it appears in the available-skills list in a fresh session.

## Retiring a skill

Set `status: replaced` + `replaced_by:`, or `status: deprecated`. Back up to `~/.claude/backups/<name>-<date>/` before removing the directory, and record the backup path in `notes`.

## Naming migration

Several active skills predate the `<domain>-<skill-name>` convention and still use their original directory names. `registry.yaml` carries both: `id` is the target name, `legacy_name` is what is on disk today. Renaming a skill directory changes its trigger surface and breaks every cross-reference in other skills — migrate deliberately, one skill at a time, not as a batch rename.
