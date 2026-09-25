---
name: sec-security-review
description: Review authentication, authorization, trust boundaries, tenant isolation, secrets and sensitive data handling. Use for security reviews, threat modeling, credential exposure incidents, and changes to production configuration, logging, frontend environment variables, or secret handling.
---

# Review security

1. Establish assets, actors, entry points, trust boundaries and the authorized review environment. Identify what the change exposes or relies on.
2. Trace identity and authorization enforcement through the complete path. Check cross-user/tenant access, fail-open conditions, injection, SSRF, secrets, unsafe deserialization and dependency risks only where applicable.
3. For each material finding, record the vulnerable path, preconditions, impact, evidence and smallest remediation. Distinguish a demonstrated exploit from a plausible attack requiring verification.
4. Validate with local fixtures or explicitly authorized targets. Review authority is not authorization to attack external services, extract secrets or mutate production data.
5. Compare against the baseline, retain unresolved risk explicitly, and seek independent falsification for consequential conclusions. Report a scoped verdict; absence of findings is not a guarantee of security.

## Preventive implementation and verification

For changes to authentication, authorization, API serialization, logging, telemetry, caches, configuration or client/build boundaries, load [Preventive security checks](references/preventive-checks.md). Select checks with its surface table and record scoped evidence; coverage means the touched surfaces were checked, not that every item was mentioned. Use this during implementation as well as review; do not wait for an incident. The checklist is canonical; Testing and Review reference it rather than maintaining copies.

## Prevent secret exposure

Treat production passwords, API keys, private keys, tokens, signing secrets, database URLs with credentials, and session cookies as secrets. Do not paste their values into chat, commits, PRs, issues, examples, screenshots, logs, or learner records. Use placeholders and provider-issued non-secret identifiers. Do not ask the user to paste a secret to diagnose an incident.

Before inspecting a suspected file or running a scanner, ensure output is redacted. Avoid raw file dumps, environment dumps, shell tracing, credential-bearing command arguments, and unredacted diffs. Report only the affected path, revision, secret type, and redacted evidence. If a tool cannot redact safely, use a local check that returns locations and counts without values. Never send repository contents or secrets to an external scanning service without authorization.

For relevant implementation and reviews:
- Keep real credentials in the deployment's supported secret store or runtime injection mechanism. Example environment files must contain placeholders only.
- Never place a server secret in a client-exposed environment variable, browser bundle, source map, static asset, or API response. Trace where a variable is consumed; its name alone does not prove it is private.
- Check application logs, error reporting, analytics, build output, test fixtures, generated files, and artifacts for accidental exposure. Redact sensitive fields before logging.
- Check the staged changes and relevant tracked/history surfaces with an available local secret scanner configured to redact values. Record scanner scope, version, exclusions and result; do not claim a scan ran if unavailable.
- Remember that .gitignore does not remove already tracked files or historical commits. Add local pre-commit/pre-push scanning where explicitly requested; do not enable disabled CI or claim a skill enforces a technical gate.
- Use fake credentials in tests. Verify that errors and logs do not expose them. Do not test a suspected production credential by logging into production without explicit authorization.

## Respond to exposed production credentials

1. Confirm the affected project/repository, environment, owner, exposure location and approximate time without retrieving or repeating the secret. Do not infer the project from unrelated conversation history. Distinguish suspected exposure from confirmed exposure; treat confirmed production exposure as an incident.
2. Prioritize invalidating the exposed credential. Tell the authorized owner to revoke or rotate it promptly; deleting a file or making a repository private does not invalidate copied credentials. Updating this skill is not incident containment.
3. Identify dependent services and use the provider's supported rotation procedure. Prefer a controlled replacement, deployment and verification sequence when available; if active abuse requires immediate revocation, state the availability trade-off. Do not change production credentials, deploy, or revoke access merely because a skill update or review was requested.
4. Preserve a minimal access-controlled incident timeline and non-secret identifiers. Review authorized provider/access logs for misuse, scope, affected resources and dependent sessions or tokens. Do not erase audit evidence or broadly distribute leaked material.
5. Remove the exposure from current source, logs and artifacts within authorized scope. Assess history, forks, clones, caches and published packages separately. History rewriting, force-pushing and destructive cleanup require explicit coordination; they never replace revocation.
6. Verify using non-secret evidence: old credential revoked or expired, replacement deployed to intended consumers, service health checked, exposure paths fixed, redacted scans completed, and monitoring reviewed. Mark each unverified item and its owner. A clean scan does not prove no misuse occurred.
7. Report containment status, corrective changes, verification evidence and remaining actions separately. Do not call the incident resolved merely because the source was cleaned or a security skill was added.

## Acceptance examples

- A user reports a leaked production key without naming the project: request project and non-secret location; do not request the key or guess the repository.
- A tracked environment file contains a password: use redacted inspection, prioritize rotation, and explain why adding .gitignore alone is insufficient.
- A frontend change references a server credential: trace browser exposure and block shipping that leak; do not simply rename the variable.
- A scanner prints matching secret values: prevent that output from entering chat or published artifacts; use safe redaction or report the scan blocked.
- The user asks only to improve this skill: update instructions, but do not revoke credentials, rewrite history, or deploy production changes.

## Governing global rules

CODE-002, VERIFY-002, TEST-001, SCOPE-003, CONSENSUS-001, CONSENSUS-002.
