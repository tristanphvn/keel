---
name: help
description: Guides users through keel setup, the lead, and picking the skill, playbook, principle, agent, or hook for a task. Use for /keel:help, or when the user asks how to install, set up, or use keel, or which keel skill fits. Not for requests to do work, even ones that name keel.
---

# keel help

Answer the user's question about keel, hand them a prompt they can send, and link the file the answer came from. For a help question, don't start the work. The user asked how, and a keel run spends real tokens, so let them send the prompt.

A message that asks for work, such as "use keel to fix this bug", is not a help question. Read [`lead`](../lead/SKILL.md) and do the work under it.

This file maps questions to the skills and guide pages that hold the answers. Those files own the details. Read the file you route to before you quote it, and trust it when it disagrees with this map. The links here point into the installed plugin, which the user may not be able to open, so give the user the file's public copy: `https://github.com/tristanphvn/keel/blob/main/` followed by its path.

## Find out what they need

Infer the need from the message and the conversation. A named situation, such as "which skill reviews a PR?", goes straight to its section. If the need is still unclear, ask one `AskUserQuestion` with these four options, then answer only the section they pick. Its built-in Other choice covers Make keel my own.

- Get set up
- Start a task with the lead
- Pick a skill for a situation
- Fix a run that went wrong

Check the state that changes the answer, and mention it only when it does:

- No `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/keel-models.md` means `/keel:setup` hasn't run for this profile, so every role uses its default model.
- No `verify-*` skill or other app harness in the project means agents have no scripted way to drive the app. Mention `/keel:create-verification-skill` when the question is about proving a change works.

## Get set up

1. Install with `claude plugin marketplace add tristanphvn/keel`, then `claude plugin install keel@keel`. To try keel for one session, clone the repository and run `claude --plugin-dir ./keel`.
2. Run [`/keel:setup`](../setup/SKILL.md). It checks for the Codex CLI, maps a model alias to each role, and writes `keel-models.md` in the active Claude config directory. keel skills read it on their next spawn, in this session and new ones.
3. Start a real task with a goal and a check that can pass or fail. The main session loads the lead on its own, or the user types `/keel:lead`.

keel needs `git`, the GitHub CLI `gh` signed in, `python3` for the hooks, and `bun` for the playbook scripts. Only `lead` and `help` load from the user's words, and `typescript-best-practices` loads when the agent touches a `.ts` or `.tsx` file. The other skills load when the user types them or when the lead reads them for a step. The [README](../../README.md) and [guide page 1](../../docs/guide/01-setup.md) have the details. Offer to word their first prompt with them.

If cost is the worry, say where the tokens go and how to spend fewer. keel spends extra tokens on subagents and review panels. Rerun `/keel:setup` and pick cheaper models, such as `sonnet` or `haiku`, for the roles that matter least. A role set to `inherit` runs on the session's model. A shorter panel list runs fewer subagents, one for each entry. Save the lead for work that needs rigor.

keel also installs in Codex, with `codex plugin marketplace add tristanphvn/keel` and `codex plugin add keel@keel`. There the user invokes `$keel:lead`, which reads the same playbooks through [its Codex adapter](../../codex/skills/lead/SKILL.md). This help skill and the other `/keel:<name>` commands are Claude Code only. The README's Codex section covers the sandbox approvals.

## Start a task with the lead

The lead matches the task to a playbook, copies the playbook's steps into the todo list, and runs the other skills as the steps need them. A step it skips stays in the list as `skip: <reason>`. A good prompt states the goal and how to tell it's done. It doesn't list skills, because a hand-written sequence tends to drop or reorder steps the playbook would keep. [Guide page 2](../../docs/guide/02-lead.md) has examples.

The lead stays on across turns. The `hooks/lead-reminder.sh` hook re-injects one line on every prompt, so a new task that needs rigor loads the lead again. The user opts out by saying so, or silences the hook with `KEEL_REMINDER=off`. Mid-chat, "new task" makes the lead match a fresh playbook.

The lead delegates code-writing to [`keel:ponytail`](../../agents/ponytail.md) builders and reviews with [`keel:critic`](../../agents/critic.md), a read-only reviewer with one lens per spawn. To get the same builder from a subagent of your own, spawn it with `subagent_type: "keel:ponytail"`.

Subagents live only as long as their session. Before closing the terminal on running work, type `/bg`. Start unattended work with `claude --bg "<brief>"`.

## Pick a skill

