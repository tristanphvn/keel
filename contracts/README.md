# Agent work contract — 0.3.0 draft

> **0.3.0 supersedes 0.2.0.** Three optional additions and no removals, but the
> version moved because this document requires it: "Any schema/enum change
> requires a new contract version", and every definition sets
> `additionalProperties: false`, so a 0.2.0 reader must reject a document
> carrying the new fields. Keeping the old version number would have produced
> exactly the silent incompatibility that rule exists to prevent.
>
> | Change | Where | Why |
> | --- | --- | --- |
> | optional `required_permissions` | role | a permission floor, so tool limits stop being invented by adapters |
> | optional `delivered_skills` | result provenance | records which skill bodies an adapter delivered, and by which mechanism |
> | second canonical example pair | `contracts/examples/*-completed.json` | acceptance and evidence semantics exercised by shipped documents, not only by synthetic fixtures |
>
> Rationale and the rejected alternatives: `docs/decisions/0001-contract-c1-c5.md`.
> Still draft. Not stable. The 0.2.0 delivery records in
> `docs/orchestration-validation.md` and `docs/orchestration-handoff.md` describe
> that version as shipped and are deliberately left unedited.

This is the canonical, runtime-independent interface between role/skill authors
and adapter implementers. It describes behavior and data, not an executable
scheduler. It is **draft pending adapter compatibility feedback**. The existing
installer does not consume this contract or install `roles/` and `contracts/`.
Static validity does not prove installation, runtime loading or behavior.

## Files and discovery

- `contracts/agent-work.schema.json`: JSON Schema Draft 2020-12; select the
  `role`, `task`, `result` or `catalog` definition by the envelope's `kind`.
- `roles/catalog.json`: explicit role and shared rule references, logical model
  policy names and default execution limits. It contains no skill bodies.
- `roles/<id>.json`: one role with responsibilities, boundaries, inputs, outputs,
  acceptance expectations, skill references and capability/permission limits.
- `skills/<name>/SKILL.md`: the only source of each skill body. Preserve the
  existing flat layout. Role skill references are explicit repository-relative
  paths, not ambiguous registry aliases.
- `registry/registry.yaml`: existing management/lifecycle metadata remains in
  place. The role catalog is not a replacement lifecycle registry.
- `contracts/examples/`: illustrative envelopes, not runtime test evidence.

An adapter must resolve references inside one pinned repository/distribution
root and verify that their real paths stay inside it (including symlinks).
Absolute paths, traversal, missing files and unresolved skill references fail
validation. Never fetch an arbitrary remote skill because a reference is missing.
Installed adapters may materialize an equivalent layout or resolve references
through an explicit mapping to the same canonical artifacts. Skill resource
references to this repository's root must remain resolvable after installation.

Read the catalog for selection, then only the selected role profile and relevant
skills. The explicit `rule_refs` apply once per execution context. Do not append
the same rules for every role or preload all skill bodies. Preserve local project
instructions and the platform/user instruction hierarchy. A role cannot replace
either. Do not infer child-context loading from parent loading.

## Identity, models and capabilities

Role IDs are stable lowercase slugs. Adding a role requires a profile, catalog
entry and appropriate skill references; it does not require another copy of a
skill or a new hardcoded role enum in the schema.

`model_policy_ref` is a logical routing key. This draft defines `default` and
`escalated`; it defines no model names, providers, prices or reasoning settings.
All initial roles use `default`. Claude owns the adapter-side mapping and may
apply per-role bindings without changing skill bodies. An explicit task policy
overrides the role default only within configured, authorized routing. An
unresolved policy is a configuration error; do not guess an API model name.

Capabilities describe runtime mechanisms:

| Capability | Meaning |
| --- | --- |
| `spawn` | Create a distinct agent execution and collect its result |
| `model-selection` | Select the requested configured model for this execution |
| `tool-isolation` | Enforce effective tool limits, rather than merely request compliance |
| `workspace-isolation` | Provide a separate writable workspace for this task |
| `fresh-context` | Start without inherited reasoning/history, with explicit context only |

