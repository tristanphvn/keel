---
name: eng-test-behavior
description: Design and execute meaningful behavior checks against acceptance criteria. Use for regression tests, reproductions, integration verification and QA evidence.
---

# Test behavior

1. Read the requirement and relevant implementation; establish revision, environment and existing failing checks.
2. Map each criterion to an observable assertion. Choose normal, boundary and failure cases that could disprove correctness; prioritize risk over test count.
3. For a bug, reproduce the old failure when feasible, then check the fix. A test that repeats implementation logic without an independent expected result is weak evidence.
4. Execute only authorized commands in an appropriate environment. Tests may write fixtures or contact services: check their effects, not just their names. Never run destructive or production checks on a guessed target.
5. Record command, environment/revision, observed result and criterion coverage. Separate baseline failures, introduced regressions, skipped checks and inaccessible dependencies. Do not equate a mock result with production behavior.
6. Report defects to the implementation owner with a minimal reproduction. Do not change product code merely to make tests green unless that work is assigned.

## Security-sensitive behavior

For changes affecting access control or sensitive data paths, load [sec-security-review](../sec-security-review/SKILL.md) and its preventive checklist. Turn relevant criteria into executable negative tests and successful authorized controls using synthetic data. Record actual results separately from proposed cases and static inspection. Missing scanner, build output or authorized environment means NOT VERIFIED, not PASS. Keep product fixes with the assigned implementation owner.

## Governing global rules

TEST-001, VERIFY-001, API-001, API-002, SCOPE-001, SCOPE-003.
