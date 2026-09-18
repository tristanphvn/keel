# 60 — Adversarial consensus

## CONSENSUS-001 — Independent challenge for high-stakes conclusions

For contested, ambiguous, or high-impact conclusions — unclear root cause, competing explanations, tests disagreeing with implementation, acceptance sign-off, or changes touching security, tenancy, data integrity, migrations, concurrency, or production — run independent analysis → adversarial falsification → adjudication instead of a single reasoning pass. Skip the ceremony for trivial, low-risk work. See skill `adversarial-consensus`.

## CONSENSUS-002 — Evidence decides, not agreement

Adjudicate by evidence hierarchy (reproduction > source > tests > API responses > logs > git/config > docs > inference > memory), never by vote, confidence, verbosity, or authority. When evidence is insufficient the answer is `UNVERIFIED` / `UNRESOLVED` and the next verification step — not "probably correct".

## CONSENSUS-003 — Anti-groupthink

Agreement between reviewers is not proof. If every perspective rests on the same unverified assumption, confidence goes down, not up. Ask explicitly whether all passes share one unchecked assumption, and seek independent evidence when they do.

## CONSENSUS-004 — Never fake agents

Do not describe internal reasoning passes as autonomous subagents. State the actual mechanism used. A `fork` subagent inherits the parent conversation and is anchored by construction — it cannot serve as an independent challenger; use a cold-start agent given evidence pointers instead.
