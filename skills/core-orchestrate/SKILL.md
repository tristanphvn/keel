---
name: core-orchestrate
description: Coordinate scoped work across role profiles when a task benefits from delegation, multiple disciplines, or independent verification. Use for task dispatch, handoffs, conflict resolution, and bounded agent workflows.
---

# Orchestrate work

Read `contracts/README.md` and `roles/catalog.json` from the canonical repository/distribution root. Load only selected role profiles and their relevant skill bodies. If these resources are unavailable, report orchestration integration as unavailable; do not invent the contract.

1. Establish the user's objective, accepted constraints, repository baseline, existing work, and observable completion criteria. For a small single-discipline task, work directly; do not manufacture a team.
2. Choose roles for distinct outputs or evidence needs. Product discovers value; Research gathers evidence; Planning describes dependencies; Orchestrator dispatches. Testing executes checks; Review assesses changes. Route security-sensitive work to Security when warranted.
3. Before dispatch, check actual capabilities and authority. Intersect task permissions, role ceilings, user authorization, and runtime restrictions. A profile grants no permission. Do not assume skills or permission limits propagate to children.
4. Create a task envelope with scope, acceptance criteria, pinned context pointers, dependencies, workspace and bounded attempts. Use the catalog's default limits unless a stricter environment or explicit task limit applies. Count attempts per logical task across role/model changes; renaming a task must not reset its budget.
5. Dispatch only ready tasks whose dependencies completed with accepted evidence. Detect unknown dependencies and cycles before dispatch. Parallelize disjoint work; one writer owns each file/directory scope. Separate worktrees alone do not resolve semantic conflicts. Shared schema changes require an owner handoff.
6. Send a short context packet: objective, constraints, selected role/skills, relevant source revisions, acceptance, permissions and expected result. Keep secrets out. For an independent challenge, use a fresh context with raw evidence pointers, not the previous conclusion. If unavailable, label sequential passes as non-independent.
7. Collect results, inspect actual changes and evidence, and map every criterion. A child saying completed is not acceptance. Reconcile the exact disputed claim against same-revision evidence; seek the smallest discriminating observation. Never decide by majority or repeatedly debate without new evidence.
8. Retry only with a specific correction or new evidence and remaining budget. Escalate a model only through a supported configured policy and remaining escalation allowance; a stronger model cannot repair missing access or authority. At budget exhaustion, report partial/blocked/failed as applicable and the next concrete action.
9. Integrate only authorized changes, check interactions, and report the actual mechanism, covered criteria, remaining limits and handoff. Stop when all criteria pass with evidence, the user cancels, a necessary dependency/authority is missing, or budgets are exhausted. Continue unrelated ready work when one branch is blocked.

## Capability fallback

- No spawn: perform bounded sequential role passes only if the objective permits; do not claim multiple agents or independent review.
- No model selection: use the actual current model only when acceptable; record the fallback. If a specific model is mandatory, block that task.
- No workspace isolation: serialize writers with explicit ownership; do not overwrite existing user edits.
- No tool isolation: do not launch a constrained child with broader effective tools. Keep the task in a sufficiently restricted execution context or block it. Prompt instructions are not enforced isolation.
- Required capability missing: block that task. Optional capability missing: document the reduced mechanism. Never silently downgrade a required capability.

## Governing global rules

VERIFY-003, SCOPE-001, SCOPE-003, TEST-001, CONSENSUS-002, CONSENSUS-004.
