---
name: ticket-pr
description: Use when writing or rewriting a ticket report, PR description, QA question, bug/research report, feedback card, estimation, or version/security-upgrade report — for Jira, Linear, or GitHub. Triggers on "viết ticket", "làm ticket", "báo cáo ticket", "mô tả PR", "PR description", "viết QA", "ticket review", "estimation", "sửa lại description PR", or any request to produce content that gets pasted into a tracker or PR body.
---

# Ticket & PR writing

Output goes straight into Jira / Linear / GitHub. A human reviewer reads it cold. Write for that reader.

## Step 1 — Pick the template, then READ it

Templates live in `$VAULT_ROOT/_common/templates/`.

| Work type | Template | `kind:` |
|---|---|---|
| Task report | `ticket-task.md` | TASK |
| Review a PR | `ticket-review.md` | REVIEW |
| Question for QA / BrSE | `ticket-qa.md` | QA |
| Customer / user feedback | `ticket-fb.md` | FB |
| Bug or research report | `ticket-bug.md` | BUG |
| Version upgrade / security patch | `report-upgrade-version.md` | TASK |
| Estimation | `ticket-estimation.md` | ESTIMATION |
| GitHub PR body | `pr-description.md` | PR |

**Read the template file before writing.** Never reproduce its structure from memory — headings drift.

Also read `$VAULT_ROOT/_common/operations/ticket-pr-format.md` for the binding rules; it wins over this file on conflict.

## Step 2 — Where the file goes

Ticket/PR cards live in `$VAULT_ROOT/<project>/work/active/<ID>[-SUFFIX].md`, never in a scratchpad and never inside the repo (some projects forbid AI traces in the repo — check the project vault).

Suffix convention: `CPP-405.md` (ticket) · `-QA` · `-REVIEW` · `-PR` · `-test-checklist` · `-FB`.

Frontmatter: `title`, `created`, `updated`, `tags`, `status`, `kind`, tracker id, `related`.

## Step 3 — Writing rules

**Nothing outside the template's sections.** No nav footer (`<!-- NAV:AUTO -->`, "Ngược lên:"), no breadcrumb, no vault navigation links, no meta commentary. The card is pasted verbatim into a tracker — every extra line is garbage in front of the reviewer.

**No internal shorthand.** Screen codes (`S-D`), feature codes (`F-15`), and internal abbreviations mean nothing to a reviewer. Write the screen name plus its URL: "màn xác nhận đặt lịch (`予約内容の確認`, `/pet/service/trimming/booking/confirm/`)". Codes are allowed only as a parenthetical after the real name, or when quoting a spec section.

**State behaviour, not vocabulary.** "Sửa cách màn X xử lý…" says nothing. Use a Before → After table, or concrete verbs: "404 page → error screen".

**Objective is mandatory.** Every card says what must be true when this is done. A reviewer who reads only the first section must know what is being changed and why.

**No filler.** Cut: restating the same fact in two sections, commit hashes and line counts in a scope section (the diff shows them), long rationale where one clause works, sections the template marks optional and you have nothing for. Delete unused optional sections rather than filling them with "N/A".

**Facts only.** Every claim traceable to `file:line`, a commit, a spec section, or a command that was actually run. Never write "tested OK" for something not run. Anything unverifiable: say "chưa xác nhận" plus why — do not guess.

**Intent before wording.** When the source material is a task, spec, or instruction written informally — shorthand, mixed VN/EN, awkward grammar — read it for intent and normalize it naturally in the card. Do not turn phrasing imperfections into REVIEW findings, and do not raise a QA question about wording that context already resolves. Ask only when two or more readings would materially change what gets built or how it is accepted. See `intent-first-review`.

**Language.** Vault cards: Vietnamese prose, technical terms and code in English/Japanese as they appear in the product. GitHub PR bodies: match the repo's existing PR language (read the last 2-3 PR bodies with `gh pr list --limit 3 --json body`).

## Step 4 — Before handing it over

- [ ] Every mandatory section of the template filled
- [ ] Nothing present that is not in the template
- [ ] A reviewer who has never seen the ticket understands what changed, from the card alone
- [ ] No internal codes without their real names
- [ ] Nothing claimed that was not verified

## Step 5 — Publishing

Writing the card is not publishing it. `gh pr edit`, posting to Jira, or commenting on a PR is an outward-facing action — show the draft and wait for explicit approval first.
