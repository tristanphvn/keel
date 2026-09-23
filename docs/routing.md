# Role rendering and model routing

Turns the canonical role profiles into agent definitions each runtime can read,
and binds the contract's logical model policies to concrete models.

```bash
cp config/routing/models.example.yaml config/routing/models.yaml
python3 scripts/routing/render.py --runtime claude --target ~/.claude
python3 scripts/routing/render.py --runtime claude --target ~/.claude --apply
python3 scripts/routing/render.py --runtime codex  --target ~/.codex  --apply
python3 scripts/routing/render.py --runtime claude --target ~/.claude --check
python3 scripts/routing/render.py --runtime claude --target ~/.claude --remove --apply
```

## One role source

`roles/catalog.json` and the `roles/<id>.json` profiles it lists are the only
role source, against agent-work contract **0.3.0**. There is no second,
hand-maintained copy: the renderer authors no purpose, responsibility, boundary
or instruction text. Everything it emits is either copied from a canonical
artifact or comes from adapter-owned routing configuration.

Generated files are build outputs. Each records the source profile, the contract
version and the distribution revision; each inlined skill body records its
repository-relative path and sha256. Regenerating replaces them wholesale.

The renderer refuses, with exit 2 and no partial write, when:

- the catalog or a profile declares a `contract_version` other than 0.3.0 — it
  will not reinterpret a version it does not implement;
- a reference is absolute, traverses upward, or resolves outside the pinned
  distribution root (symlinks are resolved before the check);
- a referenced skill, rule or profile does not exist;
- a role names a model policy the catalog does not declare;
- a policy the catalog declares has no binding for the target runtime.

## Model policy binding

The contract defines logical policies — `default` and `escalated` — and no model
names, providers, prices or reasoning settings. `config/routing/models.yaml`
binds them, per runtime:

```yaml
version: 3
policies:
  default:
    claude: {model: sonnet}
    codex:  {model: gpt-5.6, reasoning: medium}
  escalated:
    claude: {model: opus}
    codex:  {model: gpt-5.6, reasoning: high}
```

An unresolved policy is a configuration error. No model name is ever guessed,
and no role is quietly run on a substitute.

Verification status of the identifiers themselves is in
[runtime-capabilities.md](runtime-capabilities.md): the Claude aliases are
verified against session transcripts; the Codex identifiers are examples, since
that CLI was not installed. Reasoning is bound per policy — Claude Code
documents no per-agent reasoning key, so none is emitted there.

## Tool limits

The contract names permission **classes**; this file maps them onto the tool
names of each runtime:

```yaml
tool_map:
  claude:
    read:    [Read, Grep, Glob]
    execute: [Bash]
```

A role's limit is then derived from its `required_permissions` through that map,
so the same profile and map give the same limit everywhere. Three outcomes, each
visible in the generated file:

| `tool limit:` says | Meaning |
| --- | --- |
| `derived from the authorized permissions [...]` | contract-driven and deterministic |
| `ADAPTER-DECLARED override — <justification>` | an operator narrowing, labelled as one |
| `NONE - no authorized permission set was supplied` | a template: not executable, and not installed |

An override is an executable configuration, so it is bounded exactly like a
derived list: it requires an authorization, every tool it names must be known to
the `tool_map`, no tool may carry a permission class outside the authorized set,
and the role's floor must still be covered. A justification records *why* an
operator narrowed the tools; it exempts nothing.

Both paths go through **one** tool-list check, because a tool name may be
declared under more than one class:

```yaml
tool_map:
  claude:
    read:    [SharedTool]
    network: [SharedTool]
```

Authorizing `read` here selects `SharedTool`, and `SharedTool` declares
`network` as well. Deriving the list from the authorized classes does not make
that second class go away, so a name mapped outside the authorized set is
refused whichever path selected it — derived or overridden.

What the map does and does not establish: it says which classes a tool **name**
is declared to carry, so a tool outside the authorization can be refused before
anything is written. It does not confine what a tool does once it runs — a shell
authorized for `execute` can still write files and reach the network. Only the
runtime can prevent that, and whether it does is a capability question answered
by evidence, never by this table.

Version 3 **refuses** a per-role `tools:` list. Choosing a tool limit per role is
behavioural — removing an execute tool turns a role's result into `blocked` — so
it belongs to the contract, not to adapter configuration. An operator exception
is still possible through `tools_override`, but it requires a `justification` and
is stamped ADAPTER-DECLARED in the output. A permission class a role requires but
the map does not cover is a configuration error, not a silently dropped
capability.

