# Runtime capability matrix

What each supported runtime actually does with this configuration, and how that
was established. Every row is either **measured** on a named version, or
**documented** — read from the vendor's documentation and not yet observed here.
The two are never merged: a documented row is a design input, not evidence.

Nothing in this file is inferred from the other runtime. A passing Claude Code
result says nothing about Codex.

## Measurement environment

| | |
| --- | --- |
| Host | Windows 11 Home Single Language 10.0.26200, Git Bash (GNU bash 5.2.37, MSYS) |
| Claude Code | **2.1.220** |
| Codex CLI | **not installed** — every Codex row below is documented, not measured |
| Repository | branch `feat/runtime-adapters-routing`, based on `fix/safe-install-and-claude-adapter` |
| Date | 2026-09-21 |

### Method

A probe configuration directory was built containing a unique canary token in
each candidate location, and `CLAUDE_CONFIG_DIR` was pointed at it. A
non-interactive session (`claude -p`) was then asked to report, from its own
system context only, which tokens were present. A token reported PRESENT is
proof the runtime loaded that file; ABSENT is proof it did not.

Model routing was read from the session transcripts the runtime writes under
`$CLAUDE_CONFIG_DIR/projects/**.jsonl`, which record the `model` field per
session and per sub-agent — an observation of what ran, not of what was asked
for.

## Claude Code — measured on 2.1.220

| Capability | Result | Evidence |
| --- | --- | --- |
| `$AGENT_HOME/CLAUDE.md` loads at user scope | yes | canary present |
| `$AGENT_HOME/rules/*.md` load **without any import line** | yes | canary present; the probe `CLAUDE.md` contained no imports |
| `$AGENT_HOME/AGENTS.md` loads at user scope | **no** | canary absent |
| `$AGENT_HOME/learned-rules.md` loads when nothing imports it | no | canary absent |
| Skills discovered at `skills/<name>/SKILL.md` | yes | canary present |
| Skills discovered deeper (`skills/a/skills/b/SKILL.md`) | **no** | canary absent |
| Skill discovered through a linked directory | yes | canary present through a Windows junction |
| Agent definitions at `$AGENT_HOME/agents/*.md` | yes | agent appeared in the session's agent-type list |
| Per-agent `model:` in frontmatter is honoured | **yes** | sub-agent transcript `claude-haiku-4-5-20251001`, parent `claude-sonnet-5` |
| Per-agent `tools:` restriction is honoured | yes | restricted child listed only `Read` |
| Per-agent reasoning setting | **no documented key** | not emitted by the renderer; see Gaps |
| Child agent inherits user rules and `CLAUDE.md` | yes | both canaries present inside the child |
| Child agent can use skills | **only when the `Skill` tool is in its tool set** | child restricted to `tools: Read` saw no skills; unrestricted child saw them and reported having a `Skill` tool |
| Child agent sees its own `description` | no | the description is parent-visible for selection; the child receives the body as its instructions |
| Results collected from a child | yes | parent relayed the child's reply |

### Consequences for the adapter

1. Rules need no import lines on Claude Code. Adding them would load every rule
   twice, so the managed block deliberately contains none, and `--check` fails
   if any appear.
2. A user-scope `AGENTS.md` is inert here. Anything that lives only in that file
   is invisible to Claude Code. Conversely, everything in `rules/` loads whether
   or not the canonical model mentions it — which is why `rules/` is kept equal
   to the catalog's `rule_refs` and nothing else is allowed to live there.
3. Restricting a sub-agent's tools silently removes its access to skills. A role
   that needs skills must not be given a `tools:` list that omits `Skill`.

## Contract integration — measured on Claude Code 2.1.220

Two arms of one controlled experiment, same canonical role (`review`), same tool
restriction (`Read, Grep, Glob, Bash`), differing only in how its `skill_refs`
were delivered. The canary is a sentence that appears only in
`skills/review-code/SKILL.md`.

| Arm | Skill delivery | Child has `Skill` tool | Child has the skill text |
| --- | --- | --- | --- |
| A | `preload` (renderer inlines the canonical bodies) | no | **yes** — quoted verbatim |
| B | `reference` (child told to load it itself) | no | **no** — reported `NOT-PRESENT` |

