---
name: vault-rules
description: Use at the start of work in any repo that has a vault at $VAULT_ROOT/<project>/, or when the user asks "rule của project này là gì", "đọc vault", "áp workflow", "branch naming là gì", "commit format", or when about to branch/commit/push/open a PR and the project conventions are not already in context. Loads the universal rules plus the project overrides and the active work card for the current branch.
---

# Vault rules loader

Rules live outside the repo. `$VAULT_ROOT` (fallback `E:\vault`, then `%USERPROFILE%\vault`).

- `_common/` — universal, every project
- `<project>/` — project-specific; **overrides `_common/` on conflict**

Project slug = the vault folder matching the repo (e.g. `cainz-pet-portal`). Confirm with `ls $VAULT_ROOT`.

## Step 1 — Read, in this order

1. `_common/operations/workflow.md` — Step 1-7 + iron rule "never auto-edit"
2. `_common/operations/collaboration-style.md` — user = reviewer, Claude = senior eng
3. `_common/operations/engineering-principles.md` — "Must be a standard, not a bandaid"
4. `_common/operations/task-discipline.md`
5. `<project>/operations/workflow-overrides.md` — branch prefix, commit format, PR convention
6. `<project>/operations/stack-conventions.md` and `pitfalls.md`
7. `<project>/<Project Name>.md` — the landing page, for anything else worth reading

Read the files. Do not answer from memory of a previous session — rules get edited.

## Step 2 — Find the work card

```
git rev-parse --abbrev-ref HEAD
ls $VAULT_ROOT/<project>/work/active/
```

Branch `feature/CPP-405/<slug>` ↔ card `work/active/CPP-405.md`. Read the card before touching code — it holds the agreed scope, the out-of-scope list, and the acceptance criteria. Related cards use suffixes `-QA`, `-REVIEW`, `-PR`, `-test-checklist`.

No card for the current branch → say so, and offer to create one from `_common/templates/`.

## Step 3 — Apply, do not just recite

The rules that most often get broken:

- **Never edit code without explicit confirmation.** Present the plan, wait for "ok". This holds even mid-task and even when the user said "continue".
- **Never work on `main` / the base branch.** Branch first, named per the project's `workflow-overrides.md`.
- **Never push or merge unless asked.** Claude's ceiling is "open a PR". Merging belongs to the user.
- **Git flow is one-way** where the project says so (e.g. `feature → develop → release → main`): no shortcut merges, no back-merges.
- **Ask, don't infer, when the spec is silent.** Do not invent behaviour and do not decide on the user's behalf.
- **Root cause, not bandaid**, and handle every failure mode the change can hit.
- **Comment language** per the project rule (Cainz projects: English only, no Vietnamese/Japanese).
- **No AI traces** in repos that forbid them: no `Co-Authored-By`, no AI-generated docs committed inside the tree.

## Step 4 — On conflict

`<project>/` wins over `_common/`. If two rules genuinely contradict and neither is scoped, stop and ask — do not pick one silently.

## Related skills

- `ticket-pr` — writing the ticket / PR itself
- `setup-vault` — creating a vault for a repo that has none