The default answer is the lead, which runs most of the others when its steps need them. Name a skill directly when the user wants more or less of something than the playbook gives. Read the skill before you recommend it, and give one example prompt.

| The user wants to | Skill |
|---|---|
| Do any non-trivial task with rigor | [`/keel:lead`](../lead/SKILL.md) |
| Know how code works now, or where new code should live | [`/keel:how`](../how/SKILL.md) |
| Know why code is shaped this way, or where a number came from | [`/keel:why`](../why/SKILL.md) |
| Understand a change or subsystem, explained plainly | [`/keel:teach`](../teach/SKILL.md) |
| Catch up on their own recent work on a topic | [`/keel:recall`](../recall/SKILL.md) |
| Know what a small diff could break outside itself | [`/keel:blast-radius`](../blast-radius/SKILL.md) |
| Settle types and module shape before code that crosses a function boundary | [`/keel:architect`](../architect/SKILL.md) |
| Get several attempts at one brief, merged into the best one | [`/keel:arena`](../arena/SKILL.md) |
| Run parallel checks over slices, or race workers, as subagents | [`/keel:swarm`](../swarm/SKILL.md) |
| Have several models review a diff and try to break it | [`/keel:interrogate`](../interrogate/SKILL.md) |
| Fix a bug test-first when a cheap local test exists | [`/keel:tdd`](../tdd/SKILL.md) |
| Apply TypeScript rules to `.ts` or `.tsx` work | [`/keel:typescript-best-practices`](../typescript-best-practices/SKILL.md) |
| Strip comments before review, using a reviewer that didn't write them | [`/keel:no-comments`](../no-comments/SKILL.md) |
| Clean AI tells out of prose | [`/keel:unslop`](../unslop/SKILL.md) |
| Write docs, an RFC, a README, a PR description, or a commit message to a standard | [`/keel:technical-writing`](../technical-writing/SKILL.md) |
| Hear the last reply again in plain words | [`/keel:bro`](../bro/SKILL.md) |
| Give agents a scripted way to drive the app and prove behavior | [`/keel:create-verification-skill`](../create-verification-skill/SKILL.md) |
| Bring a verification skill and its feature map back in line with the app | [`/keel:maintain-verification-skill`](../maintain-verification-skill/SKILL.md) |
| Vet a performance number before reporting or acting on it | [`/keel:benchmark-checklist`](../benchmark-checklist/SKILL.md) |
| Run a large or cross-cutting change, or one to review after stepping away | [`/keel:figure-it-out`](../figure-it-out/SKILL.md) |
| Keep a decision log during a run, and review it afterward | [`/keel:show-me-your-work`](../show-me-your-work/SKILL.md) |
| Pick a model for each role | [`/keel:setup`](../setup/SKILL.md) |
| Turn their own working habits into a personal mode skill | [`/keel:automate-me`](../automate-me/SKILL.md) |
| Turn what a finished task taught into skill edits | [`/keel:reflect`](../reflect/SKILL.md) |
| Stop agents from repeating the same mistakes in this repo | [`/keel:correct`](../correct/SKILL.md) |
| Find their way around keel | `/keel:help` |

If a skill directory next to this one is missing from the table, read its frontmatter and route by its description. The `principle-*` directories are covered under principles below.

Close calls:

- `/keel:how` explains what the code does. `/keel:why` explains the reasons. `/keel:teach` runs one or both and explains the result plainly.
- `/keel:arena` gives every worker the same brief and merges the best parts. `/keel:swarm` splits work into slices or a race and returns one report.
- `/keel:architect` implements right after it settles the design. Add "with checkpoint" to review the design before it writes code.
- `/keel:interrogate` reviews the diff. `/keel:blast-radius` looks for breakage outside the diff and proves the one fact that makes the change safe.
- `/keel:recall` rebuilds context across recent chats. Resuming one specific chat or branch is the Session pickup playbook.
- `/keel:figure-it-out` designs one rigorous run. The Orchestrate playbook runs a program that spans days and many PRs. The Autonomous run playbook drives one task to a finish condition.
- `/keel:correct` mines history for repeated mistakes and fixes each at the highest level that works. The `hooks/correct-reminder.py` hook runs its one-correction path on its own whenever a prompt reads as a correction, in English or Vietnamese. `KEEL_CORRECT=off` silences it.

Not in keel:

