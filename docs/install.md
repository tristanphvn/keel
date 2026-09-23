# Installing and removing

Three separable steps. Each one previews by default and writes only with
`--apply`.

```
scripts/install.sh            shared config  ->  $AGENT_HOME
scripts/adapters/<runtime>.sh $AGENT_HOME    ->  the runtime's own integration point
scripts/routing/render.py     role profiles  ->  runtime-native agent definitions  (optional)
```

The installed tree carries `roles/` and `contracts/` as well as `rules/`,
`skills/`, the registry and the commands. Role profiles reference skills by
repository-relative path, so those references have to resolve on the machine and
not only inside a checkout — `tests/test_installer.sh` renders the full
canonical role set against the installed tree to prove they still do.

The default installation depends on nothing project-specific. No vault, no
issue tracker, no network. `skills/vault-rules` and `commands/setup-vault`
describe a convention that is only active if you set `VAULT_ROOT` yourself.

## 1. Shared configuration

```bash
export AGENT_HOME=~/.claude          # the directory your runtime reads
bash scripts/install.sh              # preview
bash scripts/install.sh --apply      # write
```

What it guarantees:

| Promise | How |
| --- | --- |
| A dry run changes nothing | No directory is created and no file is written unless `--apply` is passed. Asserted by comparing a full hash fingerprint of the tree before and after. |
| Your own files survive | Only paths the repo ships are written. Anything else is reported as `LOCAL-ONLY` and left alone. `CLAUDE.md`, `settings.json` and `hooks` are backed up but never written by the installer. |
| Your edits to an installed file survive | Before anything is written, every destination is compared against the hash recorded for it in the manifest. A file you edited since it was installed is reported as `CONFLICT`, and the whole run refuses — no write, no backup, no manifest update. This is conflict protection, not transactional atomicity: it prevents a bad run from starting, it does not make the write loop crash-safe. |
| A failed write cannot truncate a file | Every file is rendered to a temporary path and moved into place. |
| Backups are real | Before the first write, everything that could be overwritten is copied to `$AGENT_HOME/backups/install-<timestamp>/` and compared back. A backup that does not verify aborts the run before anything is written. |
| Dependencies are checked first | Missing tools are listed up front, not discovered halfway through. |
| Repeat installs are predictable | A second run reports `0 file(s) changed`. |
| Failures are visible | Any failed write exits non-zero. |

Useful variables:

- `AGENT_HOME` — target configuration directory. Default `~/.agent`.
- `AGENT_SKILLS_DIR` — install the skills tree somewhere else, for a config
  directory that already belongs to something else. The runtime still has to see
  them at its own path, so pair this with the adapter's `--link-skills`.

### The ownership manifest

`--apply` records every file it wrote, with its hash, in
`$AGENT_HOME/.agent-skills/manifest.tsv`. That file is what makes removal safe:
without it nothing can be proven to belong to the installer, and the uninstaller
refuses to guess.

The same hash is what makes *writing* safe. Installing again compares each
destination against the hash recorded for it. Three outcomes:

- unchanged since install, and the repo has moved on — overwritten, as intended;
- unchanged since install, and the repo agrees — nothing to do;
- **changed since install** — you edited it. Reported as `CONFLICT (edited since
  installed, would be overwritten)`, and the run stops before writing anything,
  taking a backup, or touching the manifest. Save the edit elsewhere or restore
  the file, then re-run.

A destination the installer never recorded is reported as `OVERWRITE (not
recorded by this installer)` and is still written, because the verified backup
covers it and refusing would break a first install onto a directory that already
has its own files at those paths.

A file that was installed previously but is no longer shipped is reported as
`STALE`. It is never deleted by the installer.

## 2. Runtime adapter

### Claude Code

```bash
export AGENT_HOME=~/.claude
bash scripts/adapters/claude.sh --apply     # managed block in CLAUDE.md
bash scripts/adapters/claude.sh --check     # verify
bash scripts/adapters/claude.sh --remove --apply
```

Claude Code auto-loads `$AGENT_HOME/rules/*.md`, so the block adds no import
lines — importing them would load every rule twice, and `--check` fails if any
appear. Only the region between `<!-- agent-skills:begin -->` and
`<!-- agent-skills:end -->` is ever touched; `--remove` restores the file
byte-for-byte.

### Codex

```bash
export AGENT_HOME=~/.agent
bash scripts/adapters/codex.sh --apply          # managed block in ~/.codex/AGENTS.md
bash scripts/adapters/codex.sh --link-skills --apply
bash scripts/adapters/codex.sh --print-config   # TOML to paste, never written for you
bash scripts/adapters/codex.sh --check
```

