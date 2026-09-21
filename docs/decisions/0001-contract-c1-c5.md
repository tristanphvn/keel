# DR-0001 — Resolving C1–C5 against contract 0.2.0 draft

Date: 2026-09-21 · Branch: `integration/contracts-v1-runtime` · Baseline: `6f0a72f`
Contract at time of writing: **0.2.0 draft** (`contracts/README.md`)

Written before implementation. Each decision names the repository evidence it
rests on, and each disputed statement is classified:

- **FACT** — observed in this repository or in a recorded runtime transcript
- **INFERENCE** — follows from facts plus a stated invariant
- **ASSUMPTION** — believed, not checked; marked so it can be attacked later
- **UNKNOWN** — not established, and not treated as either way

The review below is my own multi-perspective pass, not a panel of agents. No
separate reviewer process was run; where a perspective produced no material
disagreement it is omitted rather than padded.

## Invariants used to adjudicate

1. Role semantics stay runtime-independent.
2. Adapters implement mechanism; they do not author behavioural policy.
3. Least privilege needs a declared floor, not only a ceiling.
4. Rendering is deterministic and traceable to canonical sources.
5. One source of truth per fact.
6. Evidence is classified by what was actually observed.
7. `additionalProperties: false` stays; strictness is not traded for convenience.

---

## C1 — Role → tool requirements

**Problem.** Roles declare `permission_ceiling`; nothing declares what a role
*needs*. The adapter's routing config therefore chooses tool lists per role.

**Evidence.**

- FACT: `roles/review.json` has `permission_ceiling: [read, write, execute]`.
- FACT: `contracts/README.md` — "A role's `permission_ceiling` is an upper
  bound, not a grant" and "Review may write its report, not the reviewed source".
- FACT: before this change, `config/routing/models.example.yaml` granted `review`
  `[Read, Grep, Glob, Bash]` — **no write tool at all**. The adapter had silently
  decided that the review role cannot write its own report.
- FACT: Claude Code agent definitions are static files; the tool list is fixed at
  render time, not at dispatch (measured: agent frontmatter `tools:` is honoured,
  and a tool outside it is refused — see C4).
- INFERENCE: a tool list chosen by the adapter can flip a role's outcome from
  `completed` to `blocked` (a `testing` role without an execute tool cannot run
  tests). Under invariant 2 that makes it behavioural policy, not deployment
  detail.

**Options.** (A) contract declares required tool classes; (B) contract declares
tool restriction adapter-owned.

**Decision — A, in the contract's existing vocabulary, plus the explicit half of B.**

- Role gains **optional** `required_permissions`: a subset of the same
  `read|write|execute|network|delegate` labels, meaning "without these the role
  cannot discharge its responsibilities". No new vocabulary is introduced.
- Tool **names** remain adapter-owned: the contract gains an explicit statement
  that mapping permission classes to concrete tool identifiers belongs to the
  adapter, since the names are runtime-specific.
- The adapter config gains a `tool_map` keyed by permission class per runtime.
  Restrictions are derived from `required_permissions` through it — deterministic
  (invariant 4) and identical for every adapter that implements the same map.

**Why not B.** B is cheaper for me and worse for the system: it legitimises the
exact defect found above, and adding a runtime would mean re-deciding each role's
tool policy per adapter, with no canonical record of what a role actually needs.

**Why not a new `tool_profile` vocabulary.** It would duplicate the permission
enum with different words, and every future runtime would need a second mapping
table. Rejected under invariant 5.

**Residual, stated plainly.** Populating `required_permissions` for the 14 roles
is role semantics and therefore Codex's to author. This branch ships the
mechanism with the field unpopulated. Consequence: until it is populated, roles
render with **no** tool restriction (inherit), which is less restrictive than
today's adapter-invented lists. Rather than silently lose least privilege, an
operator may still set an explicit restriction — but it must be written as
`tools_override` with a `justification`, and the renderer stamps the generated
file as carrying an *adapter-declared* restriction rather than a contract-derived
one. Adapter policy becomes visible instead of silent, which is the actual
requirement.

