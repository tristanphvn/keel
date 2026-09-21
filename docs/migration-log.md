# Migration log

One entry per structural change to the global configuration. Newest last.

## 2026-09-17 — rules split

`$AGENT_HOME/learned-rules.md` split into seven files under `$AGENT_HOME/rules/`, imported from `AGENTS.md`. Rule IDs unchanged. The old path kept as a redirect shim (pointer table only, no definitions).

Pre-split snapshot: `$AGENT_HOME/backups/reorg-20260917/learned-rules.md` (machine-local).

Also on this date: `self-correction-regression` removed from `$AGENT_HOME/skills`, absorbed into `self-correction-coding-discipline`. Registry entry `core-self-correction-regression` retained with `status: replaced`, `replaced_by: core-self-correction`.

## 2026-09-18 — architecture validation

Fresh-session validation of the split. Verified: all seven rule files loaded in-session (bodies inlined via the `AGENTS.md` imports, disk content re-read and matched), 28 rule IDs, zero duplicates, all ten families present, legacy skills still discoverable, redirect shim intact.

Result: PASS.

## 2026-09-18 — pilot skill migration: `strict-review` → `review-code`

First rename into the domain naming convention. Identity migration only, not a redesign.

Changed:

- created `skills/review-code/SKILL.md` from the legacy file
- `name: strict-review` → `name: review-code`; H1 `# Strict review` → `# Review code`
- appended `## Governing global rules` listing `TEST-001` and `REVIEW-002`, closing the registry↔skill traceability gap (IDs only, no rule text copied)
- `AGENTS.md` routing row and the two `intent-first-review` references updated to the new name
- registry entry annotated: `legacy_name` is now provenance, not a live path
- legacy directory removed after the backup was hash-verified

Unchanged: the `description:` line byte-for-byte, so trigger phrases are identical; all six review steps, the severity table, report format, verdict rules, and the Never list. `diff -u` old→new was three hunks: name, title, traceability section.

Backup: `$AGENT_HOME/backups/reorg-20260917/pilot-review-code/` (machine-local).

Result: PARTIAL — filesystem, references, registry and behavior all verified; `review-code` confirmed discoverable in-session. The negative half (that `strict-review` no longer resolves) needs a fresh session to confirm.

Not yet migrated: the remaining eight skills still carry legacy directory names.

## 2026-09-18 — configuration put under version control

Mirrored `rules/`, `skills/`, `skill-registry/`, the entrypoint, `learned-rules.md`, and `commands/` into this repository. Copy verified by `sha256sum`. Added README, `.gitignore`, architecture notes, and the install/sync/validate scripts.

No live configuration was moved or modified by this step.

## 2026-09-18 — vendor-neutral rewrite

Removed product-specific and developer-specific identity from the tracked content so the architecture is reusable across coding agents.

- entrypoint renamed to `AGENTS.md`; its imports now use the `{{AGENT_HOME}}` token
- every absolute config path replaced: installed files carry `{{AGENT_HOME}}`, repo-only docs describe `$AGENT_HOME`
- the product-specific home variable was replaced by `AGENT_HOME`; the default target is the neutral `~/.agent`
- `install.sh` renders `{{AGENT_HOME}}` to the real path; `sync-from-local.sh` folds it back, so syncing cannot reintroduce a machine path. Dry-run comparison renders before diffing, so it stays accurate
- product names in prose replaced with "the agent runtime" / "your coding agent"; the agent's own name in skill text replaced with "the agent"
- absolute developer paths (`$VAULT_ROOT`, agent settings file) parameterized
- customer and product names in examples replaced with `<customer>` / `<an-existing-slug>` placeholders
- vendor skill notes generalized from one model's name to "coding agents"
- `validate.sh` gained check 8: portability — fails on any hardcoded home directory, drive letter, or vendor config directory, and on installed files using `$AGENT_HOME` instead of the token

Unchanged: all rule IDs and rule text, skill logic and constraints, registry structure, and checks 1–7.

Two literal env var names (`CLAUDECODE`, `CLAUDE_CODE`) remain in the WorkOS vendor skill. They are strings that a third-party CLI inspects, listed alongside `CURSOR_AGENT` and `CODEX_SANDBOX`; renaming them would make the documentation factually wrong.

## 2026-09-19 — installer safety, entrypoint routing, Claude Code adapter

Repair pass before the first real install. Audit of `ed0c6e2` listed six defects; all six were
reproduced at that commit, and one was corrected in the process.

Installer and sync (`scripts/install.sh`, `scripts/sync-from-local.sh`):

