# Claude Code adapter

The shared configuration in `rules/`, `skills/`, `registry/` and `config/AGENTS.md` is
vendor-neutral. This directory holds the part that is specific to Claude Code, so the
shared tree never grows a vendor assumption.

## What Claude Code actually loads from `$AGENT_HOME`

Measured on Claude Code 2.1.278 (macOS) by capturing the real request body with a local
mock API endpoint and `CLAUDE_CONFIG_DIR` pointed at a probe directory:

| Path | Loaded at user scope? |
| --- | --- |
| `CLAUDE.md` | yes |
| `rules/*.md` | **yes — auto-discovered, no import needed** |
| `AGENTS.md` | **no** — AGENTS.md is a project-scope feature; a user-scope copy is inert, with or without a sibling `CLAUDE.md` |
| `learned-rules.md` | no — only reachable through an `AGENTS.md` import |
| `skills/<name>/SKILL.md` | discovered, one level deep only (`skills/a/skills/b/SKILL.md` is **not** found) |

Two consequences shape this adapter:

1. **Rules need no imports here.** They already load from `rules/`. Adding
   `@{{AGENT_HOME}}/rules/...` to `CLAUDE.md` would load every rule twice.
2. **Anything that lived only inside `AGENTS.md` is lost on Claude Code.** An earlier
   pass moved a skill-routing table into `rules/70-routing.md` for that reason. It has
   since been removed: role `skill_refs` are the canonical selection mechanism, and a
   rule file that the canonical model never declared would load here regardless —
   see `docs/decisions/0001-contract-c1-c5.md`. `rules/` now matches the catalog's
   `rule_refs` exactly.

`learned-rules.md` is deliberately left unreachable on Claude Code. It is a redirect shim
whose entire content points at `rules/`, which Claude Code already loads — carrying it into
every session would cost tokens to say something the runtime has already done.

## Usage

```bash
export AGENT_HOME=~/.claude
bash scripts/adapters/claude.sh            # preview
bash scripts/adapters/claude.sh --apply    # writes, after backing up CLAUDE.md
bash scripts/adapters/claude.sh --check    # verify an existing install
bash scripts/adapters/claude.sh --remove   # take the managed block back out
```

```bash
bash scripts/adapters/claude.sh --link-skills --apply     # only when AGENT_SKILLS_DIR is set
bash scripts/adapters/claude.sh --unlink-skills --apply
```

The adapter only ever touches `$AGENT_HOME/CLAUDE.md`, and only between its
`<!-- agent-skills:begin -->` / `<!-- agent-skills:end -->` markers. Everything the user
wrote in that file is preserved; re-running is idempotent. Claude Code strips HTML comments
when it loads the file, so the markers cost the model nothing.

## Symlinked skills

Measured the same way: Claude Code **does** discover a skill whose directory under
`$AGENT_HOME/skills/` is a symlink, and reads its `references/` through the link. That makes
`AGENT_SKILLS_DIR` + `--link-skills` a safe way to keep the skills tree out of a config
directory that already belongs to something else.
