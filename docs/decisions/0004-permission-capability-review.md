# DR-0004 — Answering Codex's review of b6733f9

Date: 2026-09-21 · Branch: `fix/permission-capability-review`
Baseline: `cae50cc` (PR #4, `codex/permission-contract-review`), itself on `b6733f9`
Contract: **0.3.0 draft**, unchanged by this work. Capability record schema: 1 → 2.

Codex's findings are in `docs/decisions/0003-codex-integration-review.md`. All four
were reproduced against the reviewed source before anything was changed; the
reproductions and the corrected behaviour are recorded below.

The canonical permission floors Codex authored are used as given. None was
widened, narrowed or re-argued to make the renderer's life easier — where a
floor made rendering fail, the renderer changed.

## R1 — Permission handling

**Reproduced at `cae50cc`:**

| Probe | Result |
| --- | --- |
| `effective_tools` for `testing` (floor `read, execute`) | `(['Read','Grep','Glob','Bash'], 'contract', '')` — the floor used as the entire allowlist |
| `tools_override: []` with a justification | `(['Read','Grep','Glob'], 'contract', '')` — the explicit empty list silently ignored |
| `testing` task granting only `read` | no semantic failure |

**Three separate defects, three separate fixes.**

*The floor is not the allowlist.* `required_permissions` is a minimum, so deriving
the tool list from it caps every role at its minimum — a `review` role could never
write the report the contract explicitly says it may. Effective tools now come
from an **authorized permission set**, supplied per role (optionally per runtime)
in adapter-owned configuration, and checked against both halves of the contract's
inequality: `floor ⊆ authorized ⊆ ceiling`. Below the floor and above the ceiling
are each refused, with the missing or excess classes named.

*Omitted is not empty.* `if override:` treated `[]` as absence. An explicitly
empty list is a decision meaning **no tools**, so it can never fall back to
inherited ones. Whether Claude Code represents an empty `tools:` list as "no
tools" rather than "unrestricted" has **not been measured here**, so the renderer
refuses and says exactly that, rather than emitting something whose meaning it
cannot state. Measuring it is a probe, not a guess — deliberately not done under
a review-fix branch.

*Absent authorization is not permission to inherit.* A role with no authorized set
now renders as a **template**: no tool limit, and a prominent `NON-EXECUTABLE
TEMPLATE` marker in the generated file saying it would inherit the parent's tools
and must not be dispatched. This is the option the contract allows — "static role
generation can produce templates" — and not the one it forbids, which is claiming
an authorized, restricted execution from a profile alone.

*Overrides are not exempt.* A `tools_override` must still cover the role's floor,
justified or not; coverage is computed through the adapter's tool map. Where no
map is declared, coverage is unknowable and the override is refused rather than
trusted.

These are static generation checks. They are not dispatch-time enforcement, and
nothing here claims to be: no orchestration engine was added.

**Consequence, accepted rather than worked around.** The Codex tool map is empty,
because no Codex tool identifier has been verified. Authorizing a Codex role
therefore fails with an unmapped-class error, exactly as Codex predicted. The
example configuration authorizes Claude roles only, and Codex roles render as
templates. No identifier was invented to make that go away.

## R2 — Task capability requirements

**Reproduced:** a `testing` task requiring `tool-isolation` failed with
`requires no capability the role does not name`.

The check treated `optional_capabilities` as a ceiling. The contract says the
effective requirement is the **union** of role and task. The validator now checks
the task's capabilities against the closed vocabulary, reports the effective
union, and — when a capability record is supplied via `--capabilities` — enforces
that union against real evidence using the same verdict logic the renderer uses.
One implementation, so a task cannot be accepted against a record the renderer
would reject. No capability was added to any role.

## R3 — Evidence validation on the render path

**Reproduced:** with every evidence item removed from the `tool-isolation` entry,
`capability_verdict` returned `(True, 'enforced')` and `check_capabilities`
reported no failures. The renderer read the label and believed it.

The renderer now runs the **canonical** validator — `validate_record_file` in
`scripts/capabilities/validate.py` — before a record authorises anything: schema,
evidence presence and required kind, probe containment, existence and digest, and
the example-versus-measured rule. Failure is refusal before any write, with the
problems listed. A second, weaker implementation at the call site is what the
review found, so there is now one implementation and the renderer imports it.

Where `jsonschema` is unavailable the record cannot be validated, so it cannot
authorise: fail closed, with a message saying an unvalidated record is not
evidence.

**Target identity is now required, not optional.** `--runtime-version` and
`--platform` were match flags that did nothing when omitted; a record could
authorise a render against an unnamed target. When any role requires a
capability, both must be stated, and a mismatch on family, version or platform
refuses.

Record validation is not probe re-execution. Passing says the record is
well-formed and internally consistent, not that the runtime still behaves that
way.

## R4 — Workspace isolation

Codex is right, and the earlier conclusion was wrong.

The contract defines `workspace-isolation` as providing a **separate writable
workspace** for a task. The probe attempted a **read** outside the session
directory and concluded the capability was `unavailable`. Those are different
properties: separate worktrees can give each task its own writable location while
still permitting reads elsewhere, so an unconfined read neither establishes nor
refutes workspace allocation.

- The canonical definition is untouched. No new vocabulary was introduced; a new
  capability name would need its own contract proposal.
- `workspace-isolation` is now **`unmeasured`**, with the reason recorded.
- The observation is preserved, accurately labelled, under a new `observations`
  section: `filesystem-read-confinement`, carrying its probe, digest and what was
  actually seen, plus `not_a_claim_about: [workspace-isolation]`.
- The probe is renamed `tests/probes/filesystem-read-confinement.sh` and its
  verdicts now read CONFINED / UNCONFINED / INCONCLUSIVE. A file named after a
  capability it does not measure is how this happened in the first place.

Observations are never consulted when deciding whether a role may render, and the
validator enforces that a capability disclaimed by an observation is not
simultaneously claimed as measured.

**Capability record schema 1 → 2.** Adding `observations` to a closed schema
(`additionalProperties: false`) means a version-1 reader must reject a version-2
record, so the version moved — the same rule applied to the contract itself. This
is the adapter-owned record schema, not the agent-work contract, which stays
0.3.0 draft and is untouched by this branch.

## Ancillary

- The tracked `scripts/routing/__pycache__/render.cpython-313.pyc` is removed and
  `__pycache__/` ignored. The renderer and validators are imported as modules by
  tooling and tests, so bytecode regenerates; it is build output.
- PR #3's description claimed no Linux evidence exists. Linux CI has since run:
  it provides **static and adapter-write** evidence on Ubuntu, not Claude or Codex
  runtime evidence. The sentence is corrected to say exactly that.

## What this branch does not do

No PR merged, no contract version bump, nothing marked stable or
runtime-conformant, no M2 harness, and no Codex runtime claim. An empty-tool-list
measurement and a genuine workspace-allocation probe are both still missing, and
both are named as such rather than approximated.

---

## Follow-up: the two PR #5 review blockers

Reviewed head `0be92f7`. Both reproduced against that source before any change.

### Overrides bypassed authorization and the ceiling

The override branch checked floor coverage and returned, so everything after it —
the authorization check, the ceiling, the tool map — never ran. Reproduced:

| Case | Before |
| --- | --- |
| `documentation` (floor `read`, ceiling `read, write`), authorized `[read]`, override `[Read, WebFetch]` | accepted; `WebFetch` carries `network`, outside both |
| override `[Read, UnknownTool]` | accepted; the tool is absent from the map, so its classes are unknown |
| override `[Read]` with no `permissions:` | accepted; an executable tool list with nothing authorizing it |

Every executable path now passes through one gate. An override requires an
explicit authorization, is validated as `floor ⊆ authorized ⊆ ceiling`, must name
only tools the map describes, may not include a tool carrying a class outside the
authorization, and must still cover the floor. A justification records why an
operator narrowed the tools; it exempts nothing. All three cases now refuse with
exit 2 and write nothing.

The mapping's limit is stated where it is used: it constrains tool **names**
before anything is written. It does not confine what a tool does once it runs — a
shell authorized for `execute` can still write and reach the network. That is a
runtime enforcement question, answered by capability evidence, not by this table.

### "Non-executable" templates were installed as discoverable agents

They were written to `agents/`, which both runtimes scan. A `NON-EXECUTABLE
TEMPLATE` comment does not stop a runtime listing and dispatching a file.

The split is now structural. Authorized roles are installed at
`<target>/agents/<id>.<ext>`; unauthorized roles are written to
`<target>/.agent-skills/templates/<runtime>/`, which no runtime scans, with a
README stating why. The same rule applies to both adapters, and the manifest,
`--check`, `--remove` and the delivery record (which now carries `executable`
per role) all follow it.

Transitions are the dangerous part, so they are explicit:

- losing authorization removes the installed agent and writes the template
  (`DEACTIVATE`); regaining it does the reverse (`PROMOTE`);
- the old file is removed **only** when this renderer owns it and its digest
  still matches;
- a modified or unowned file is preserved, reported as `CONFLICT`, and the run
  exits non-zero having written nothing. Claiming a deactivation that did not
  happen would be worse than failing: the role would still be dispatchable.

---

## Follow-up: two further PR #5 defects

Reviewed head `92e5fa7`. Both reproduced against that source before any change.

### A modified destination file was overwritten

The preflight for a role *changing sides* checked the file at the other location
against the manifest digest. The write loop, dealing with the destination, asked
only whether the path was **in** the manifest — never whether the bytes still
matched the digest recorded for it. An owned path was therefore treated as a free
path.

| Step | Before |
| --- | --- |
| render an authorized role, digest recorded | `381eeac5…` in the manifest and on disk |
| append an operator edit | `d1b97b0a…` on disk |
| render again at the same location | exit **0**, file back to `381eeac5…`, edit gone |
| append an edit to the templates `README.md` | overwritten the same way |

The ownership question is now asked once, by `ownership_conflict()`, for every
file a render touches — each destination, each migration source, and the
generated auxiliary files — and it is asked as a **preflight**, before the first
mutation. Not in the manifest means someone else's file; in the manifest with a
digest that no longer matches means someone's edit. Both are preserved and
reported, and a conflict anywhere refuses the whole run: nothing written, nothing
removed, no migration performed, no manifest and no delivery record updated.

The auxiliary files are in scope because they are build outputs like any other. A
templates `README.md` is not overwritable merely because the renderer knows its
path; nor is the delivery record.

Batch atomicity is the point of the preflight rather than a side effect. The
previous code counted collisions mid-loop and carried on, so an unrelated role
was still written, an unrelated migration still performed, and the manifest still
rewritten — leaving a half-migrated target described by a delivery record for a
delivery that did not happen.

### Derived tool lists bypassed the multi-class check

`effective_tools()` checked every *override* tool's mapped classes against the
authorization. The derived path walked the authorized classes, collected their
tool names and returned without ever asking what else those names were mapped to.

Reproduced with floor `[read]`, ceiling `[read, write]`, authorized `[read]`,
`tool_map: read → [SharedTool], network → [SharedTool]`, no override:

| Path | Before |
| --- | --- |
| derived | `(['SharedTool'], 'authorized', 'read')` — accepted, and `SharedTool` declares `network`, outside the authorization and the ceiling |
| the same tool named as an override | already refused, exit 2 |

One shared gate, `check_tool_selection()`, now validates both paths: every
selected tool must be described by the map, and none may declare a class outside
the authorized set. The floor, ceiling, unknown-class, unmapped-class and
empty-override checks are unchanged and still run.

This concerns **declared mappings**. It does not claim the map confines what a
tool does once it runs — the same limit already recorded above.

Neither shipped `tool_map` (`models.example.yaml`, and the local `models.yaml`)
declares a tool name under two classes, so no currently rendered output changes.
The check closes the path, it does not alter today's results.

---

## Follow-up: the installer had the same ownership defect

Found while reviewing adjacent execution paths against the invariant the
renderer fix established. Reproduced at `192aa67` before any change.

`scripts/install.sh` writes `path<TAB>sha256` for every file it installs, and
its own header says a path "whose hash no longer matches has been edited by the
user since". `scripts/uninstall.sh` honours that — it refuses to delete an edited
file and reports `KEPT (modified since install)`, requiring `--force`. The
installer did not. It compared the destination against the rendered source and
overwrote on any difference, so "the user edited this file" and "the repo moved
on" were indistinguishable.

The hash needed to tell them apart was written on every run and then loaded with
`cut -f1` (line 103), which discarded the digest column.

| Step | Before |
| --- | --- |
| `install.sh --apply` into a fresh `$AGENT_HOME` | manifest records `98133280…` for `skills/review-code/SKILL.md` |
| append a local customization | `d77f5dee…` on disk |
| `install.sh --apply` again | exit **0**, `OVERWRITE`, file back to `98133280…` — customization gone |

A preflight now compares every destination against its recorded hash before the
first write. A file that would change and whose digest no longer matches is
reported as `CONFLICT` and the run refuses — before the backup is taken, so a
refused run leaves no new backup directory and no manifest rewrite either.

Two deliberate limits, both stated rather than quietly assumed:

- **Conflict protection is not transactional atomicity.** The preflight stops a
  bad run from starting. It does not make the write loop crash-safe; a failure
  part-way through still leaves a partially updated tree, and the verified backup
  is what covers that. The same distinction applies to the renderer.
- **A destination absent from the manifest is reported, not blocked.** It is now
  labelled `OVERWRITE (not recorded by this installer)` instead of a bare
  `OVERWRITE`. Blocking it would break a first install onto a directory that
  already holds the user's own files, and the verified backup already covers the
  case. Whether to promote it to a refusal is a separate decision, like
  `--remove`'s exit semantics.

### Canonical positions carried forward

Contract 0.3.0 stays draft. A probe of separate writable workspaces and
independent writes belongs to `workspace-isolation` — no new vocabulary, and the
capability stays `unmeasured` until such a probe exists. Filesystem confinement
remains a separate property and is recorded as an observation; any vocabulary for
it would be proposed on its own. Codex runtime behaviour is still unverified and
no tool identifier was invented. No orchestration engine or conformance harness
was added.
