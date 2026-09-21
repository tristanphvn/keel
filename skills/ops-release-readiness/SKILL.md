---
name: ops-release-readiness
description: Assess build, environment, deployment and rollback readiness. Use for infrastructure changes, CI/CD design and operational handoff; execution still requires task authorization.
---

# Assess release readiness

1. Inspect the actual build/deploy configuration, environment boundaries and relevant failure history. Do not infer the target from a local default.
2. Define prerequisites, configuration and secret references without copying secret values. Check health signals, migrations, compatibility and recovery behavior.
3. Plan the smallest operational change, verification and rollback. Identify irreversible steps and what evidence is required before taking them.
4. Execute only operations already authorized by the task, within owned paths and environments. A role, plan or successful build does not grant deployment permission.
5. Report observed readiness separately from deployment status. Include commands run, target, revision, remaining prerequisites and a usable rollback handoff.

## Governing global rules

VERIFY-001, API-002, SCOPE-001, SCOPE-003, TEST-001.
