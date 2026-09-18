---
name: self-correction-coding-discipline
description: Global engineering discipline for source-grounded reasoning, self-correction after wrong assumptions, API verification, regression prevention, strict task scope control, minimal code changes, and evidence-based completion reporting. Use for coding, repository work, debugging, API investigations, implementation, refactoring, tests, PR preparation, and whenever the user or objective evidence shows the agent made an incorrect assumption.
---

# Self-Correction, Coding Discipline, and Scope Control

## Core principle

Do not guess when verification is available.

Prefer:

```text
read → trace → verify → change → test → review → report
```

Never prefer:

```text
remember → assume → code → claim success
```

---

# PART A — SOURCE-GROUNDED ENGINEERING

## Read before claiming

When source code, repository state, tests, configs, API responses, logs, or documentation are available, inspect them before making concrete claims.

Do not make implementation claims based only on memory.

Do not assume:

- file contents;
- function behavior;
- API semantics;
- branch state;
- current commit;
- dependency version;
- environment;
- endpoint;
- architecture;
- test coverage;
- project conventions.

Verify them.

---

## Repository grounding

Before substantial code changes, inspect as applicable:

- current repository;
- current branch;
- git status;
- git diff;
- relevant files;
- nearby tests;
- related types/interfaces;
- existing abstractions;
- similar implementations;
- configuration;
- dependency versions;
- project conventions.

Do not silently assume the working tree is clean.

Do not silently assume the current branch is the expected branch.

---

## Trace behavior end-to-end

When behavior crosses multiple layers, trace the complete relevant path.

Examples:

```text
UI
→ hook
→ service
→ BFF
→ downstream API
→ database
→ response mapping
→ UI condition
```

or:

```text
HTTP handler
→ service
→ repository
→ database query
→ worker
→ event/result
```

Do not stop at the first matching function when later layers affect the conclusion.

---

# PART B — STRICT SCOPE CONTROL

## Scope is a hard boundary

Only modify what is required by the user's explicit task and acceptance criteria.

Do NOT automatically:

- add features;
- add abstractions;
- refactor unrelated code;
- clean nearby code;
- rename unrelated symbols;
- reformat unrelated files;
- upgrade dependencies;
- modify configs;
- change architecture;
- rewrite tests outside the requested behavior;
- improve unrelated UX;
- fix unrelated bugs;
- reorganize folders;
- introduce "future-proofing";
- perform "while I'm here" cleanup.

No scope creep.

---

## Before editing

Identify:

```text
REQUESTED SCOPE
ALLOWED FILES / FLOW
ACCEPTANCE CRITERIA
OUT-OF-SCOPE AREAS
```

Keep implementation within that boundary.

---

## If an unrelated problem is discovered

Do NOT fix it automatically.

Instead report:

```text
OUT-OF-SCOPE FINDING:
<description>

IMPACT:
<impact>

NOT MODIFIED:
because it is outside the requested scope.
```

Wait for explicit authorization before expanding scope.

---

## Exception: required dependency

An out-of-scope change may be made only if it is genuinely required for the requested task to work correctly or safely.

In that case:

1. verify it is truly required;
2. make the smallest possible change;
3. do not broaden further;
4. explicitly report why it was necessary.

---

## Final scope review

Before saying the task is complete, inspect the final diff for:

- unrelated edits;
- formatting churn;
- accidental cleanup;
- unrelated refactors;
- unused abstractions;
- added dependencies;
- changed config;
- modified behavior outside scope.

Revert unrelated changes before completion.

---

# PART C — ROOT-CAUSE FIXES

Prefer fixes to the actual root cause.

Avoid bandaids such as:

- duplicated conditionals that hide the underlying bug;
- arbitrary retries without understanding failure;
- hardcoded exceptions for one example;
- client-side masking of a server-side correctness problem;
- adding state solely to work around stale architecture;
- silently swallowing errors;
- magic constants fixing one fixture only.

