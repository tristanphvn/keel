---
name: core-plan-work
description: Convert an accepted objective into bounded work with dependencies and measurable acceptance. Use for implementation plans, milestones, sequencing and replanning after verified blockers.
---

# Plan work

1. Inspect the accepted objective and relevant source state. Preserve existing decisions; separate unknown facts from unresolved choices.
2. Define deliverables and observable acceptance criteria before assigning implementation tasks. Include explicit non-goals and verification needs.
3. Split by independently reviewable outputs. Assign a suggested role, owned paths, dependencies and evidence requirement to each task. Validate that dependencies form an acyclic graph and no two concurrent writers own overlapping paths.
4. Identify the smallest useful next step and critical blockers. Estimate only with stated assumptions; do not invent calendar commitments.
5. Produce a plan and task-envelope candidates for Orchestrator. Planning does not spawn agents or execute the plan unless separately assigned execution authority.
6. Replan only affected work after new evidence. Preserve completed evidence and user scope; do not reset retry budgets by renaming failed tasks.

## Governing global rules

SCOPE-001, REVIEW-003, REVIEW-004, VERIFY-001, TEST-001.
