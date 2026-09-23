# Claude integration handoff

Status: contract **0.2.0 draft** and behavior artifacts; adapter integration not verified.
The local 0.1.0 review candidate was superseded when dispatch identity became
required. Consume 0.2.0 only; no compatibility with 0.1.0 is claimed.

Baseline: `main` at `ed0c6e2120d24481e7bab34c80cb66af89545995`.
Existing adapter branch observed at `7dbd2053d88a42a073a53d6986bae7c7619389af`.
Codex branch: `codex/agent-behavior-contracts-v1`.

## Consume these interfaces

1. Read `contracts/README.md` and validate envelopes with
   `contracts/agent-work.schema.json` (Draft 2020-12).
2. Discover roles and explicit rule paths from `roles/catalog.json`; resolve
   role `skill_refs` relative to a pinned canonical distribution root.
3. Map `default` and `escalated` logical policy references in adapter-owned
   configuration. Per-role model preferences belong there, not in the profiles.
4. Enforce role/task capability requirements, permission intersection, path
   ownership, budgets and cross-document result invariants. The schema checks
   shape; it cannot enforce permissions or truth of evidence.
5. Report unsupported mechanisms honestly. These files do not spawn agents.

## Existing behavior preserved

All 28 original rule definitions remain unchanged. Existing skill bodies remain
unchanged except for `adversarial-consensus`: its independence guidance now checks
actual context capabilities instead of assuming named agent types are cold-start;
internal passes are explicitly non-independent, and an assumed vendor-specific
review command is replaced by capability/authorization checks.
The new catalog explicitly lists the existing seven rule files once. No new
always-on rule or import is added. Existing code-review, intent-first, adversarial,
UI and coding discipline skills are reused through canonical paths. The nine new
skills fill orchestration, research, product, planning, architecture, testing,
security, release readiness and documentation gaps.

Vault/vendor skills remain as existing optional repository content; the role
catalog does not reference them. The old installer still installs its old default
set. Making the default installation project-independent is Claude's work, not
something this branch claims to have accomplished.

## Ownership and minimal integration changes

- Codex: `contracts/**`, `roles/**`, nine new skill directories, the scoped
  portability correction in `skills/adversarial-consensus/SKILL.md`,
  `evals/orchestration/**`, this handoff and behavior validation report.
- Claude: `scripts/**`, adapters, routing configuration, technical tests and CI.
- Shared registry: preserve existing entries; merge Codex's nine additions and
  removal of the former `sec-security-review` planned entry and registry date
  update. No existing active entry was rewritten. This is the expected textual
  conflict with your branch.
- Your existing `7dbd205` branch fixes the YAML representation of
  `conventions.skill_path`; retain that fix when combining the registry edits.
  This branch preserves the inherited placeholder syntax, so the existing shell
  validator passes but a general YAML parser needs that already-authored fix.
- Your branch also adds `rules/70-routing.md`. The catalog here deliberately
  enumerates the seven baseline behavior rule files; it does not discover new
  rules by glob at runtime. Reconcile the selection guidance with role loading
  and optional profiles before deciding whether to extend the catalog. Do not
  auto-load Vault/vendor workflows through a default routing rule.
- Root README, `config/AGENTS.md`, adapter entrypoints and legacy architecture
  docs were not edited here. Proposed integration: link this contract from the
  README; add role/contract resource installation and discovery; keep rules loaded
  once; update architecture status after actual adapter tests.

Do not simply install core-orchestrate's SKILL.md without its root contract and
profile resources. An adapter may render resource locations, but must retain
canonical source identity and resolve all references after installation.
Existing runtime-specific wording in reused skills remains inherited; report
concrete portability mismatches rather than silently substituting nonexistent
commands. No executable external orchestration service is introduced.

## Feedback requested before stability

Return a compatibility table for Claude Code and Codex separately:

- Runtime/version, adapter/profile and tested repository SHA.
- Schema/reference validity and safe installation.
- Rules and selected skills actually loaded in a fresh session.
- Actual spawn, fresh-context, model-selection, workspace and tool isolation.
- Contract fields needing changes, with the exact unsupported mechanism.
- Scenario results and raw evidence; distinguish static checks, role simulations
  and real adapter runs. `evals/orchestration/scenarios.md` defines the cases.

Independent installer work can continue while this draft is reviewed. Keep the
contract draft until disagreements are reconciled; do not merge either branch
automatically. No message to another service is sent by this handoff file.
