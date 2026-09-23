---
name: sec-security-review
description: Review authentication, authorization, trust boundaries, tenant isolation, secrets and sensitive data handling. Use for security reviews and threat modeling of scoped changes.
---

# Review security

1. Establish assets, actors, entry points, trust boundaries and the authorized review environment. Identify what the change exposes or relies on.
2. Trace identity and authorization enforcement through the complete path. Check cross-user/tenant access, fail-open conditions, injection, SSRF, secrets, unsafe deserialization and dependency risks only where applicable.
3. For each material finding, record the vulnerable path, preconditions, impact, evidence and smallest remediation. Distinguish a demonstrated exploit from a plausible attack requiring verification.
4. Validate with local fixtures or explicitly authorized targets. Review authority is not authorization to attack external services, extract secrets or mutate production data.
5. Compare against the baseline, retain unresolved risk explicitly, and seek independent falsification for consequential conclusions. Report a scoped verdict; absence of findings is not a guarantee of security.

## Governing global rules

CODE-002, VERIFY-002, TEST-001, SCOPE-003, CONSENSUS-001, CONSENSUS-002.