- `/simplify`, `/loop`, `/bg`, and plan mode are Claude Code built-ins. The lead runs `/simplify` before each commit.
- Browser and desktop driving comes from the `anthropic-skills` browser and computer-use skills when available, else Playwright through Bash. `anthropic-skills:skill-creator` writes skills when available.
- keel has no `/keel:orchestrate` skill. Orchestrate is a lead playbook. If the slash menu shows `/orchestrate`, another plugin provides it.

## Playbooks and principles

Playbooks are step lists inside the lead, not skills, so they have no slash command. Describing the task picks one, and these phrases name one directly:

- "babysit this pr" or "check on pr 123" runs Babysit. It drives the PR to merge-ready and stops there. It doesn't merge unless the user asks to merge, land, or ship.
- "land the stack" runs Shipping.
- "take over this branch" runs Session pickup.
- "pause safely" runs Pause safely.
- "full autopilot on this queue" runs Autopilot-full. "stack them, don't ship" runs Autopilot-stack.
- "run the eval playbook" runs Eval.

The Playbooks section of [`lead`](../lead/SKILL.md) lists every playbook and when it applies. [Guide page 6](../../docs/guide/06-verify-and-ship.md) covers opening, babysitting, and landing a PR.

keel has no planning skill. Claude Code's plan mode works alongside it. For work that spans phases or stacked PRs, asking the lead for a plan runs the [Multi-phase plan playbook](../lead/playbooks/multi-phase-plan.md), which writes the plan and doesn't implement it. For a design question, the Prototype playbook or `/keel:architect` settles it in code first.

Principles are one-rule skills that the lead reads and cites in its replies. The user rarely invokes one. They steer with the names instead, as in "apply prove it works. show me the real output." Typing `/keel:principle-<name>` still loads one on demand. [Guide page 8](../../docs/guide/08-principles.md) lists them.

## Fix a run that went wrong

| Symptom | Fix |
|---|---|
| The lead stopped applying after a few turns | Check that `KEEL_REMINDER` is not `off`, or type `/keel:lead` at the start of each task. |
| A question got treated as the next step of the last task | Say "new task", or say the turn doesn't need the lead. |
| A new model choice had no effect | Check that `/keel:setup` wrote `keel-models.md` under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` for the profile in use. Subagents already running keep their model. |
| Runs cost more than expected | See the cost paragraph under Get set up. |
| A skill didn't load on its own | Only `lead` and `help` load from the user's words, and `typescript-best-practices` loads on `.ts` and `.tsx` files. The others load when the user types them or when the lead reads them, and it doesn't run every skill. |
| Parallel agents overwrote each other | Give each agent its own worktree with `isolation: "worktree"`, or a separate `claude --worktree` session. |
| Subagents stopped mid-task | Closing the terminal stops them. Type `/bg` first next time. To recover, follow the Session pickup playbook against their worktrees. |
| The git guard blocked a command | It blocks force-pushes, `reset --hard`, `clean -f`, and whole-tree discards on purpose. An owner publishes its own rebased branch with `git push --force-with-lease origin <branch>`. See [`hooks/git-guard.py`](../../hooks/git-guard.py). |
| The correct reminder fired on a prompt that wasn't a correction | Its patterns live in one table at the top of [`hooks/correct-reminder.py`](../../hooks/correct-reminder.py). Set `KEEL_CORRECT=off` to silence it. |
| Every turn now takes an extra review pass | That's [`hooks/think.py`](../../hooks/think.py): it injects a dig protocol on each prompt and blocks the first stop of each turn for a review. Set `KEEL_THINK=off` to turn it off. |
| An overnight run moved but finished nothing | `/loop` needs a check that can pass or fail, not a duration. See [guide page 7](../../docs/guide/07-overnight.md). |
| The reply claims success from a green build | Ask for the real command, flow, stored value, or profile. That's the prove-it-works principle. |

[Guide page 10](../../docs/guide/10-recipes-and-pitfalls.md) has more pitfalls and the recipes worth copying.

## Make keel my own

- [`/keel:automate-me`](../automate-me/SKILL.md) drafts a personal mode skill from the user's own history, to use alongside the lead.
- [`/keel:reflect`](../reflect/SKILL.md) after a session turns its lessons into skill edits the user approves.
- `/keel:lead write a skill for <workflow>` runs the authoring playbook. The eval playbook tests a skill change blind.
- Fix a misbehaving skill in its own PR, not inside the feature work where it went wrong.

[Guide page 9](../../docs/guide/09-make-it-yours.md) covers each of these.

## Reply

Lead with the answer. Give at most one example prompt in a code block, then the link to that file. Keep it short unless the user asked for the whole map.
