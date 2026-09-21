# Role-to-model routing

Maps role ids onto concrete provider/model identifiers per runtime, and renders
one agent definition per role in the format each runtime actually reads.

```bash
cp config/routing/models.example.yaml config/routing/models.yaml
python3 scripts/routing/render.py --runtime claude --target ~/.claude
python3 scripts/routing/render.py --runtime claude --target ~/.claude --apply
python3 scripts/routing/render.py --runtime codex  --target ~/.codex  --apply
python3 scripts/routing/render.py --runtime claude --target ~/.claude --check
python3 scripts/routing/render.py --runtime claude --target ~/.claude --remove --apply
```

Routing is **optional**. With no `models.yaml` the renderer prints that fact and
exits 0; the installation is complete without it.

## Boundary: what routing does not own

Routing does not define roles. A role's purpose and its instructions are
canonical artifacts owned outside this layer. Here a role is:

- an opaque `id`,
- a pointer to its `profile` file, and
- the runtime-facing settings that decide which model runs it.

The renderer copies instructions from the profile verbatim and **never authors
them**. A role without a `profile` is a schema error. A profile without a
`description`, or with an empty body, is a schema error. This is deliberate: a
generated role instruction is a contract invented by the wrong component.

Until canonical role profiles exist, keep `roles: []`. The renderer will say
there is nothing to render, which is the correct state, not a failure.

## The three layers, kept separate

| Layer | Key | Why separate |
| --- | --- | --- |
| Model selection | `catalog[].tier` → per-runtime `model` | A role names a tier, not an identifier, so re-pointing a tier changes every role at once. |
| Reasoning | `reasoning.default`, `roles[].reasoning` | The same tier is used at different depths, and the runtimes express depth differently. |
| Fallback | `fallback.*` | What happens when a request cannot be honoured is a policy decision, not a property of a model. |

## Model identifiers

Only identifiers verified against the runtime you target belong in `catalog`.
Informal or marketing names are not API identifiers; they fail at spawn time or
resolve to something you did not choose.

Verification status lives in
[runtime-capabilities.md](runtime-capabilities.md). At the time of writing:

- **Claude Code** — the CLI aliases `opus`, `sonnet`, `haiku` are accepted in
  agent frontmatter and were observed resolving to concrete model ids in the
  session transcripts (`haiku` → `claude-haiku-4-5-20251001`). Verified.
- **Codex** — the identifiers in the example file come from vendor
  documentation examples and are **unverified here**, because the Codex CLI was
  not installed. Replace them with identifiers you have confirmed.

## Fallback policy

```yaml
fallback:
  on_unknown_model: deny          # or: use_default
  on_missing_capability: [degrade_to_inline, deny]
```

- `on_unknown_model: deny` — a role asking for a tier with no model for the
  target runtime is a schema error. Nothing is substituted silently. This is the
  default, because a silent substitution means work runs on a model nobody
  chose.
- `on_missing_capability` — ordered steps when the runtime cannot do what the
  role needs. `degrade_to_inline` means: run the role's instructions in the
  current session instead of a separate agent, and say so. `deny` means fail
  loudly.

Capability gaps that currently trigger this, with their measured status, are
listed in the capability matrix. One worth stating here: **Claude Code
documents no per-agent reasoning setting**, so the renderer emits no reasoning
key for that runtime rather than inventing one. The value is still used for
Codex.

## Rendered output

| Runtime | Path | Format |
| --- | --- | --- |
| `claude` | `<target>/agents/<id>.md` | YAML frontmatter: `name`, `description`, `model`, optional `tools`; body = profile instructions |
| `codex` | `<target>/agents/<id>.toml` | `name`, `description`, `developer_instructions`, optional `model`, `model_reasoning_effort`, `sandbox_mode` |

A caution measured on Claude Code: restricting a sub-agent's `tools` removes its
access to skills unless `Skill` is in the list. Omit `tools` to inherit the
parent's set.

## Ownership

Every rendered file is recorded with its hash in
`<target>/.agent-skills/routing-manifest.tsv`.

- A file at the target path that is **not** in the manifest is a collision: it
  is reported, the run exits non-zero, and nothing is overwritten.
- `--remove` deletes only manifest entries whose content still matches. An
  edited file is reported as `KEPT (modified since render)`.
- `--check` fails if a rendered file is missing, stale, or unowned.

## Config format

YAML, parsed with PyYAML when it is installed. When it is not, a parser for a
restricted subset is used instead, so routing works on a bare Git Bash machine:

- 2-space indentation, `key: value` mappings
- `- ` sequences of scalars or of mappings
- inline `[a, b]` flow sequences
- `#` comments
- scalars: quoted strings, bare strings, integers, `true`/`false`, `null`

Anything outside the subset is an error with a file and line number, never a
guess. Validation errors exit 2; collisions and write failures exit 1.
