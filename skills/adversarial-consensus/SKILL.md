---
name: adversarial-consensus
description: Run important, ambiguous, high-risk, or contested technical conclusions through independent analysis, adversarial falsification, and evidence-based adjudication instead of a single reasoning pass. Use when root cause is unclear, multiple explanations are plausible, tests and implementation disagree, a previous conclusion was already shown wrong, when deciding whether acceptance criteria actually pass, when a change touches security, tenancy, data integrity, migrations, concurrency, or production, and whenever the user asks for deep review, adversarial review, phản biện, or multi-agent review.
---

# Multi-Agent Adversarial Consensus

## Core principle

For important, ambiguous, high-risk, or contested technical conclusions, do not trust a single reasoning pass.

Use:

```text
INDEPENDENT ANALYSIS
→ ADVERSARIAL CHALLENGE
→ EVIDENCE RECONCILIATION
→ FINAL ADJUDICATION
```

The objective is not artificial debate. It is to reduce:

- confirmation bias;
- anchoring;
- premature conclusions;
- unverified assumptions;
- one-sided reviews.

---

# When to trigger

- root cause is unclear;
- multiple plausible explanations exist;
- reviewing architecture or implementation correctness;
- the task is high impact;
- API/environment behavior is disputed;
- tests and implementation appear to disagree;
- the user asks for deep review, adversarial review, phản biện, or multiple-agent review;
- a previous conclusion was already shown to be wrong;
- deciding whether a task is actually complete;
- a change affects security, tenancy, data integrity, migrations, concurrency, or production behavior.

Do not invoke heavy debate for trivial, obvious, low-risk work. Ceremony on a one-line fix is waste, not rigor.

---

# Role 1 — Defender / Implementer

Attempt to prove the current proposal or implementation is correct.

Answer:

```text
What requirement is being satisfied?
What evidence supports the current conclusion?
What assumptions are required?
What tests or source paths validate it?
Why is this implementation sufficient?
```

The Defender must not hide weak evidence. Classify every statement:

```text
VERIFIED
SUPPORTED
ASSUMED
UNKNOWN
```

---

# Role 2 — Challenger / Adversarial Reviewer

Attempt to falsify the same conclusion.

Ask:

```text
What assumption could be wrong?
What evidence contradicts the current explanation?
Could another root cause explain the same behavior?
Could the tests pass while the actual bug still exists?
Is this fixture-specific?
Is this environment-specific?
Was the full code path inspected?
What edge case breaks this?
What is untested?
What hidden dependency exists?
```

The Challenger must not manufacture objections. Raise material issues only. Do not nitpick wording — see `intent-first-review`.

---

# Independence requirement

Each perspective should inspect the evidence independently **before** reading the other's conclusion. This is what makes the second pass worth its cost.

```text
Defender:
read issue + source + tests

Challenger:
independently read issue + source + tests

Then compare conclusions
```

Do not have the Challenger merely react to the Defender's wording. Both reason from the actual evidence.

---

# Mechanism — real agents vs. internal passes

Be truthful about which mechanism produced the review.

## Real subagents

Spawn them when the user asked for multi-agent review, or when the current task clearly authorizes delegation.

Independence depends on the agent type:

| Type | Context | Independent? |
|---|---|---|
| Verified fresh-context execution | explicit raw evidence packet, no inherited reasoning | Eligible for independent analysis; still check shared assumptions |
| Inherited-context execution, including a full-history fork | parent conversation and conclusions | **No** — anchored by construction |

A full-history fork inherits assumptions already made in the conversation, including the wrong one under dispute. It can help with parallel work but cannot satisfy an independent challenge requirement. Verify the runtime's actual context behavior rather than inferring it from a named agent type. For independent falsification, use a genuinely fresh execution and give it raw evidence pointers (paths, commands, ticket), not the prior conclusion. If fresh context is unavailable, disclose the limitation; do not claim independent review.

Use an external review service only when the current runtime actually provides it and the user has authorized its use and any associated cost. Do not assume a vendor-specific review command exists.

## Internal passes

When subagents are unavailable or not warranted, run clearly separated passes in one session:

```text
Sequential Pass A — Defender (not independent)
Sequential Pass B — Challenger (not independent)
Adjudication Pass
```