Arm B is the control, and it is the point: under a tool restriction, referencing
a skill delivers nothing at all, because the restriction removed the tool that
would load it. Preloading delivers the required instructions **without widening
the permission** — the alternative the contract forbids.

Model selection was read from the session transcripts in the same runs: the
rendered role carried `model: sonnet` and its sub-agent ran `claude-sonnet-5`
while the parent ran `claude-haiku-4-5-20251001`. Per-role model binding from
adapter-owned routing configuration therefore reaches the runtime.

| Contract capability | Claude Code 2.1.220 | Evidence |
| --- | --- | --- |
| `spawn` | yes | sub-agent created and its result collected |
| `model-selection` | yes | transcript model differs from the parent's, as bound |
| `tool-isolation` | **enforced** | a restricted child emitted a real `tool_use` for an excluded tool and the runtime answered `is_error=true`; an identical child *with* that tool succeeded in the same session |
| `fresh-context` | **not measured** | no probe distinguishes a fresh context from an inherited one |
| `workspace-isolation` | not measured | no separate writable workspace was requested |

### Tool isolation — how it was proven

An earlier pass recorded this capability as *requested but not enforced*,
because a child reporting a short tool list proves only that the child says so.
The probe below replaced that report with an observation, and the verdict
changed on the evidence.

```
restricted-probe (tools: Read)        TOOL_USE 'Bash' -> TOOL_RESULT is_error=True
                                      "No such tool available: Bash"
allowed-probe    (tools: Read, Bash)  TOOL_USE 'Bash' -> TOOL_RESULT is_error=False
                                      "ISOLATION-PROBE"
```

Three things together make this enforcement rather than compliance: the child
*attempted* the call (a `tool_use` block exists in the transcript), the runtime
*refused* it (`is_error=true`), and an otherwise identical child with that tool
in its list *succeeded in the same session*. The control arm is what rules out
the alternative explanation — the first arm's error text also mentions a
session-level restriction, and without the control that would be the simpler
reading.

Reproduce with `bash tests/probes/tool-isolation.sh`. It is not part of
`tests/run.sh`: it needs credentials, network and billable usage. Its output
carries the runtime version it was measured on.

Not established by this probe: that any *other* capability is enforced.
`fresh-context` and `workspace-isolation` have no probe yet.

## Windows link support — measured

| Mechanism | Result |
| --- | --- |
| POSIX symlink (`ln -s`) | **fails silently**: exits 0 and produces a deep copy, not a link |
| `MSYS=winsymlinks:nativestrict ln -s` | fails loudly: `Operation not permitted` (no Developer Mode / `SeCreateSymbolicLinkPrivilege`) |
| Directory junction (`cmd /c mklink /J`) | works without elevation; MSYS reports it as a symlink; `rm -f` removes the junction and leaves the target intact |

This is why `scripts/lib/common.sh:as_link_support` probes rather than assumes,
and why the adapters refuse to link when neither mechanism works instead of
leaving copies behind. A silent copy is worse than no link: it is recorded as a
managed link, never cleaned up, and drifts from its source.

Path identity is compared through `as_canon_path`, not `readlink` output: MSYS
resolves the same directory to `/tmp/...` through a junction and to
`/c/<user>/...` directly, so raw string comparison reports a healthy link as
broken.

## Codex — documented, NOT measured

The Codex CLI is not installed on the measurement host. Every row below comes
from the vendor documentation and must be re-verified on a machine that has it
before any of it is treated as fact.

