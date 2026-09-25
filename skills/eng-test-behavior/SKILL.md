---
name: eng-test-behavior
description: Plan, design and execute meaningful behavior checks against acceptance criteria. Use for test planning, "what tests are still needed", test gaps and coverage review, regression tests, reproductions, integration verification and QA evidence.
---

# Test behavior

1. Read the requirement and relevant implementation; establish revision, environment and existing failing checks.
2. Map each criterion to an observable assertion. Choose normal, boundary and failure cases that could disprove correctness; prioritize risk over test count.
3. Assess security relevance before concluding which tests are needed (see below).
4. For a bug, reproduce the old failure when feasible, then check the fix. A test that repeats implementation logic without an independent expected result is weak evidence.
5. Execute only authorized commands in an appropriate environment. Tests may write fixtures or contact services: check their effects, not just their names. Never run destructive or production checks on a guessed target.
6. Record command, environment/revision, observed result and criterion coverage. Separate baseline failures, introduced regressions, skipped checks and inaccessible dependencies. Do not equate a mock result with production behavior.
7. Report defects to the implementation owner with a minimal reproduction. Do not change product code merely to make tests green unless that work is assigned.

## Security-sensitive behavior

Decide explicitly, from the code under test, whether it touches a security boundary: authentication, authorization or tenant scoping, data returned by an API or export, logging/telemetry/error output, caches of personalized data, secrets or credentials, or client/build configuration and published artifacts.

- **Relevant:** load the [sec-security-review](../sec-security-review/SKILL.md) skill and read the sections of its [preventive checklist](../sec-security-review/references/preventive-checks.md) that match the touched surfaces, before deciding the test plan. Turn those criteria into executable negative tests plus successful authorized controls, using synthetic data.
- **Not relevant:** say so in one line and continue.

Plan for the surfaces actually touched, not every checklist item: an API-only change needs serialization and authorization tests, not build-artifact inspection. Record actual results separately from proposed cases and static inspection. A relevant check without its evidence (scanner, build output, authorized environment) is NOT VERIFIED, not PASS. Keep product fixes with the assigned implementation owner.

## Governing global rules

TEST-001, VERIFY-001, API-001, API-002, SCOPE-001, SCOPE-003.
