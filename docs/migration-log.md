# Migration log

One entry per structural change to the global configuration. Newest last.

## 2026-09-17 — rules split

`~/.claude/learned-rules.md` split into seven files under `~/.claude/rules/`, imported from `CLAUDE.md`. Rule IDs unchanged. The old path kept as a redirect shim (pointer table only, no definitions).

Pre-split snapshot: `~/.claude/backups/reorg-20260917/learned-rules.md` (machine-local).

Also on this date: `self-correction-regression` removed from `~/.claude/skills`, absorbed into `self-correction-coding-discipline`. Registry entry `core-self-correction-regression` retained with `status: replaced`, `replaced_by: core-self-correction`.

## 2026-09-18 — architecture validation

Fresh-session validation of the split. Verified: all seven rule files loaded in-session (bodies inlined via the `CLAUDE.md` imports, disk content re-read and matched), 28 rule IDs, zero duplicates, all ten families present, legacy skills still discoverable, redirect shim intact.

Result: PASS.

## 2026-09-18 — pilot skill migration: `strict-review` → `review-code`

First rename into the domain naming convention. Identity migration only, not a redesign.

Changed:

- created `skills/review-code/SKILL.md` from the legacy file
- `name: strict-review` → `name: review-code`; H1 `# Strict review` → `# Review code`
- appended `## Governing global rules` listing `TEST-001` and `REVIEW-002`, closing the registry↔skill traceability gap (IDs only, no rule text copied)
- `CLAUDE.md` routing row and the two `intent-first-review` references updated to the new name
- registry entry annotated: `legacy_name` is now provenance, not a live path
- legacy directory removed after the backup was hash-verified

Unchanged: the `description:` line byte-for-byte, so trigger phrases are identical; all six review steps, the severity table, report format, verdict rules, and the Never list. `diff -u` old→new was three hunks: name, title, traceability section.

Backup: `~/.claude/backups/reorg-20260917/pilot-review-code/` (machine-local).

Result: PARTIAL — filesystem, references, registry and behavior all verified; `review-code` confirmed discoverable in-session. The negative half (that `strict-review` no longer resolves) needs a fresh session to confirm.

Not yet migrated: the remaining eight skills still carry legacy directory names.

## 2026-09-18 — configuration put under version control

Mirrored `rules/`, `skills/`, `skill-registry/`, `CLAUDE.md`, `learned-rules.md`, and `commands/` into this repository. Copy verified by `sha256sum`. Added README, `.gitignore`, architecture notes, and the install/sync/validate scripts.

No live configuration was moved or modified by this step.