The required set is the union of role and task requirements. Unknown or
unverified runtime capabilities count as unavailable. Optional capabilities
allow a reduced mechanism only when the task's acceptance still permits it.
An optional role capability becomes mandatory if the task requires it. Record
fallbacks in result summary/limitations and the actual `mechanism`. For an
independent review require `fresh-context` and a genuinely separate execution;
a sequential role pass is never independent evidence.

The initial profiles can be used directly and therefore have no globally
required multi-agent capability. A task needing real delegation must explicitly
require `spawn`; a task requiring a particular model must require
`model-selection`. Missing required capability produces `blocked`, not a
simulated successful run.

## Permissions and ownership

Permission labels classify operations: `read`, `write`, `execute`, `network`,
and `delegate`. A role's `permission_ceiling` is an upper bound, not a grant.
Task permissions must be a subset of that ceiling and intersect with platform
restrictions and actual user authorization. Capability flags also grant nothing.

A role may also declare optional `required_permissions`: the classes without
which it cannot discharge its responsibilities. Where `permission_ceiling` is the
upper bound, this is the floor, and it must be a subset of the ceiling. It exists
so that least privilege has something to be computed from: an adapter that has to
choose a tool limit with only a ceiling available will either grant everything or
invent a restriction, and an invented restriction is behavioural — a role denied
an execute tool reports `blocked` rather than doing its work.

**Tool identifiers are adapter-owned.** The contract names permission classes and
never tool names, because the names are runtime-specific. An adapter maps classes
onto its own tools and must do so deterministically: the same profile and the
same mapping produce the same limit on every machine. An adapter may still apply
a limit the contract did not ask for — operators have legitimate reasons — but it
must be recorded as adapter-declared rather than presented as a contract
requirement. A role that declares no `required_permissions` has not yet stated
what it needs, and the honest rendering is no restriction at all.

`write_paths` are explicit workspace-relative files or directory prefixes
(directory prefixes end in `/`), not shell globs. Empty means no writes. Include
fixtures, logs and test output where needed; command execution can write files
or use the network and must obey the same limits. The document-only roles may
write requested artifacts; Review may write its report, not the reviewed source.
`execute` is not blanket permission to run destructive commands or deploy.
External targets and side-effect constraints belong explicitly in task scope.

Before concurrent dispatch, check canonical path overlap, including directory
prefixes and symlinks. Assign one writer for overlapping scopes, or serialize.
Different worktrees prevent accidental shared-file edits but do not authorize
conflicting changes to the same contract. Preserve pre-existing edits. Shared
interface changes go to their owner; the consumer continues independent work.

If the runtime cannot enforce a required tool boundary, do not give a child
broader tools and call it isolated. Execute in an already sufficiently restricted
context or block. Model escalation cannot broaden permissions or escape a blocker.

## Task semantics

Every task has a unique logical `task_id`, a role, objective, input/context references,
scope, dependency IDs, at least one acceptance criterion, a workspace baseline,
effective permissions, a logical model policy and explicit budgets. Each dispatch
also carries a globally unique `dispatch_id` and a 1-based `attempt`. Results must
echo all three identity fields. The orchestrator allocates dispatch IDs, retains
the logical task identity across retries and persists accepted/obsolete dispatch
identities in its run checkpoint; a resumed session must not recreate counters
from a child's report. Use a new dispatch ID for each attempt. Criterion IDs must
be unique within a task (array item uniqueness alone does not enforce this).
Input refs
are artifacts to operate on; context refs are supporting evidence. Both carry
revision and purpose. Use immutable revisions or captured hashes/timestamps;
for non-versioned sources record the capture identifier and limitation.

Dependencies must exist in the current task graph, cannot refer to self and
must be acyclic. Dispatch only after required dependencies are accepted as
completed. A partial result does not satisfy a dependency automatically; split
and replan with explicit criteria if only a completed subset is needed. Resume
blocked work only after verifying its dependency changed. Continue independent
ready work. Planning authors the graph; Orchestrator owns dispatch and acceptance.

Default budgets are two total attempts per logical task, one delegation level,
three simultaneous agents including the orchestrator, and one model escalation
within the attempt budget. Attempt 1 is the initial execution. Root depth is 0;
depth 1 children cannot delegate again. The root enforces global concurrency
and depth: children cannot multiply limits. Stricter runtime limits win.
Task limits cannot exceed catalog defaults without explicit user authorization.

