# Domains

Seven canonical domains. Do not add more without a real need — a domain that holds one skill forever was a tag, not a domain.

Skill id = `<domain>-<skill-name>`. The domain lives in the **name**, not in a nested directory: Claude Code loads personal skills from `~/.claude/skills/<skill-name>/SKILL.md` only.

| Domain | Owns | Examples |
| --- | --- | --- |
| `core` | General reasoning behavior — self-correction, source grounding, evidence discipline | `core-self-correction`, `core-source-grounding` |
| `review` | Review and adversarial reasoning — task review, critical challenge, multi-perspective review, adjudication | `review-code`, `review-intent-first`, `review-adversarial-consensus` |
| `eng` | Software engineering — implementation discipline, debugging, APIs, Git, testing | `eng-coding-discipline`, `eng-debugging`, `eng-api-investigation`, `eng-git-discipline` |
| `design` | UI/UX — design discipline, reference-backed design, visual review, reference discovery | `design-ui-discipline`, `design-reference-discovery`, `design-ui-review` |
| `sec` | Security — auth, authorization, tenant isolation, security review | `sec-security-review` |
| `data` | Data correctness — database, migrations, data integrity | `data-migration-safety` |
| `ops` | Completion and operational behavior — task completion, release readiness, handoff | `ops-completion-handoff`, `ops-ticket-pr` |

## Picking a domain

Ask what the skill is *about*, not what it touches. A migration review touches SQL and review technique, but it exists to protect data → `data`. An adversarial pass over a migration exists to adjudicate a disputed conclusion → `review`.

If two domains fit equally, the skill is probably two skills.

## Rule vs skill

```text
RULE  = short behavior that should apply almost always   → ~/.claude/rules/
SKILL = repeatable multi-step workflow, loaded on demand → ~/.claude/skills/
```

"Do not modify unrelated code" is a rule. "Perform adversarial PR review" is a skill. Long procedures never go in `CLAUDE.md` or in a rules file.

## Global vs project

| Scope | Location |
| --- | --- |
| Reusable across projects | `~/.claude/skills/<skill-name>/SKILL.md` |
| Specific to one repository | `<repository>/.claude/skills/<skill-name>/SKILL.md` |

Project-specific behavior stays in the repository. Do not promote it into the global library because it was useful once.

**Name collisions:** a project skill must not reuse a global skill's name. Prefix with the product: `wedding-builder-verification`, `arcflux-analytics-review` — never bare `review` or `verify`.

## Loading philosophy

Load the minimum relevant set.

```text
API bug                    → core-source-grounding + eng-debugging + eng-api-investigation
PR review                  → review-task + review-critical-challenge
UI design                  → design-ui-discipline + design-reference-discovery
high-risk disputed review  → review-task + review-critical-challenge + review-adversarial-consensus
```

(The right-hand ids above include planned skills; today's equivalents are in `registry.yaml`.)
