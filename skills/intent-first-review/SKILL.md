---
name: intent-first-review
description: Threshold rule for reviewing or interpreting a task, requirement, specification, prompt, issue, acceptance criteria, ticket, or user instruction — judge intent, behavior, scope, and correctness, not wording, style, grammar, or terminology preference. Use when reviewing a spec/ticket/AC, when deciding whether a wording problem is a real finding, when tempted to ask a clarification question about awkward or mixed-language phrasing, and alongside review-code, ticket-pr, and code review.
---

# Intent-First Review — Do Not Nitpick Wording

## Core rule

Prioritize:

```text
INTENT
→ BEHAVIOR
→ SCOPE
→ CORRECTNESS
```

over:

```text
WORDING
→ STYLE
→ GRAMMAR
→ TERMINOLOGY PREFERENCE
```

Do not create findings merely because wording is informal, awkward, repetitive, non-native, or could be phrased more elegantly.

If the intended meaning is clear and the scope is sufficient for correct implementation, accept the meaning.

Do not be pedantic.

---

## Wording is NOT a defect when

The sentence:

- is grammatically imperfect;
- uses informal language;
- uses slightly imprecise terminology but the intended concept is obvious from context;
- could be shorter or more elegant;
- repeats information harmlessly;
- uses Vietnamese/English mixed terminology;
- is written in shorthand;
- is not phrased like formal technical documentation;

BUT:

- the intended behavior is clear;
- implementation scope is clear;
- acceptance criteria can still be understood correctly.

In these cases:

```text
DO NOT FLAG AS A REVIEW FINDING.
```

If rewriting the task/spec, normalize the sentence naturally while preserving the exact intended meaning.

---

## Only flag wording when it materially matters

Raise a wording issue only when the wording:

1. changes or may change the intended behavior;
2. creates real ambiguity between multiple materially different implementations;
3. contradicts another requirement;
4. changes the task scope;
5. creates a technical, security, legal, data, or operational risk;
6. makes acceptance criteria impossible to determine;
7. could reasonably cause the implementer to build the wrong behavior.

The test is:

> Would this wording issue materially affect what gets built, verified, or shipped?

If NO: do not treat it as a defect.

---

## Natural normalization

When meaning is already clear but phrasing is awkward:

Prefer:

```text
understand intent
→ preserve intent
→ rewrite naturally
```

Do NOT:

```text
find minor wording imperfection
→ classify as issue
→ block task
```

Example:

User writes:

> get api rồi check status coi có data không

If context clearly means:

> Call the API and inspect the response status/data.

Do not raise a grammar or terminology finding. Normalize it naturally if producing documentation.

---

## Review finding threshold

Before raising a wording-related finding, ask:

```text
Does this wording create a real correctness or scope problem?
```

If no, suppress the finding.

Do not manufacture review depth by nitpicking prose.

---

## Acceptance criteria

Evaluate acceptance criteria based on the intended behavior they specify.

Do not fail an acceptance criterion solely because the sentence could be written more elegantly.

A wording problem only matters when it prevents reliable determination of:

```text
what must happen
where it must happen
under what condition
what counts as success
```

---

## Ambiguity handling

If context resolves the wording naturally, use the context.

Do not ask unnecessary clarification questions for harmless linguistic ambiguity.

Only escalate ambiguity when two or more plausible interpretations would materially change implementation or acceptance behavior.

---

## Final rule

```text
CLEAR INTENT + CLEAR SCOPE + CORRECT BEHAVIOR
= ACCEPT
```

even if wording is imperfect.

```text
WORDING CHANGES MEANING / SCOPE / CORRECTNESS
= FLAG
```

The reviewer exists to detect real implementation and correctness problems, not to act as a grammar critic.

---

## Boundaries — what this rule does NOT relax

Intent-first applies to **prose**: task text, specs, tickets, acceptance criteria, prompts, comments, docs.

It does not lower the bar on:

- code correctness, security, data integrity, scope creep — see `self-correction-coding-discipline`;
- verification honesty — never say tested/passed for something not run (`TEST-001`);
- naming that materially misleads the reader of the code (a function named `deleteUser` that archives is a behavior/correctness finding, not a wording nit);
- template/format requirements the target system actually enforces (`ticket-pr`).

---

## Related

- `review-code` — reviewing someone else's code; severity ladder and `⚪ nit` level
- `ticket-pr` — writing review cards, QA questions, PR bodies
- `self-correction-coding-discipline` — scope control, source grounding, verification honesty
- `adversarial-consensus` — independent falsification and adjudication for high-stakes conclusions; challenge meaning, logic, evidence, scope, risk — never prose
