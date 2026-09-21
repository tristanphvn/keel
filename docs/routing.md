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
role source, against agent-work contract **0.2.0**. There is no second,
hand-maintained copy: the renderer authors no purpose, responsibility, boundary
or instruction text. Everything it emits is either copied from a canonical
artifact or comes from adapter-owned routing configuration.

Generated files are build outputs. Each records the source profile, the contract
version and the distribution revision; each inlined skill body records its
repository-relative path and sha256. Regenerating replaces them wholesale.

The renderer refuses, with exit 2 and no partial write, when:

- the catalog or a profile declares a `contract_version` other than 0.2.0 — it
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
version: 2
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

Per-role runtime options live in the same file, keyed by role id:

```yaml
roles:
  review:
    claude: {tools: [Read, Grep, Glob, Bash]}
    codex:  {sandbox_mode: read-only}
```

These change how the runtime is configured, never what the role is. A tool list
or a sandbox mode grants nothing on its own — the contract's permission ceiling
is an upper bound, and enforcement belongs to the runtime.

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

## Instruction budget

Preloading makes a role's instructions much larger. `--budget N` sets a
per-file limit; Codex defaults to 32768 bytes, mirroring
`project_doc_max_bytes`. Claude Code documents no equivalent limit, so its
default is unlimited — that is a documented absence, not a measured one.

Over budget, the renderer fails the whole run before writing anything and names
the offending roles. Required instructions are never truncated: raise the
runtime's limit, or move those roles to `skill_delivery: reference` and accept
that they need their Skill tool.

## Ownership

Rendered files are recorded with their hashes in
`<target>/.agent-skills/routing-manifest.tsv`.

- A file at a target path that is not in the manifest is a collision: reported,
  non-zero exit, never overwritten.
- `--remove` deletes only manifest entries whose content still matches; an
  edited file is `KEPT (modified since render)`.
- `--check` fails on a missing, stale or unowned file.

## Config format

YAML, parsed with PyYAML when installed; otherwise a restricted subset parser
(2-space indent, `key: value`, `- ` sequences, inline `[a, b]`, `#` comments,
quoted/bare/int/bool/null scalars) so routing works on a bare Git Bash machine.
Anything outside the subset is an error with a line number. The contract itself
is JSON and never depends on this.