Each retry must name new evidence or a concrete correction. Track attempts and
escalations across task renames, model/role switches and context restarts. Save a
compact checkpoint outside source-controlled canonical configuration if needed.
At exhaustion stop affected work and return its actual status. Do not extend
budgets implicitly. User cancellation stops further dispatch and safely winds
down running work without silently deleting partial artifacts.

`handoff_to` is a role ID in the catalog or null. It is a routing hint, not an
instruction to send a message or automatically launch another task. The
orchestrator resolves an actual recipient execution and checks authorization.

## Result and completion semantics

Provenance may carry optional `delivered_skills`: `{ref, sha256, method}` per
skill, where `method` is `preload` (the body was embedded in the instructions the
adapter generated) or `reference` (the skill was named and left to be loaded).
Four stages are distinguishable, and only the first three are representable:

| Stage | Established by |
| --- | --- |
| declared by the role | the role's `skill_refs` |
| resolved to a canonical file | reference resolution plus the digest |
| delivered into the executing context | this field — the adapter's own claim |
| relied upon during execution | **nothing; no field asserts it** |

`reference` is deliberately the weaker claim of the two: it records that a skill
was made available, not that it reached the context. That distinction is not
pedantic — a child whose tool limit removes its skill-loading tool receives
nothing at all under `reference`, which has been observed on a real runtime.
Recording delivery is never evidence that the instructions were read or followed.

Results identify the task, dispatch and attempt, mechanism, observed runtime/model and
source provenance. Use `unverified` when a runtime identity is not observable;
never invent one. Record evidence references with revision, claim and observed
outcome. Protect secrets and sensitive payloads. Changed file revisions may be
commit IDs or captured content hashes for uncommitted artifacts; for renames,
record the old path in the summary as well as the resulting path.

| Status | Meaning |
| --- | --- |
| `completed` | Every task criterion passed with supporting evidence; no blocking unresolved item |
| `partial` | Useful work exists but criteria remain unmet or unverified |
| `blocked` | Necessary dependency, capability, access, authority or input is unavailable |
| `failed` | Execution or required behavior failed; no further in-budget correction is available |
| `cancelled` | Work stopped at the user's or orchestrator's cancellation |

Budget exhaustion does not itself establish failure: retain `partial` for useful
incomplete work or `blocked` for missing prerequisites and explain the exhausted
budget. Record all criteria exactly once, including skipped/blocked ones. Every
`pass` references at least one existing evidence ID and must be justified by its
contents. Evidence IDs must be unique. Every acceptance entry must resolve to the
original task criterion; no missing or invented criterion can yield completion.
The result identity must match a dispatched task, its attempt must be within the
effective budget, and a dispatch may be accepted at most once. These
cross-document/semantic constraints are required even though JSON Schema
alone cannot enforce them. Adapters/validators must enforce them separately.

For blocked results identify a blocking unresolved item and a concrete next
action. Changed files must be in the allowed write scope. Report partial edits
on failures too. Reject duplicate, stale or mismatched task/attempt results;
compare evidence against the relevant revision before accepting it. A legitimate
retry is a new attempt, not permission to overwrite old evidence.

Review completion means the review deliverable is finished; it does not mean the
reviewed product passed. A completed review can report defects. The orchestrator
must inspect the verdict and unresolved findings before accepting dependent
implementation work or declaring the overall objective complete.

## Compatibility and ownership

Codex owns `contracts/`, `roles/`, shared skill bodies, behavioral scenarios and
their documentation. Claude owns installers, adapters, routing implementation,
technical validators/tests and CI. Existing root config, README and legacy
architecture docs need a coordinated handoff; neither side replaces them silently.
Codex adds the nine lifecycle entries in `registry/registry.yaml` and promotes
the existing security draft. Claude preserves those entries while reconciling
its earlier registry changes. Do not bulk-rename existing skills.

The schema rejects unknown properties and versions. This draft is exact-version
compatible, not a promise of semantic-version interoperability. Any schema/enum
change requires a new contract version and compatibility discussion; readers must
not silently reinterpret unknown fields. Before stability, Claude must report
parser support, reference loading, permission/capability enforcement and actual
fresh-session behavior against this version. Keep limitations explicit.
