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