Codex expands no imports, so this adapter copies the rule bodies into the
managed block. It also measures the result against `project_doc_max_bytes`
(32 KiB by default) and refuses to write past it — Codex would truncate
silently, cutting the block off mid-rule. Raise the budget in `config.toml` and
re-run with `CODEX_DOC_MAX_BYTES` set to match.

Variables: `CODEX_HOME` (default `~/.codex`), `CODEX_SKILLS_DIR` (default
`~/.agents/skills`, which is where Codex looks), `CODEX_DOC_MAX_BYTES`.

**The Codex CLI was not available when this adapter was written.** What it
writes is tested; that Codex reads it is not. See
[runtime-capabilities.md](runtime-capabilities.md).

### Skills installed outside the config directory

```bash
export AGENT_SKILLS_DIR=~/src/agent-skills-tree
bash scripts/install.sh --apply
bash scripts/adapters/claude.sh --link-skills --apply
bash scripts/adapters/claude.sh --unlink-skills --apply
```

The adapter links each skill directory into the path the runtime scans, records
them in a link manifest, and removes only links that still resolve to the target
recorded there. An existing file or directory in the way is a collision: it is
reported, the run exits non-zero, and nothing is overwritten.

On a host that can create neither symlinks nor junctions, linking fails with a
non-zero exit and names the supported alternative. It never falls back to
copying — see the Windows section of the capability matrix for why.

## 3. Role rendering and routing (optional)

Renders the 14 canonical role profiles into agent definitions and binds the
contract's logical model policies to concrete models. See [routing.md](routing.md).
Installation does not require it.

Only roles with an explicit authorized permission set are installed as active
agents in `<target>/agents/`. The rest are written as templates under
`<target>/.agent-skills/templates/<runtime>/`, which no runtime scans — a role
the operator has not authorized is not merely labelled non-executable, it is not
installed where anything could dispatch it.

## Runtime capability records

```bash
python3 scripts/capabilities/validate.py --schema
python3 scripts/capabilities/validate.py --semantic
python3 scripts/routing/render.py --runtime claude --target ~/.claude   --capabilities capabilities/records/claude-code-2.1.220-windows.json   --runtime-version 2.1.220 --platform windows --apply
```

`capabilities/records/` says what a runtime was *measured* to be able to prove.
When a role declares `required_capabilities`, the renderer matches them against
that record and refuses — before writing anything — if the evidence does not
reach the level the capability demands. Unmeasured, documented-only, a record for
another version or platform, or no record at all: all refuse.

The canonical roles declare no required capabilities today, so the default render
needs no record and behaves exactly as before.

Measuring a runtime is a separate, deliberate act:

```bash
bash tests/probes/tool-isolation.sh
bash tests/probes/fresh-context.sh
bash tests/probes/filesystem-read-confinement.sh
```

These are not in `tests/run.sh` — they need credentials, network and billable
usage. Their output is read by a human, who writes the record; probe transcripts
are never committed.

## Validating contract documents

```bash
python3 scripts/contracts/validate.py --schema      # JSON Schema shape
python3 scripts/contracts/validate.py --semantic    # cross-document meaning
```

Two modes, two results, deliberately not merged. The schema checks shape; it
cannot check that an acceptance entry refers to a criterion the task declared,
that an evidence ID exists, that a dependency graph is acyclic or that a
dispatch is accepted only once. Neither mode is runtime enforcement: a valid
document has not been executed, and no permission or budget has been enforced by
validating it. `--schema` needs `jsonschema`; if it is absent the run reports it
as unavailable and fails, rather than counting a skipped check as a pass.

## Removing

```bash
bash scripts/uninstall.sh                # preview
bash scripts/uninstall.sh --apply        # remove
bash scripts/uninstall.sh --stale --apply
bash scripts/uninstall.sh --force --apply
```

Two things are never removed:

- a path absent from the manifest — the installer did not create it;
- a manifest path whose content changed since install — you edited it. It is
  reported as `KEPT (modified since install)` and left in place unless `--force`.

Everything removed is copied to `$AGENT_HOME/backups/uninstall-<timestamp>/`
first, and each copy is hash-verified before the original is deleted.
Directories are removed only when empty, so one local file keeps its directory.

The runtime integration is separate, because it lives in files the machine owns:

```bash
bash scripts/adapters/claude.sh --remove --apply
bash scripts/adapters/claude.sh --unlink-skills --apply
python3 scripts/routing/render.py --runtime claude --target ~/.claude --remove --apply
```

## Verifying an installation

```bash
bash scripts/validate.sh                      # repo-level: schema and references
bash tests/run.sh                             # installer, adapters, routing
bash scripts/adapters/claude.sh --check       # this machine's integration
```

None of these proves runtime discovery. A skill is only confirmed live when a
fresh session of the runtime lists it — that is the fourth validation layer, and
it is recorded in the capability matrix with the version it was measured on.