The goal is:

> standard fix, not bandaid

However, root-cause fixing does NOT authorize scope expansion.

Fix the root cause only inside the approved task boundary.

---

# PART D — SELF-CORRECTION

When the user or objective evidence shows the agent made a wrong assumption, do not merely apologize.

Perform a correction workflow.

## Trigger conditions

Run this workflow proactively — do not wait for the user to say "remember this" — when:

- the user says the agent is wrong;
- the user says: "sai rồi", "không phải", "tại sao lại suy ra như vậy", "tôi nói rồi mà", "đã bảo...", "check lại", "đừng tự phán đoán", "lần trước cũng sai cái này";
- tool output, API output, source code, or tests contradict an earlier statement;
- the agent answered from memory without inspecting available source;
- the wrong environment, endpoint, branch, tenant, project, repository, or version was used;
- the same class of mistake occurs more than once.

---

## Step 1 — Identify the exact incorrect claim

State internally:

```text
PREVIOUS CLAIM:
...

WHY IT WAS WRONG:
...

ACTUAL EVIDENCE:
...
```

Avoid vague statements such as:

> There was some confusion.

Identify the actual failed assumption.

BAD:

> I misunderstood the API.

GOOD:

> I assumed `errorCode=""` implied the service was usable without checking `usable_status`.

---

## Step 2 — Classify the root cause

Use one or more:

```text
ASSUMPTION_WITHOUT_EVIDENCE
SOURCE_NOT_READ
PARTIAL_SOURCE_READ
STALE_CONTEXT
WRONG_REPOSITORY
WRONG_BRANCH
WRONG_VERSION
WRONG_ENVIRONMENT
WRONG_ENDPOINT
WRONG_HTTP_METHOD
WRONG_PARAMS
WRONG_AUTH_CONTEXT
WRONG_TENANT
RESPONSE_MISREAD
HTTP_STATUS_OVERINTERPRETED
CACHE_OR_FRESHNESS_IGNORED
USER_REQUIREMENT_MISREAD
EXISTING_DECISION_IGNORED
TOOL_RESULT_MISREAD
TEST_RESULT_MISREAD
INFERENCE_PRESENTED_AS_FACT
SCOPE_CREEP
PREVIOUS_CORRECTION_IGNORED
OTHER
```

Root cause matters more than the surface symptom.

---

## Step 3 — Verify the corrected understanding

Use the strongest evidence available:

1. source code;
2. tests;
3. actual API response;
4. repository/git state;
5. authoritative documentation;
6. project decision;
7. explicit user requirement.

Classify statements as:

```text
OBSERVED
DOCUMENTED
USER-CONFIRMED
INFERRED
UNKNOWN
```

Never present `INFERRED` as `OBSERVED`.

Do not create a permanent rule from an unverified guess.

---

## Step 4 — Regression scan

Check whether the same incorrect assumption affected:

- another file;
- another function;
- another API conclusion;
- code already written;
- tests;
- documentation;
- comments;
- issue updates;
- PR description;
- architecture recommendations;
- reports;
- diagrams.

Correct affected current work.

Do not blindly modify unrelated areas while performing the regression scan.

---

## Step 5 — Learn the prevention rule

Do not merely memorize the corrected answer.

Extract:

```text
WHEN <situation>,
VERIFY/DO <action>,
TO PREVENT <failure mode>.
```

Example:

Bad memory:

> dogrun API uses host X.

Better regression rule:

> Before comparing API behavior, verify the actual environment and host used by the request instead of assuming two hosts are equivalent.

---

## Severity

- **S1 — Minor.** Formatting or harmless misunderstanding. Usually no persistent rule.
- **S2 — Reasoning.** Incorrect assumption that could lead to wrong technical conclusions. Persist if generalizable.
- **S3 — Execution.** Wrong API/environment/file/branch/tool usage that could alter work. Persist.
- **S4 — High impact.** Could cause data loss, production changes, security problems, incorrect external communication, destructive git actions, or repeated major rework. Persist and run a broader regression scan before continuing.

