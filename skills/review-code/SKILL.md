---
name: review-code
description: Use when reviewing someone else's code — a PR, a branch diff, a colleague's commit, a file handed over for checking. Triggers on "review PR", "review diff", "check code này", "soi code", "audit file", "kiểm tra code đồng nghiệp". Not for reviewing your own uncommitted work (use /code-review) and not for writing the review ticket (use ticket-pr).
---

# Review code

The reviewer's job is to be right, not to be agreeable. A review that misses a real defect costs more than one that raises an extra question.

## Step 1 — Establish what is actually under review

```
gh pr view <n> --json baseRefName,headRefName,state,commits
git log --oneline <base>..<head>
git show <sha>          # per commit, not just the squashed diff
```

Separate what this change introduced from what it inherited. Pre-existing problems are notes, not blocking findings — mislabelling them burns the author's time and your credibility.

## Step 2 — Read the code, not the diff summary

Open each touched file at full width around the change. A diff hides the caller, the type, the guard three lines up that makes the new branch unreachable.

For every finding, verify it in the source before writing it down:

- Is the new branch reachable? Check every caller and every guard upstream (a server component that throws on a missing param makes the client-side check dead code).
- What is the type actually? An optional prop and a required one produce different findings.
- Does the claimed behaviour hold at runtime? Effect deps, mount order, StrictMode double-mount, SSR vs client evaluation.
- What happens on the failure path? Empty, null, malformed, network error, storage unavailable, duplicate request, race with another tab.

If a finding cannot be traced to `file:line`, it is not a finding yet.

## Step 3 — Check against the spec, not against taste

Find the spec (`docs/`, the ticket, the design file) and quote the clause. "Spec §6 line 147 says error screen; the code returns 404" is a finding. "I would have done it differently" is not.

Scope discipline: the change is measured against what the ticket agreed to do. Work the author deliberately left out, and documented, is not a defect.

Read the ticket/spec for intent, not for prose quality. Informal, awkward, non-native, shorthand, or Vietnamese/English-mixed wording in the requirement is not a defect when the intended behavior and scope are clear — see `intent-first-review`.

## Step 3.5 — The wording threshold

Judge intent → behavior → scope → correctness. Never wording, style, grammar, or terminology preference for its own sake.

Before writing any wording-related finding, apply the test:

> Would this wording materially affect what gets built, verified, or shipped?

If no, suppress it — not even a `⚪ nit`. Padding a review with prose complaints costs the author time and costs you credibility on the findings that matter.

Flag wording only when it changes behavior or scope, contradicts another requirement, leaves two materially different implementations equally plausible, makes an acceptance criterion undeterminable, or creates technical/security/legal/data/operational risk. Naming that actively misleads the next reader of the code (`deleteUser` that archives) is a behavior finding, not a nit — it stays.

For UI changes, the spec includes the product's own visual language. A screen that ignores the established spacing, density, dialog, or typography pattern — or that ships fashionable decoration with no product reason — is a real finding, not taste. See `ui-design-discipline`. Judging it requires visual evidence (screenshot or rendered page); without that, say the visual result was not inspected.

## Step 4 — Report

Order by severity, most severe first. One line each, then detail only where detail changes what the author does.

| Level | Meaning |
|---|---|
| 🔴 P1 | Blocks merge — wrong behaviour, data loss, security, crash |
| 🟠 P2 | Should fix before merge — spec mismatch, unhandled failure path |
| 🟡 P3 | Note — dead code, inconsistency, monitoring/ops impact |
| ⚪ nit | Cosmetic; author's call |

Format: `path:line — <what is wrong>. <what to do>.`

Also state plainly what is correct, in one compact block — the author needs to know which parts were actually checked, not just where the complaints are. Do not pad it into praise.

Close with a verdict: APPROVE / APPROVE WITH NOTES / REQUEST CHANGES, and list anything that needs a decision from the author or the team rather than a fix.

## Step 5 — Hold the line

When the change touches security, tenancy, data integrity, migrations, concurrency, or production behavior — or when the root cause is contested — one review pass is not enough. Run the defend → falsify → adjudicate loop from `adversarial-consensus` before issuing the verdict. Agreement between your own passes is not evidence if they all read the same file and inherited the same assumption.

If the author or another agent pushes back, re-read the code and verify. Wrong → correct it in one sentence and move on. Right → say so and show the evidence. Do not concede to end the discussion.

## Never

- Never claim something was tested when it was not run. Run it (`tsc --noEmit`, build, the app) or write "chưa chạy".
- Never take another agent's report at face value — confirm at `file:line`.
- Never edit the author's code during a review unless asked.
- Never post the review to GitHub/Jira without explicit approval.

## Related skills

- `ticket-pr` — turning the findings into a review card / PR comment

## Governing global rules

- TEST-001
- REVIEW-002
