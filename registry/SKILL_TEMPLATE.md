# Skill template

Copy the block below to `{{AGENT_HOME}}/skills/<domain>-<skill-name>/SKILL.md`, then add a matching record to `registry.yaml`.

## Frontmatter — supported fields only

The agent runtime reads **`name`** and **`description`** from SKILL.md frontmatter. Nothing else is guaranteed to be parsed. Domain, status, version, and dependencies are management metadata and belong in `registry.yaml`, not here — inventing frontmatter keys produces a file that looks configured but is not.

- `name` — must equal the directory name, kebab-case, `<domain>-<skill-name>`.
- `description` — the only thing that decides whether the skill loads. Write it as trigger surface: name the artifacts, verbs, and phrasings (including Vietnamese) that should pull it in. Third person, one paragraph.

---

```markdown
---
name: <domain>-<skill-name>
description: <What it does, then when to use it. Name concrete triggers — artifacts, verbs, file types, user phrasings in both languages. This text is the whole trigger mechanism; vague descriptions never fire.>
---

# <Skill title>

## Purpose

One or two sentences. What this skill makes reliably better. If it overlaps an existing skill, say which one owns what.

## Trigger

- <situation that should load this skill>
- <user phrasing, VN and EN>

## Do not trigger

- <adjacent case that belongs to another skill — name it>
- <case too trivial to justify the workflow>

## Dependencies

- `<other-skill-id>` — what it provides
- rules: `<RULE-ID>`, `<RULE-ID>`

## Workflow

1. <step — imperative, verifiable>
2. <step>
3. <step>

## Scope boundaries

What this skill may change, and what it must report instead of touching. Unrelated findings → `OUT-OF-SCOPE FINDING`, never a silent fix (`SCOPE-001`).

## Evidence requirements

What counts as proof for this skill's conclusions, in hierarchy order. What must be labelled `NOT VERIFIED` when unavailable (`TEST-001`, `VERIFY-002`).

## Completion behavior

What the skill reports when done: `IMPLEMENTED` / `VERIFIED` / `UNVERIFIED` / `BLOCKED` / `OUT-OF-SCOPE FINDINGS`. Never collapse these.

## Self-test

| # | Scenario | Expected behavior |
| --- | --- | --- |
| A | <input that should trigger> | <what the skill makes happen> |
| B | <adjacent case that should NOT trigger> | <defers to X / no action> |
| C | <case where evidence is missing> | reports `UNVERIFIED`, names the next verification |
```

---

## Before registering

- [ ] `name` matches the directory name exactly
- [ ] No unsupported frontmatter keys
- [ ] Description names real triggers, not a summary of the body
- [ ] No duplicate of an existing skill — checked `registry.yaml`; overlapping skill either merged or given an explicit boundary
- [ ] Long always-on behavior extracted to `{{AGENT_HOME}}/rules/` instead
- [ ] Registry record added with `id`, `domain`, `status`, `purpose`, `depends_on`, `version`
- [ ] Skill loaded in a fresh session and confirmed to appear in the available-skills list
