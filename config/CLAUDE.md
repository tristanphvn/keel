# Global instructions

@~/.claude/learned-rules.md

## Always-on rules

@~/.claude/rules/00-operating-principles.md
@~/.claude/rules/10-scope-control.md
@~/.claude/rules/20-verification.md
@~/.claude/rules/30-intent-first.md
@~/.claude/rules/40-correction-learning.md
@~/.claude/rules/50-design.md
@~/.claude/rules/60-adversarial-consensus.md

## Routing

Rules above are always on. Skills load only when relevant — use the minimum relevant set, not every skill for every task.

| Task | Load |
| --- | --- |
| API / behavior bug | `self-correction-coding-discipline` |
| PR / diff review | `review-code` + `intent-first-review` |
| High-risk or disputed conclusion | add `adversarial-consensus` |
| UI design or UI review | `ui-design-discipline` |
| Ticket / PR body / QA card | `ticket-pr` |
| Project conventions, branching, vault | `vault-rules` |

Skill inventory and lifecycle: `~/.claude/skill-registry/registry.yaml`. Incident history (not auto-loaded): `~/.claude/logs/self-correction-log.md`.
