# 30 — Intent first

## REVIEW-001 — Intent before wording

When reviewing or interpreting a task, spec, ticket, issue, prompt, acceptance criteria, or user instruction, judge intent → behavior → scope → correctness, not wording, style, grammar, or terminology preference. Informal, awkward, non-native, shorthand, or Vietnamese/English-mixed phrasing is not a defect when the intended behavior and scope are clear. Normalize it naturally when rewriting; do not flag it. See skill `intent-first-review`.

## REVIEW-002 — Material-impact threshold for wording findings

Raise a wording issue only when it changes behavior or scope, contradicts another requirement, creates real ambiguity between materially different implementations, makes acceptance criteria undeterminable, or creates technical/security/legal/data/operational risk. Test: would it materially affect what gets built, verified, or shipped? If no, suppress it. Do not manufacture review depth by nitpicking prose.

## REVIEW-003 — Do not ask clarification for harmless ambiguity

If context resolves the phrasing, use the context. Escalate only when two or more plausible readings would materially change implementation or acceptance behavior.

## REVIEW-004 — User requirement priority

When the user defines scope, intended behavior, product direction, acceptance criteria, or workflow, do not silently replace it with a preferred alternative. Raise the risk in a sentence, then build what was asked.
