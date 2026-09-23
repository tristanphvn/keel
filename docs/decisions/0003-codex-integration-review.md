# Codex review of integration b6733f9

Date: 2026-09-21. Reviewed head: `b6733f9b8650bd04e9a13bb4bad35b7649d310ad`.
Disposition: **request changes; keep contract 0.3.0 draft**. No merge authorized.

## Canonical decisions implemented in this follow-up

Accept the 0.3.0 schema bump: optional properties still require an exact-version
change under the closed schema. Accept delivered-skills provenance as an adapter
claim, with reference delivery weaker than actual context loading. It does not
prove the model relied on a skill. Accept removal of `rules/70-routing.md` and its
import: canonical role selection plus existing skill descriptions supersede it.
These decisions are not acceptance of all renderer or validator behavior.

Populate required_permissions for all 14 profiles:

| Roles | Permission floor |
| --- | --- |
| backend, frontend | read, write |
| testing | read, execute |
| orchestrator, product-thinking, research, critical-thinking, planning, architecture, ux-ui, infrastructure-devops, review, security, documentation | read |

Floors express the minimum core responsibility, not every possible task. A test
writer also needs write; a code implementer running tests also needs execute;
an infrastructure executor may need write/execute/network. A planning-only
infrastructure task does not. Saved documentation needs write; a response in the
conversation does not. The task explicitly supplies those additional grants.
Do not make delegation mandatory for an orchestrator that can work directly.

The contract text now requires floor <= task permissions <= ceiling and rejects
the inference that no floor means unrestricted inherited tools. This clarifies
the intended floor semantics without introducing another schema field/version.
It intentionally requires changes in Claude-owned code; this commit does not
pretend that updating prose enforces anything.

## Reproduced findings for Claude

### R1 — Permission restrictions fail open or miss the task's actual needs

At the reviewed head, `scripts/routing/render.py:379-385` returns inherited tools
for an omitted floor and for `tools_override: []`. A nonempty floor is used as the
entire allowlist rather than a minimum. `scripts/contracts/validate.py:179-188`
checks only the ceiling, not the floor.

Direct function probes against the actual source returned:

- unpopulated testing floor: `(None, 'none', '')`;
- explicit empty override with a justification: `(None, 'none', '')`;
- testing with required read/execute, task granting only read: no semantic failures.

Fix the validator's floor check, distinguish an empty override from absence, and
derive effective tools from an explicit authorized execution policy/task context.
Do not silently inherit broad tools when the required information is absent.
Do not widen all floors to ceilings to make rendering convenient. Add focused
regressions for each reproduced case and for an allowed task permission above
the floor (for example writing a review report). Do not implement an unrequested
orchestration engine or call these static checks dispatch enforcement.

### R2 — Task capabilities incorrectly constrained by a role's optional list

`scripts/contracts/validate.py:185-188` rejects a task requiring a known capability
unless its role already lists it as required or optional. The contract specifies
the union of role and task requirements; optional_capabilities is not a ceiling.

Probe: a testing task requiring `tool-isolation` produces the failure
`requires no capability the role does not name`, despite being valid under the
canonical union rule. Validate capability vocabulary, then enforce the union.
Do not add every capability to every role as a workaround.

### R3 — Rendering trusts capability labels without validating their evidence

`scripts/routing/render.py:570-585` loads a record but does not invoke its schema
and semantic validation. `capability_verdict` at 622-623 accepts `enforced`
directly. Removing every evidence item from the tool-isolation record still
returned `(True, 'enforced')`, and check_capabilities returned no failures for a
role requiring it. The separate capability validator is not on this render path.

Validate the exact supplied record before it authorizes rendering: shape, evidence
kind, probe resolution/digest and other declared semantic invariants. Require a
known target runtime version/platform when relying on a measurement, or explicitly
mark output as an unverified template. Optional CLI match flags cannot establish
compatibility with an unspecified target. Reject invalid/stale records before
writes; keep validation distinct from rerunning the runtime probe.

### R4 — Workspace probe measures a different property from the contract

`contracts/README.md` defines workspace-isolation as a separate writable workspace
for the task. `tests/probes/workspace-isolation.sh` instead attempts an outside
Read and equates success with no workspace isolation. Separate worktrees can
provide distinct write locations while allowing outside reads. This observation
does establish that the tested execution did not confine reads; it does not prove
separate writable workspaces are unavailable.

Keep the canonical definition. Reclassify that capability as unmeasured until a
probe actually checks distinct workspaces and independent writes. Preserve the
outside-read observation as a separately labelled filesystem-confinement result,
without claiming it proves workspace allocation behavior. Any new capability
vocabulary would need a separate contract proposal, not a silent redefinition.

## Evidence and limits

- GitHub PR #3 head and run `35562556934` both resolve to b6733f9; all four jobs
  returned success, including Ubuntu and Windows. Main remained ed0c6e2.
- Downloaded text/source artifacts were matched to GitHub blob hashes before
  testing. The tracked bytecode file was not downloaded or executed.
- Independently ran the six shell suites on Linux: 30/26/50/69/44/74 assertions,
  **293 passed, zero failed**. This review's additional direct function probes
  reproduced R1-R3 despite the green suite. R4 is a source/definition mismatch.
- This was a single-reviewer source and execution pass, not independent multi-agent
  consensus. Neither Claude runtime measurements nor transcript claims were rerun.
- Neither codex nor shellcheck is installed in this review environment. No Codex
  CLI tool identifiers or runtime behavior are certified from Work Mode tools.
- No M2 runtime conformance harness is implemented or requested by this follow-up.

## Handoff and compatibility boundary

This branch changes only the fourteen role floors, canonical permission prose and
this decision record. Claude owns renderer/validator/probe fixes and regression
tests. Empty Codex tool mappings should fail honestly once these floors are
consumed; do not invent identifiers to make rendering pass.

Ancillary cleanup in Claude's scope: remove the tracked
`scripts/routing/__pycache__/render.cpython-313.pyc`; update PR #3's stale sentence
claiming no Linux evidence (CI now supplies static/adapter evidence, not runtime
evidence). Keep macOS and Codex runtime claims unverified.
