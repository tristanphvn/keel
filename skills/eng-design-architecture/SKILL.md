---
name: eng-design-architecture
description: Design technical boundaries and evaluate implementation tradeoffs. Use for architecture decisions, API/data contracts, concurrency design and cross-component changes.
---

# Design architecture

1. Read existing interfaces, data flow, failure behavior and operational constraints before proposing structure.
2. Identify invariants, ownership, trust boundaries and compatibility requirements. Trace reads, writes and asynchronous transitions across the relevant system.
3. Compare a minimal extension of the current design with material alternatives. Explain costs and failure modes; avoid introducing infrastructure solely for hypothetical scale.
4. Specify contracts, data lifecycle, concurrency/idempotency behavior, migration/rollback needs and observable failure signals where relevant.
5. Return a decision record with evidence, rejected alternatives, unresolved assumptions and acceptance checks. Hand scoped implementation to the appropriate roles. Request independent challenge for material security/data/concurrency risk using the existing adversarial-consensus skill.

## Governing global rules

CODE-001, CODE-002, ROOT-001, SCOPE-001, CONSENSUS-001.