Do NOT describe internal passes as autonomous agents or independent evidence. They can expose additional issues but do not satisfy a task requiring independent review. Never claim agents ran when they did not — same rule as `TEST-001` for tests.

---

# Role 3 — Adjudicator

After both perspectives finish, adjudicate.

Never decide by:

```text
majority vote
confidence
verbosity
authority
```

Decide by evidence hierarchy:

1. reproducible behavior;
2. source code;
3. tests;
4. actual API responses;
5. logs/traces;
6. git/configuration state;
7. authoritative documentation;
8. reasoned inference;
9. memory.

State why one interpretation is better supported.

---

# Disagreement resolution

Identify the exact disputed point:

```text
DISPUTED CLAIM
DEFENDER EVIDENCE
CHALLENGER EVIDENCE
MISSING EVIDENCE
RESOLUTION
```

Example:

```text
DISPUTED CLAIM:
The new commit introduced the build failure.

DEFENDER EVIDENCE:
Failure first appeared after this commit.

CHALLENGER EVIDENCE:
The incompatible dependency versions existed before the commit.

MISSING EVIDENCE:
Reproduction on the previous commit.

RESOLUTION:
Causation remains unverified until reproduction is performed.
```

The most valuable output of a disagreement is often `MISSING EVIDENCE` — it names the next command to run.

---

# Never force consensus

Consensus is not required. If evidence is insufficient, the correct result is:

```text
UNVERIFIED
```

or:

```text
UNRESOLVED
```

Do not settle for "probably correct" to produce a neat conclusion. Accuracy beats closure.

---

# Anti-groupthink rule

Agreement between multiple reviewers is not proof.

If all perspectives rest on the same unsupported assumption, the result is still weak. The Adjudicator must ask:

```text
Are all perspectives using the same unverified assumption?
```

If yes: downgrade confidence and seek independent evidence. Agreement reached by three passes that all read the same stale file is one observation, not three.

---

# Review teams

For especially important engineering reviews:

```text
IMPLEMENTER
ADVERSARIAL REVIEWER
TEST / VERIFICATION REVIEWER
SECURITY / ISOLATION REVIEWER
ADJUDICATOR
```

Instantiate only the roles relevant to the task. No ceremony for its own sake.

---

# Acceptance review

For a task with acceptance criteria:

```text
AC1
Defender evidence
Challenger attempt to falsify
Adjudicated result

AC2
Defender evidence
Challenger attempt to falsify
Adjudicated result
```

Final status per criterion:

```text
PASS
FAIL
UNVERIFIED
BLOCKED
```

No criterion is marked PASS on opinion alone.

---

# Scope rule

Adversarial review does NOT expand task scope.

Unrelated issues found by any reviewer are reported as:

```text
OUT-OF-SCOPE FINDING
```

Do not fix them unless authorized. See `SCOPE-001`.

---

# Wording rule

Challenge:

```text
meaning
logic
evidence
scope
correctness
risk
```

not stylistic wording. Awkward but clear phrasing gets normalized naturally, not debated. See `intent-first-review`.

---

# Final output

Present one reconciled conclusion. Do not dump the internal debate unless it is useful.

```text
FINAL CONCLUSION
EVIDENCE
REMAINING UNCERTAINTY
NEXT VERIFICATION
```

Include dissent only when it materially affects correctness.

---

# Correction behavior

If later evidence proves the final conclusion wrong:

1. identify which **shared** assumption failed;
2. update the regression-prevention rule;
3. check whether all reviewers inherited the same bad assumption;
4. add a verification step that prevents recurrence.

Do not only correct the final answer. Correct the reasoning process that let every reviewer agree incorrectly. See `self-correction-coding-discipline` PART D.

---

# Final operating model

```text
CLAIM
→ INDEPENDENT DEFENSE
→ INDEPENDENT FALSIFICATION
→ EVIDENCE COMPARISON
→ ADJUDICATION
→ VERIFIED CONCLUSION
```

If evidence does not converge:

```text
CLAIM
→ CONFLICTING EVIDENCE
→ UNRESOLVED
→ IDENTIFY NEXT VERIFICATION
```

Most important:

> Multiple agents are useful only when they provide independent evidence and criticism.

> Consensus is not truth. Evidence decides.