---

## C2 — Delivered skill provenance

**Problem.** Nothing in a result records which skill bodies reached the child.

**Evidence.**

- FACT: `result.provenance` requires runtime, runtime_version, adapter,
  profile_revision, model, workspace_revision; `additionalProperties: false`.
- FACT (measured, 2.1.220): with `skill_delivery: reference` and a restricted
  tool list, the child reported the canonical sentence as `NOT-PRESENT`; with
  `preload` the same child quoted it verbatim.
- INFERENCE: "the role declared a skill" and "the child received it" are
  different claims, and today only the first is representable.

**Four stages, only some of which are provable.**

| Stage | Provable by | Status |
| --- | --- | --- |
| declared by the role | `roles/<id>.json` `skill_refs` | FACT, static |
| resolved by the renderer | reference resolution + sha256 | FACT, static |
| delivered into the runtime context | the adapter's own record of what it embedded or referenced | adapter claim |
| relied upon during execution | nothing available | **UNKNOWN — not representable** |

**Decision.** `result.provenance` gains an **optional** `delivered_skills`:
`[{ref, sha256, method: preload|reference}]`.

- It is the *adapter's* claim about stage 3, and `contracts/README.md` says so in
  those words: recording delivery is not evidence of reliance, and no field
  asserts stage 4.
- The semantic validator checks what it can: every `ref` must be a `skill_ref` of
  the result's role, `sha256` must be 64 hex characters, `method` must be in the
  enum, and refs must be unique.
- `method: reference` deliberately records a *weaker* claim than `preload`: the
  skill was made available, not placed in context. The distinction is the point.

**Rejected alternative.** A top-level `delivered_skills` on the result. Provenance
is where "where did this execution's inputs come from" already lives (invariant 5).

---

## C3 — `rules/70-routing.md`

**Problem.** `rules/` holds 8 files; `roles/catalog.json` enumerates 7.

**Evidence.**

- FACT: `git log --diff-filter=A` shows `rules/70-routing.md` was added by
  `c3d0169` — adapter work on my branch, not by the contract branch.
- FACT: its body is a task→skill selection table naming legacy skill directories,
  including `vault-rules`.
- FACT: `docs/orchestration-handoff.md` — "Do not auto-load Vault/vendor
  workflows through a default routing rule."
- FACT: the repository baseline requires the default installation to work without
  Vault or any tracker.
- FACT (measured, 2.1.220): every file in `$AGENT_HOME/rules/` loads without any
  import. So while the file sits there, Claude Code receives a routing rule that
  the canonical model never declared — exactly the state C3 forbids.
- INFERENCE: role `skill_refs` now express role→skill selection canonically, so
  the table is a second, competing selection surface (invariant 5).

**Classification: (B) adapter-local legacy guidance, already superseded.**

**Decision — delete it, structurally.** Remove `rules/70-routing.md`, remove its
import from `config/AGENTS.md`, and return `validate.sh` to the seven canonical
rule files. `rules/` then equals the catalog's `rule_refs` exactly, and neither
adapter can materialise a rule the contract does not acknowledge. No copy is kept
anywhere: a copy would recreate the second surface. What it used to say, and why
it is gone, is recorded in the migration log.

**Note on ownership.** `config/AGENTS.md` is listed as needing coordinated
handoff. The only edit here is removing the import line that my own earlier
commit added, so the file returns to its pre-`c3d0169` content.

---

## C4 — Tool-isolation evidence

**Problem.** The contract defines `tool-isolation` as enforcement, "rather than
merely request compliance". The earlier observation — a child reporting a short
tool list — did not establish that.

**Decision — keep the strict definition, and define the probe that can satisfy it.**

Required evidence, all three parts:

1. the restricted child emits a real `tool_use` block for the excluded tool;
2. the runtime returns `tool_result` with `is_error=true`;
3. an otherwise identical child **with** that tool succeeds in the same session,
   so the refusal is attributable to the tool list rather than to the tool being
   broken or disabled session-wide.