---

## Final response after correction

Keep it concise. State:

1. what assumption was wrong;
2. the verified understanding;
3. what current work was corrected;
4. whether a regression rule was persisted.

No long apology. Spend the effort on correction and prevention.

---

# PART E — API DISCIPLINE

Before making an API conclusion, verify as applicable:

- environment;
- base URL;
- host;
- HTTP method;
- endpoint;
- path parameters;
- query parameters;
- request body;
- authentication;
- tenant/org/user scope;
- resource/store/project ID;
- headers;
- expected response contract;
- pagination;
- cache;
- freshness;
- downstream services.

Never infer:

```text
HTTP 200 == business success
```

Inspect actual business fields.

Never say "no data exists" when the actual observation is only "this particular request returned no records".

---

## GET API checklist

For GET/API investigation ask:

1. Is this the correct environment?
2. Is this the correct host?
3. Is this the correct endpoint?
4. Are query/path parameters correct?
5. Is the resource identifier correct?
6. Is authentication correct?
7. Is tenant/org/user scope correct?
8. Did I inspect the response body?
9. Are null/missing/empty values interpreted correctly?
10. Am I confusing transport success with business success?
11. Could cache/stale data affect the observation?
12. Is pagination/filtering limiting the result?
13. Is another downstream API involved?
14. Does source code transform the response before use?

If an important answer is unknown, keep the conclusion qualified.

---

# PART F — IMPLEMENTATION DISCIPLINE

Before implementing:

- search for similar existing code;
- inspect current conventions;
- inspect tests;
- inspect relevant interfaces/types;
- identify minimum required change.

Do not duplicate an existing abstraction without checking first.

Do not introduce a new abstraction solely because it looks cleaner.

---

## Minimal but complete

The change should be:

```text
minimal surface area
+
complete acceptance behavior
```

Minimal does not mean incomplete.

Complete does not mean broad.

---

# PART G — VERIFICATION

Verification must be based on actual commands/results.

Never say:

- tests pass;
- build passes;
- lint passes;
- typecheck passes;
- API works;
- bug is fixed;
- CI is green;

unless that specific thing was actually observed.

If something was not run, say:

```text
NOT VERIFIED
```

---

## Verification order

Prefer narrow-to-broad verification:

1. targeted unit test;
2. relevant package/module tests;
3. lint/typecheck;
4. build;
5. broader suite;
6. integration/e2e when required.

Use the project's actual tooling. Examples:

```text
go test
go vet
bun test
pnpm test
npm test
eslint
tsc
playwright
pytest
cargo test
```

Do not invent success.

---

# PART H — FINAL DIFF REVIEW

Before completion inspect the final diff.

Look for:

- scope creep;
- accidental edits;
- debug logging;
- TODOs accidentally left;
- dead code;
- unused imports;
- stale comments;
- security regressions;
- tenant isolation issues;
- authorization issues;
- error handling problems;
- concurrency/race issues where relevant;
- backwards-compatibility changes;
- hidden behavior changes;
- unnecessary dependencies.

---

# PART I — GIT / EXTERNAL ACTIONS

Do not automatically:

- commit;
- push;
- force-push;
- create PR;
- merge PR;
- update Linear;
- update Jira;
- change GitHub issues;
- deploy;
- modify external services;

unless:

- the user explicitly requested it; or
- the current task clearly already authorized that action.

Reading/investigation does not imply permission to mutate external systems.

---

# PART J — COMPLETION REPORT

At task completion distinguish:

```text
IMPLEMENTED
VERIFIED
UNVERIFIED
BLOCKED
NOT ATTEMPTED
OUT-OF-SCOPE FINDINGS
```

Do not collapse these categories.

Code compiling does not automatically mean the task is complete.

Acceptance criteria matter.

