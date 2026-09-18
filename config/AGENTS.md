# Global instructions

<!-- The AGENT_HOME token below is rendered to a real path by scripts/install.sh. -->

@{{AGENT_HOME}}/learned-rules.md

## Always-on rules

@{{AGENT_HOME}}/rules/00-operating-principles.md
@{{AGENT_HOME}}/rules/10-scope-control.md
@{{AGENT_HOME}}/rules/20-verification.md
@{{AGENT_HOME}}/rules/30-intent-first.md
@{{AGENT_HOME}}/rules/40-correction-learning.md
@{{AGENT_HOME}}/rules/50-design.md
@{{AGENT_HOME}}/rules/60-adversarial-consensus.md

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

Skill inventory and lifecycle: `{{AGENT_HOME}}/skill-registry/registry.yaml`. Incident history (not auto-loaded): `{{AGENT_HOME}}/logs/self-correction-log.md`.