Read from session transcripts, never from the agent's prose. Implemented as
`tests/probes/tool-isolation.sh`; not in `tests/run.sh`, because it needs
credentials, network and billable usage.

**Result on Claude Code 2.1.220 — ENFORCED (FACT).**

```
restricted-probe (tools: Read)        TOOL_USE 'Bash'  -> TOOL_RESULT is_error=True
                                      "No such tool available: Bash"
allowed-probe    (tools: Read, Bash)  TOOL_USE 'Bash'  -> TOOL_RESULT is_error=False
                                      "ISOLATION-PROBE"
```

Both arms ran in one session with identical parent flags; the agent definition
was the only difference. The first arm's error text also mentions a session-level
restriction — the control arm succeeding in that same session is what rules that
explanation out.

**Codex: UNKNOWN.** The CLI is not installed; no probe was run. The capability
stays unavailable there, per the contract's own rule that unverified capabilities
count as unavailable.

**Explicitly not decided:** that other capabilities are enforced. `fresh-context`
and `workspace-isolation` have no probe yet and remain unmeasured.

---

## C5 — Canonical completed result example

**Problem.** `contracts/examples/result.json` is `blocked` with empty `evidence`
and `changed_files`, so acceptance semantics are exercised only by fixtures my
own tests synthesise — which cannot catch a contract that drifts away from them.

**Decision.** Add a second canonical pair, `task-completed.json` /
`result-completed.json`, that is `completed`, carries two criteria, real evidence
entries referenced by the acceptance rows, one changed file inside the declared
write scope, and `delivered_skills` provenance. It uses only repository-relative
references and fixture revisions — no absolute path, no environment, no secret.

Both pairs are wired into `scripts/validate.sh` and `tests/test_contracts.sh`, so
an example that stops satisfying the schema or the semantics fails the build.
The existing `blocked` example stays: the two together cover both ends of the
status range.

---

## Versioning

- FACT: `contracts/README.md` — "Any schema/enum change requires a new contract
  version and compatibility discussion; readers must not silently reinterpret
  unknown fields."
- FACT: every definition sets `additionalProperties: false`, and
  `contract_version` is `{"const": "0.2.0"}`.
- INFERENCE: adding optional fields under the unchanged version would produce
  documents that a conforming 0.2.0 reader must **reject**, while both claim the
  same version. That is precisely the silent incompatibility the rule forbids.

**Decision: bump to `0.3.0`, still draft.** This is the repository's own
versioning contract requiring it, not an automatic bump. Role profiles, the
catalog and the examples change only their `contract_version` string; no role
semantics are edited. The renderer and validator keep pinning one exact version
and continue to reject any other.

**Not done:** marking the contract stable. It remains draft pending Codex's
review of these changes.

---

## Material disagreements surfaced by the review

**Security vs. maintainability, on C1.** Shipping `required_permissions`
unpopulated loosens today's effective restriction. The security reading says keep
the adapter lists; the contract-design reading says an adapter must not own that
decision. Resolved by evidence: the adapter's current list already removes a
permission the role's own ceiling grants (`write` for `review`), so the existing
restriction is not a considered security control — it is an accident that looks
like one. Keeping it would preserve the appearance of least privilege while the
canonical model stays silent. The `tools_override` + `justification` path keeps a
real control available to an operator and labels it honestly.

**Adapter-author vs. provenance, on C2.** `method: reference` records that a
skill was *offered*, which is weaker than `preload`. Argument for dropping it:
recording a weak claim invites reading it as a strong one. Argument for keeping
it: omitting it makes "referenced" indistinguishable from "never delivered", and
the measured control run shows those are genuinely different outcomes. Kept, with
the asymmetry stated in the contract text.

**Portability, on C3.** Deleting the routing rule removes selection guidance for
the standalone skills (`vault-rules`, `ticket-pr`, `workos`) that no role
references. Counter-evidence: those skills carry their own trigger descriptions,
which is the mechanism the runtime actually uses for lazy loading — measured
during earlier discovery work. No replacement surface is needed.