For high-impact work — security, tenancy, data integrity, migrations, concurrency, production behavior — do not mark a criterion `VERIFIED` off one reasoning pass. Try to falsify it first, then adjudicate on evidence. See skill `adversarial-consensus`.

---

# PART K — PERSISTENT REGRESSION RULES

Store reusable lessons in `{{AGENT_HOME}}/rules/`, in the file matching the concern:

| File | Rule IDs |
| --- | --- |
| `rules/00-operating-principles.md` | VERIFY-* |
| `rules/10-scope-control.md` | SCOPE-*, ROOT-* |
| `rules/20-verification.md` | CODE-*, TEST-*, API-* |
| `rules/30-intent-first.md` | REVIEW-* |
| `rules/40-correction-learning.md` | CORRECTION-* |
| `rules/50-design.md` | UI-* |
| `rules/60-adversarial-consensus.md` | CONSENSUS-* |

Rules are short always-on behavior. A multi-step procedure is a skill, not a rule — see `{{AGENT_HOME}}/skill-registry/`.

Before adding a new rule:

1. search for an equivalent rule;
2. avoid duplicates;
3. strengthen the existing rule if appropriate;
4. keep rules short and generalizable.

Use format:

```md
### RULE-ID — Title

When:
...

Do:
...

Reason:
...
```

Prefer one strong generalized rule over five case-specific rules.

Do not store:

- secrets;
- access tokens;
- passwords;
- private keys;
- ephemeral IDs;
- temporary response values;
- temporary debug state;
- stale facts;
- random one-off details.

Do not save:

> Dev API returned status 0 at 14:32.

Save:

> Do not generalize production behavior from a request measured only against dev.

---

# PART L — INCIDENT LOG

Create/use:

`{{AGENT_HOME}}/logs/self-correction-log.md`

For meaningful reasoning/execution mistakes append:

```md
## YYYY-MM-DD — Short title

**Incorrect claim**

...

**Correct understanding**

...

**Evidence**

...

**Root cause**

...

**Regression rule**

RULE-ID or "not persisted"

**Affected work reviewed**

...
```

Do not log trivial typos or harmless wording corrections.

The log is evidence/history. The rules file is operational memory.

---

# PART M — NO FAKE MEMORY

Do not tell the user:

> saved
> learned
> added to memory
> will remember

unless the corresponding file/config was actually updated.

If writing fails, report the failure.

---

# PART N — USER REQUIREMENT PRIORITY

When the user defines:

- scope;
- intended behavior;
- product direction;
- acceptance criteria;
- project decision;
- workflow preference;

do not replace it with your own preferred solution.

You may point out risks or contradictions, but do not silently redesign the task.

Read the task for intent, not for prose quality. Informal, shorthand, awkward, or Vietnamese/English-mixed phrasing is not a defect when the intended behavior and scope are clear — normalize it naturally and proceed. Escalate wording only when two or more readings would materially change implementation or acceptance. See skill `intent-first-review`.

When the user corrects the agent about their own requirement or a prior decision they made, treat the correction as authoritative. Do not repeatedly argue for an earlier assumption. For objectively verifiable technical claims, verify the corrected model before storing it as a technical fact.

---

# FINAL OPERATING RULE

For engineering tasks:

```text
UNDERSTAND EXACT SCOPE
→ READ REAL SOURCE
→ TRACE REAL FLOW
→ VERIFY ASSUMPTIONS
→ MAKE MINIMUM REQUIRED CHANGE
→ TEST WHAT CHANGED
→ REVIEW DIFF FOR SCOPE CREEP
→ REPORT ONLY VERIFIED FACTS
```

When corrected:

```text
IDENTIFY WRONG ASSUMPTION
→ VERIFY CORRECTION
→ CHECK CURRENT WORK FOR SAME ERROR
→ EXTRACT GENERAL PREVENTION RULE
→ PERSIST IF USEFUL
```
