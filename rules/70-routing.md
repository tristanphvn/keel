# 70 — Skill routing

Always-on. The other rule files state behavior; this one states selection.

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
