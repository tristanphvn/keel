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
2. **Anything that lived only inside `AGENTS.md` is lost on Claude Code.** That is why the
   routing table moved out of `config/AGENTS.md` into the shared `rules/70-routing.md`:
   Claude Code picks it up from the rules directory, and `AGENTS.md` imports it for
   everyone else. One source, no duplication.

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

The adapter only ever touches `$AGENT_HOME/CLAUDE.md`, and only between its
`<!-- agent-skills:begin -->` / `<!-- agent-skills:end -->` markers. Everything the user
wrote in that file is preserved; re-running is idempotent.
