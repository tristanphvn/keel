# DR-0002 — Machine-readable runtime capability records (M1)

> **One conclusion in this record was later withdrawn.** The
> `workspace-isolation` verdict below rested on a probe that measured filesystem
> read confinement, which is a different property from providing a separate
> writable workspace. Codex's review caught it; DR-0004 reclassifies the
> capability as `unmeasured` and keeps the read observation under its own name.
> The design decisions in this record stand.

Date: 2026-09-21 · Branch: `integration/contracts-v1-runtime` · Baseline: `e566f64`
Contract: 0.3.0 draft, unchanged by this milestone.

Written before the capability system was coded. The two new probes were run
first, because a design that cannot represent the evidence we actually have is
the wrong design.

## The invariant

A role must not render as runnable on a runtime when a capability it requires is
unavailable, unmeasured, unsupported for that runtime version or platform, or
simply absent from the record. Fail closed, before any file is written.

Three distinctions the representation must keep apart, because each has already
been confused once in this repository:

| Not the same as | | |
| --- | --- | --- |
| configured | ≠ | available |
| documented | ≠ | observed |
| model complied | ≠ | runtime enforced |

## Ownership boundary

Two artifacts, two owners, matched by a third component:

```
roles/<id>.json          what a role REQUIRES      canonical, Codex-owned
capabilities/records/*   what a runtime CAN PROVE  measured, adapter-owned
scripts/routing/render.py  matches the two         refuses when unsatisfied
```

The renderer never invents either side. A role's `required_capabilities` remains
the only statement of what a role needs; this milestone adds no second place to
declare that, and does not touch `required_permissions`.

## Decisions

**1. Where the record lives — a new artifact, not the agent-work contract.**

`capabilities/` at the repository root:

- `capabilities/runtime-capability.schema.json` — the record schema
- `capabilities/records/<family>-<version>-<os>.json` — measured records
- `capabilities/examples/*.example.json` — labelled fixtures, never evidence

Rejected: extending `contracts/agent-work.schema.json`. The contract describes
work — roles, tasks, results — and is Codex-owned. Runtime facts are
adapter-owned, change with every runtime release, and differ per machine.
Folding them in would put measurements under contract ownership and force a
contract version bump every time a new version of a CLI is measured. The
contract already draws this line itself: it defines capability *names* and says
nothing about which runtime has them.

**2. Runtime identity — family, version, platform.**

```json
"runtime": {"family": "claude-code", "version": "2.1.220"},
"platform": {"os": "windows", "detail": "MINGW64_NT-10.0-26200"}
```

`family` and `version` are exact strings; there is no range syntax and no
"compatible with" field, because no evidence exists for what a version range
would claim. `platform.os` is a small enum; `detail` is free text for the human
reading the record. No user name, home directory or host name appears in a
record — `validate.sh` section 8 already forbids that repository-wide.

**3. Capability states — five, and "unknown" keeps its reason.**

| State | Meaning | Requires |
| --- | --- | --- |
| `enforced` | the runtime demonstrably prevents the violation | ≥1 evidence entry of kind `enforcement` |
| `observed` | the behaviour was observed; prevention was not tested | ≥1 evidence entry |
| `unavailable` | the runtime was exercised and does not provide it | ≥1 evidence entry |
| `unmeasured` | no probe was run | `reason`, and no evidence |
| `documented` | vendor documentation only | `source`, and no evidence |

`unmeasured` and `documented` are deliberately distinct from `unavailable`: all
three fail closed, but only the last one is a finding. Encoding unknown as false
would erase why it is unknown, which is the failure mode this milestone exists to
prevent.

**4. Evidence — bound to the probe that produced it.**

Each evidence entry carries `probe` (repository-relative path), `probe_sha256`,
`kind` (`observation` | `enforcement`), and `observation` (what was seen). The
digest is what makes staleness detectable: if the probe script changes, the
recorded digest no longer matches the file, and the record's claim is stale.

**5. Staleness — three independent rules.**

- version: a record proves nothing about a version other than its own;
- platform: Windows evidence never certifies Linux or macOS;
- probe drift: a `probe_sha256` that no longer matches the probe in the tree
  invalidates that evidence entry.

There is no expiry date. A date-based rule would either be arbitrary or would
silently invalidate good evidence; the three rules above are all falsifiable.

**6. Which level each capability demands.**

Defined once, in the schema's `$defs.evidence_requirements`, and read from there
by both the validator and the renderer — no second copy.

| Capability | Required | Why |
| --- | --- | --- |
| `spawn` | observation | either a child ran or it did not |
| `model-selection` | observation | the transcript records which model ran |
| `fresh-context` | observation | the property is what the child *received*, read from the runtime's own transcript; there is no prevention to catch |
| `tool-isolation` | **enforcement** | the contract defines it as enforcement "rather than merely request compliance" |
| `workspace-isolation` | **enforcement** | same: a boundary that is not enforced is not a boundary |

`enforced` satisfies both levels. `observed` satisfies only observation-level
requirements — so an observed-but-unenforced tool isolation can never satisfy a
role that requires it.

**7. Tracked, not generated into the tree.**

Records are committed: they are curated evidence, small, and reviewable. Probe
*output* is not committed — transcripts contain absolute paths and, in a
credentialed run, potentially more. A record is written by hand from a probe run
and cites the probe by path and digest; the probe itself is the reproducer.

**8. Renderer failure — before any write.**

The gate runs in the same pre-write phase as the instruction-budget check, which
already establishes the no-partial-write property: everything is rendered into
memory, every gate runs, and only then does the first byte reach disk. A failure
lists every unsatisfied role with the reason per capability and exits 2.

When a role requires capabilities and no record was supplied, that is a refusal,
not a default-allow. When a role requires nothing — the state of all 14 canonical
roles today — rendering proceeds unchanged and no record is needed.

## Evidence this design must represent (measured before designing)

| Capability | Claude Code 2.1.220 / Windows | Probe |
| --- | --- | --- |
| `spawn` | observed | transcripts from the delivery experiment |
| `model-selection` | observed | child `claude-sonnet-5` under parent `claude-haiku-4-5-20251001` |
| `tool-isolation` | **enforced** | `tests/probes/tool-isolation.sh`, three-part |
| `fresh-context` | observed | `tests/probes/fresh-context.sh`, two-canary |
| `workspace-isolation` | ~~unavailable~~ **superseded — now `unmeasured`** | the cited probe measured read confinement, not workspace allocation; see DR-0004 |
| instruction truncation | unmeasured | the 32 KiB budget is configuration, not a measured truncation point |

Codex: no record claiming availability. The CLI is absent, so every capability is
`unmeasured` with a reason, shipped as a clearly labelled example rather than as
a measurement. A role requiring any capability therefore cannot render for Codex
today. That is the correct outcome, not a gap to paper over.

## Rejected alternatives

- **Capability flags inside role profiles.** Would make a runtime fact part of a
  runtime-independent artifact, and every new runtime would edit all 14 roles.
- **Deriving capabilities from the adapter's own tests.** `test_adapter_codex.sh`
  proves what the adapter writes, not what a runtime does. Treating write tests
  as runtime evidence is precisely the confusion this milestone forbids.
- **A single global `capabilities.json`.** One file per runtime/version/platform
  keeps staleness local: a new CLI release adds a file rather than editing a
  shared one, and an unmeasured platform is visibly missing.
- **Defaulting a missing capability to available.** Fails open. Not considered
  further than writing it down here.