| Aspect | Documented value |
| --- | --- |
| User config | `~/.codex/config.toml` (TOML); project `.codex/config.toml` |
| Global instructions | `~/.codex/AGENTS.override.md`, else `~/.codex/AGENTS.md`, then the project chain from repo root down |
| Instruction budget | `project_doc_max_bytes`, **32 KiB default**, combined across the chain |
| Import/include in AGENTS.md | none documented — text is concatenated, not expanded |
| Skills, user scope | `$HOME/.agents/skills/<name>/SKILL.md` (**not** under `~/.codex`) |
| Skills, repo scope | `.agents/skills`, scanned from cwd up to the repository root |
| Skill frontmatter | `name` and `description` required |
| Custom prompts | `~/.codex/prompts/*.md`, top level only; deprecated in favour of skills |
| Model selection | `model`, `model_provider`, `[model_providers.<id>]` |
| Reasoning | `model_reasoning_effort` = `low` \| `medium` \| `high` \| `xhigh` |
| Profiles | `~/.codex/<name>.config.toml`, selected with `codex --profile <name>` |
| Sub-agents, global | `[agents]`: `enabled`, `max_concurrent_threads_per_session`, `default_subagent_model`, `default_subagent_reasoning_effort` |
| Sub-agent definitions | `~/.codex/agents/*.toml` (personal), `.codex/agents/*.toml` (project) |
| Sub-agent fields | required `name`, `description`, `developer_instructions`; optional `model`, `model_reasoning_effort`, `sandbox_mode`, `mcp_servers`, `skills.config` |
| Context to a sub-agent | documented as inherited from the parent, resolved explicit → `[agents]` defaults → parent |

Sources: the Codex configuration, AGENTS.md, subagents and build-skills pages of
the official documentation, retrieved 2026-09-21.

### Consequences for the Codex adapter

1. **The shared `config/AGENTS.md` cannot carry the rules to Codex.** Its
   `@{{AGENT_HOME}}/rules/...` lines are import syntax; with no documented
   expansion they arrive as literal text and the rules never load. The adapter
   therefore materialises the rule bodies into the managed block.
2. **Skills do not live under the Codex config directory.** They are linked into
   `$HOME/.agents/skills`, so `CODEX_SKILLS_DIR` defaults there.
3. **The 32 KiB budget is shared with project instructions.** The adapter
   measures the file it is about to write and refuses to exceed the budget
   rather than letting Codex truncate mid-rule. Current rule payload: ~9.2 KiB.
4. **`config.toml` is never written automatically.** Appending to TOML is not
   safe in general — a bare key appended after a table header silently joins
   that table, and a duplicate `[agents]` header is a parse error. The adapter
   prints a snippet with `--print-config` instead.

## Configured limits are not measured limits

Every instruction limit this repository acts on is a **configured** value read
from documentation or set by an operator. None has been measured against a
running instance.

| Limit | Status | Basis |
| --- | --- | --- |
| Codex `project_doc_max_bytes` = 32 KiB | configured, **not measured** | vendor documentation; the CLI is not installed here |
| Renderer `--budget` (32 KiB default for Codex) | configured | mirrors the value above so a rendered file cannot silently exceed it |
| Claude Code per-agent instruction limit | **unknown** | no documented value, and none probed. The renderer therefore enforces no limit there — absence of a documented limit is not evidence that none exists |

Measuring an effective limit means growing an instruction file until the runtime
demonstrably drops content, and observing where. That test has not been run on
either runtime. Until it is, a file that fits the configured budget is only
known to fit the configured budget.

## Gaps and explicit fallbacks

| Gap | Fallback in force |
| --- | --- |
| No per-agent reasoning key documented for Claude Code | The renderer emits no reasoning key for the Claude runtime; the routing file's `reasoning` value is used for Codex only. Recorded rather than guessed. |
| Host cannot create directory links | `--link-skills` fails with a non-zero exit and prints the supported alternative: install skills directly into the runtime's own skills path (`unset AGENT_SKILLS_DIR`). |
| Codex runtime unavailable for testing | Everything in the Codex section is marked documented. `tests/test_adapter_codex.sh` asserts only what the adapter writes, never that Codex reads it. |
| A role asks for a tier with no model for the target runtime | `fallback.on_unknown_model: deny` (default) makes it a schema error. Substituting a different model silently is never done. |
| Instruction budget exceeded | Write refused, with the exact byte count and the `project_doc_max_bytes` value to raise. |

## What is still unverified

- Every Codex row above, on every axis: loading, budget enforcement, skills
  discovery, sub-agent spawning, and whether a rendered `~/.codex/agents/*.toml`
  is picked up at all.
- Whether Claude Code's rule auto-discovery extends to nested directories under
  `rules/`. Only the flat case was probed.
- Behaviour on macOS and Linux hosts. All measurements here are Windows.