- dry run no longer creates directories — the one unguarded `mkdir -p` now sits under `--apply`
- destination paths are no longer word-split: `PAIRS` holds destinations relative to `$AGENT_HOME`,
  so spaces install correctly; `&`, `|` and `\` are escaped in the sed *replacement*
- reverse sync no longer treats `$AGENT_HOME` as a regex — it is escaped as a BRE, so `.claude`
  stops matching `Xclaude`
- writes are atomic (render to a temp file, then move) and failures are counted; both scripts now
  exit non-zero instead of printing "Applied." over a half-written tree
- the backup is a precondition: it aborts on failure, covers `CLAUDE.md`/`settings.json`/`hooks/`,
  and is verified against the source before the first write
- `LC_ALL=C`, plus verbatim passthrough for files sed would treat as binary, so a non-UTF-8 file
  can never be silently truncated to zero bytes
- reverse sync refuses a source directory that is its own git checkout rather than ingesting its
  object database into this repo

Validation (`scripts/validate.sh`):

- section 7 fails on an entrypoint with no imports, and on a `rules/*.md` that nothing imports
- new section 9 parses `registry/registry.yaml` and every `SKILL.md` frontmatter with a real
  YAML parser
- the `$AGENT_HOME` check is scoped to files that are actually installed, so repo-only docs may
  name the variable

Configuration:

- `registry/registry.yaml` `conventions.skill_path` is a folded block scalar. It was invalid YAML:
  a plain scalar cannot open with `{`. Quoting would have broken on a Windows path (`\U` escape) or
  an apostrophe; `>-` survives every rendered form.
- the routing table moved out of `config/AGENTS.md` into `rules/70-routing.md`, imported back by
  the entrypoint. Claude Code does not read a user-scope `AGENTS.md`, so routing was unreachable
  there; as a rule file it loads on both runtimes from one source.
- new `config/claude/` + `scripts/adapters/claude.sh`: a marker-delimited managed block in
  `$AGENT_HOME/CLAUDE.md`, idempotent and exactly reversible, adding no rule imports because
  Claude Code already auto-loads `rules/`.

Unchanged: every rule ID and rule body, all skill logic and skill names, the registry structure,
and checks 1–6.

Result: `validate.sh` PASS. Verified in a sandbox — dry run writes nothing, `--apply` is
idempotent, install→sync round trip is byte-identical, and all four hostile destination shapes
(space, `&`, `|`, apostrophe) install cleanly.

## 2026-09-21 — removal path, Codex adapter, role-to-model routing

Second pass over the same layer, on top of `7dbd205`. Nothing from the previous entry was
reverted; the installer's guarantees were re-verified in a sandbox before anything changed.

Runtime measurement first. A probe configuration directory with a unique canary in each candidate
location, `CLAUDE_CONFIG_DIR` pointed at it, and a non-interactive session asked which canaries it
could see. This confirmed, on Claude Code 2.1.220 (Windows), the four claims the previous pass had
measured on 2.1.278 (macOS): `rules/*.md` auto-load without imports, a user-scope `AGENTS.md` is
inert, skills are found one level deep only, and a linked skill directory is followed. It also
established two new facts: agent definitions in `$AGENT_HOME/agents/*.md` are discovered, and their
`model:` frontmatter is honoured — the sub-agent transcript records `claude-haiku-4-5-20251001`
under a `claude-sonnet-5` parent. Full matrix with evidence: `docs/runtime-capabilities.md`.

Three defects found by that measurement, all Windows-only and all in the link path:

- `ln -s` on a host without symlink privilege exits 0 and silently deep-copies the directory. The
  copy was then recorded as a managed link, `--check` called it broken, and `--unlink-skills`
  refused to remove it — a duplicated, drifting skills tree that nothing could clean up.
  `as_link_support` now probes the mechanism (symlink → junction → none) and the adapters refuse
  to link rather than fall back to copying.
- link identity compared raw `readlink` output against the recorded target. MSYS resolves one
  directory to two spellings, so a healthy link reported as broken. Comparison now goes through
  `as_canon_path`.
- `--unlink-skills` deleted its manifest even when it had skipped links, orphaning them.

Removal (`scripts/uninstall.sh`, new): ownership comes from
`$AGENT_HOME/.agent-skills/manifest.tsv`, written by the installer with a hash per file. A path
absent from the manifest was not installed and is never touched; a path whose hash no longer
matches was edited by the user and is kept and reported unless `--force`. `--stale` removes only
what the repo has stopped shipping. Everything removed is backed up and hash-verified first.

The installer also gained a dependency preflight ahead of the first write, and reports files it
installed previously that the repo no longer ships.

Codex adapter (`scripts/adapters/codex.sh`, new). The Codex CLI is not installed here, so its
behaviour is documented, not measured, and the file says so. Two documented facts shaped it: Codex
expands no imports in `AGENTS.md`, so the shared entrypoint's `@.../rules/...` lines would arrive
as literal text and the rules would never load — the adapter materialises the rule bodies into its
managed block instead; and the instruction chain is capped at `project_doc_max_bytes` (32 KiB), so
the adapter measures what it is about to write and refuses rather than letting Codex truncate
mid-rule. `config.toml` is never written automatically — appending to TOML is unsafe in general —
`--print-config` prints a snippet instead.

Routing (`config/routing/`, `scripts/routing/render.py`, new, optional). Maps opaque role ids onto
model tiers and renders one agent definition per role per runtime. Model selection, reasoning and
fallback policy are three separate sections. It never authors role instructions: a role must point
at a profile file, and a missing profile or description is a schema error. `roles: []` — the
current state — renders nothing, which is correct until canonical role profiles exist.

Tests (`tests/`, new): 129 assertions across four files, dependency-free bash, covering dry-run
inertness by whole-tree fingerprint, user content preserved byte-for-byte, removal boundaries,
idempotency, path-with-spaces, link collisions, the Codex instruction budget, and routing schema
and ownership. CI runs validation, the suite on Linux and Windows, and shellcheck.

`validate.sh` gained section 10 (the routing example must still satisfy the renderer's schema), and
section 8 was split: machine paths are forbidden repo-wide, while the vendor-neutrality rule now
applies to installed content only — an adapter naming its own runtime's directory is its purpose,
not a leak.

Unchanged: every rule ID and rule body, all skill logic and skill names, the registry structure,
`config/AGENTS.md`, and checks 1–7.
