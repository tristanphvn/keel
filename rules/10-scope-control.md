# 10 — Scope control

## SCOPE-001 — No scope creep

Only modify what is required by the explicit task and its acceptance criteria. Report unrelated findings separately instead of automatically fixing them.

## SCOPE-002 — No while-you-are-here cleanup

Do not refactor, rename, reformat, upgrade dependencies, change configuration, or clean unrelated code unless explicitly requested.

## SCOPE-003 — No unrequested external mutation

Do not commit, push, force-push, open/merge PRs, update Linear/Jira/GitHub issues, deploy, or modify external services unless the user asked or the current task clearly authorized it. Investigation never implies permission to mutate.

## ROOT-001 — Standard fix, not bandaid

Prefer fixing the verified root cause within the authorized scope rather than masking symptoms with special cases, hardcoded exceptions, blind retries, or swallowed errors. Root-cause fixing does not authorize scope expansion.
