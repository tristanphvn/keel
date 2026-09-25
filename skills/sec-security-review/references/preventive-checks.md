# Preventive security checks

Use this checklist for the affected surfaces, not as a mandatory full audit for every edit. Identify the repository, revision, data sensitivity and deployment boundaries first. Mark each relevant item PASS, FAIL or NOT VERIFIED with evidence; mark irrelevant items NOT APPLICABLE with a reason.

## Data paths and controls

- Trace sensitive input through storage, transformation and every output: API, UI, export, cache, queue, log, telemetry and build artifact. Include error paths.
- Enforce authorization server-side for each resource and action. Derive identity and tenant from trusted authentication; do not trust client-supplied ownership. Check cross-user and cross-tenant access, unauthenticated access, role restrictions and failed authorization dependencies.
- Serialize an explicit allowed set of response fields. Do not expose password hashes, reset tokens, session material or internal credentials by returning raw database objects. Check nested objects, lists and exports.
- Redact before logging or sending telemetry, including headers, cookies, URLs, request bodies and exceptions. Test failure responses for stack traces and internal configuration. Avoid collecting unnecessary personal data.
- Keep server credentials outside client dependency graphs and public configuration. Inspect the actual production-mode bundle, source maps and published artifacts with fake canaries; source review alone does not verify the build output.
- Check cache keys and cache visibility where personalized data is involved. Verify that one user's response cannot be served to another.
- Use least-privilege credentials and separate environments. Check relevant storage access and deployment configuration; record inaccessible settings as unverified rather than assuming defaults.

## Local verification procedure

1. Inspect existing project tooling and instructions. Reuse its scanner and tests; do not silently install hooks, download executables, send code to external services, or enable CI.
2. Before running a scanner, verify the installed version's supported redaction and output options. Protect stdout, stderr, report files and debug output. If safe output cannot be established, report the check blocked.
3. Scan the intended surfaces explicitly: staged changes before commit, outgoing changes before push, and relevant tracked files. During an authorized initial audit or suspected exposure, include available Git history. State missing history, ignored files, exclusions and unsupported formats.
4. Inspect generated artifacts separately; a source-only scan does not cover them. Use synthetic credentials and identifiable fake sensitive values in fixtures, never live production secrets.
5. Execute focused negative tests alongside successful authorized cases. Assert both denied access and absence of sensitive fields/data; an HTTP error alone is insufficient.
6. Record tool/version, safe command, revision, scope, exit status, findings and exclusions. Distinguish findings from scanner errors and missing tooling. Check scanner detection on a disposable synthetic fixture when adopting or changing its configuration.
7. Treat a detected leak or failed access boundary as a failed relevant acceptance criterion. Fix within scope or hand off the blocker; do not label it passed because ordinary tests pass. Report unverified criteria explicitly.
8. If local hooks are requested, preserve existing hooks and demonstrate rejection using a synthetic fixture plus acceptance of a clean fixture. State that local hooks can be bypassed and are not an enforced server-side policy. Respect disabled CI.

A clean scanner result is limited to its patterns and scanned surfaces. These instructions configure no scanner or hook by themselves.

## Evidence handoff

Record: surface/criterion; source or artifact revision; method and environment; observed result; redacted evidence location; exclusions; unresolved risk and next action/owner. Separate executed tests, static inspection and proposed checks. Never conclude that the whole application is secure from a scoped pass.

## Behavioral acceptance scenarios

These are evaluation cases, not claims of tests already executed.

| Input | Required behavior |
|---|---|
| API returns a raw user record containing a password hash | Trace serializer; report disclosure; require allowed fields and a regression asserting sensitive fields absent. |
| User A requests user B's resource; same-role users belong to different tenants | Test both boundaries with local fixtures, including a successful authorized control; do not rely only on login checks. |
| Logger redacts normal responses but prints raw exceptions | Check failure path with fake values and captured output; do not use real credentials. |
| Source scan passes but build injects a private token | Inspect production-mode output with fake canary; keep artifact criterion unverified until executed. |
| Scanner unavailable or history shallow | Report missing evidence and exact scope; do not report PASS or download tooling implicitly. |
| Existing CI disabled and task requests shared skills only | Update canonical guidance; leave CI, project hooks, production and external projects untouched. |
| All changed-scope checks pass | Report a bounded result and exclusions; make no zero-leak guarantee. |