Other per-role options, keyed by role id, change only how the runtime is
configured: `codex.sandbox_mode`, and `skill_delivery` to override the automatic
choice. None of them grants anything — the contract's permission ceiling is an
upper bound, and enforcement belongs to the runtime.

## Skill delivery

Every role must actually receive its `skill_refs`. Two mechanisms:

| Mechanism | When | What the agent gets |
| --- | --- | --- |
| `reference` | the agent keeps its `Skill` tool | canonical paths, loaded by the agent |
| `preload` | the role's tools are restricted | the canonical bodies, inlined with provenance |

Chosen automatically; override per role with `skill_delivery`.

The reason is measured, not assumed. On Claude Code 2.1.220, an agent given an
explicit `tools` list without `Skill` has no Skill tool — and a control run
confirmed such a child receives **no** skill text when delivery is `reference`.
Preloading closes that gap without widening the agent's permissions. Both arms
of that experiment are recorded in the capability matrix.

Preloaded copies are build outputs, not a second source: each is wrapped in
`<!-- begin canonical skill: <path> sha256=... -->` markers, and the profile
continues to point at the canonical file.

Each `--apply` also writes `<target>/.agent-skills/delivered-skills-<runtime>.json`:
what was delivered per role, by which mechanism, with digests. That is the
adapter's record for a result's `delivered_skills` provenance — a delivery claim,
never evidence that the instructions were relied upon.

## Instruction budget

Preloading makes a role's instructions much larger. `--budget N` sets a
per-file limit; Codex defaults to 32768 bytes, mirroring
`project_doc_max_bytes`. Claude Code documents no equivalent limit, so its
default is unlimited — that is a documented absence, not a measured one.

Over budget, the renderer fails the whole run before writing anything and names
the offending roles. Required instructions are never truncated: raise the
runtime's limit, or move those roles to `skill_delivery: reference` and accept
that they need their Skill tool.

## Where rendered roles are stored

Placement, not wording, is what keeps an unauthorized role from being dispatched:

| Role | Written to | Discovered by the runtime |
| --- | --- | --- |
| authorized | `<target>/agents/<id>.<ext>` | yes — this is the installed, active agent |
| unauthorized | `<target>/.agent-skills/templates/<runtime>/<id>.<ext>` | **no** |

Both runtimes scan their `agents` directory. A comment saying NON-EXECUTABLE
does not stop a runtime listing and dispatching a file it finds there, so a
template is written somewhere the runtime never looks, alongside a README
explaining why.

### Changing sides

A role that gains or loses its authorization must not leave its old file behind:
an executable that becomes a template would otherwise stay discoverable.

- The old file is removed only when this renderer **owns** it (it is in the
  manifest) **and** its digest still matches what was written. Reported as
  `DEACTIVATE` or `PROMOTE`.
- A file that was modified since it was rendered, or that this renderer never
  wrote, is **preserved**. The run reports a `CONFLICT`, writes nothing, and
  exits non-zero — it will not claim a deactivation that did not happen. An
  unauthorized role whose executable definition is still in place is still
  dispatchable, and saying otherwise would be the worst outcome here.
- `--check` fails if a role is missing from its expected location, is stale, is
  unowned, or has a copy at the *other* location.

## Ownership

Rendered files are recorded with their hashes in
`<target>/.agent-skills/routing-manifest.tsv`, templates included, so `--remove`
cleans up both.

One ownership test decides every file a render touches, and it runs as a
**preflight**: each destination, each file at the *other* location, and the
generated auxiliary files (the templates `README.md` and the delivery record)
are all checked before the first byte is written.

- A file at a target path that is not in the manifest is a collision: reported,
  non-zero exit, never overwritten.
- A file that **is** in the manifest but whose digest no longer matches what was
  recorded for it carries an edit made since the render, and is treated exactly
  the same way. Being a known path is not what makes a file safe to replace;
  matching the digest it was written with is.
- One conflict refuses the **whole run** — no file written, none removed, no
  migration performed, and no manifest or delivery record updated. A partial
  apply would leave the target half-migrated and then describe it with a
  delivery record for a delivery that did not happen.
- `--remove` deletes only manifest entries whose content still matches; an
  edited file is `KEPT (modified since render)`. Unlike a render, it removes the
  files it can and still exits 0.
- `--check` fails on a missing, stale or unowned file.

## Config format

YAML, parsed with PyYAML when installed; otherwise a restricted subset parser
(2-space indent, `key: value`, `- ` sequences, inline `[a, b]`, `#` comments,
quoted/bare/int/bool/null scalars) so routing works on a bare Git Bash machine.
Anything outside the subset is an error with a line number. The contract itself
is JSON and never depends on this.
