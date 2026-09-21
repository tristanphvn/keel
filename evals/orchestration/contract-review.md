# Contract review

Verdict: REQUEST CHANGES for the path representation issue below; otherwise suitable as a clearly marked draft for adapter feedback, not runtime approval.

Scope: read-only review of the working-tree additions and registry diff against ed0c6e2120d24481e7bab34c80cb66af89545995. Inspected contract schema/docs/examples, all 14 role profiles and catalog, nine new skill bodies, referenced existing review/intent/adversarial/coding/UI skill bodies, behavioral scenarios and integration handoff. No repository files were modified. No technical tests or validators were implemented or run.

## Actionable finding

**P2 — Valid workspace paths containing spaces cannot be authorized or reported.** `contracts/agent-work.schema.json:229` and `:579` use a path pattern ending in `[^\\s]+$` for `scope.write_paths` and `changed_files[].path`. Consequently an otherwise ordinary task editing `docs/Release Notes.md` or a directory such as `client assets/` cannot represent its exact write scope or changed file in a valid envelope. `contracts/README.md:82` describes workspace-relative files and directory prefixes without imposing this filename restriction. A broader parent scope would unnecessarily increase authority and still cannot represent the changed file. Permit ordinary spaces in literal path fields while retaining traversal/absolute-path/realpath containment checks; specify any actual platform restrictions explicitly. This is established by source inspection of the regex, not a validator run.

## Concrete inherited integration issue (not a newly introduced legacy-skill defect)

The new critical-thinking and security profiles load `skills/adversarial-consensus/SKILL.md`. That existing skill's lines 126–129 classify specific agent *type names* as cold-start versus inherited and lines 138–139 label same-session reasoning as “Independent Pass.” The new contract at `contracts/README.md:61–67` instead requires observed capabilities and an actual separate fresh execution, and `skills/core-orchestrate/SKILL.md:15,22` forbids labeling sequential passes independent. The handoff already acknowledges inherited runtime wording, so this should not be presented as an undisclosed implementation claim or silently fixed in the legacy body. Before runtime acceptance, explicitly resolve precedence in adapter loading and verify B06/B10 against actual context behavior. Agent labels alone are insufficient evidence. The concrete overlap deserves an explicit compatibility-table entry.

## Checks and conclusions

- The 14 catalog role references correspond to the reviewed profiles. Their skill references use canonical flat repository paths; no new hardcoded role-ID enum prevents adding a role. The nine new registry records match the new skill bodies, and the prior planned security record is promoted rather than duplicated.
- The shared seven rule files and existing skill bodies are unchanged in the inspected git diff. Registry edits are additions plus deletion of the promoted planned entry. No installer or routing implementation appears in the reviewed change.
- Permissions are ceilings rather than grants, with explicit task/user/platform intersection, command side effects, empty write scopes, symlink overlap, one-writer ownership, and no implied external-send authority. Required capability absence blocks; optional fallback must be disclosed. These are declarative requirements, not enforced mechanisms in this change.
- Budget prose bounds attempts, delegation depth, global concurrency and escalation, and prevents reset through rename/model/role/context changes. Adapter-side state is still required to enforce these limits. No state or scheduler implementation was claimed.
- Schema handles envelope shape and the completed-result all-pass/no-blocking condition. Cross-document criterion/evidence identity, safe paths, ceilings, graph cycles, stale results, truth of evidence and runtime capability checks are deliberately assigned to semantic validation/adapters. Their absence from JSON Schema alone is not a finding against the stated scope.
- Draft/exact-version behavior, unsupported capabilities, example fixture nonexecution, runtime identity uncertainty, and installation limits are disclosed. The example result is honestly blocked. Behavioral scenarios are explicitly specifications, not executed results. Review completion versus approval of reviewed work is distinguished.

## Adapter decisions worth making explicit

The task envelope contains no attempt number, while results require one and stale attempts must be rejected (`contracts/agent-work.schema.json:394–409,426–429`; `contracts/README.md:162–164`). An adapter can supply attempt identity in its dispatch wrapper, but the shared contract should document that transport responsibility before implementations diverge. Likewise, explicitly require unique task acceptance-criterion IDs during semantic validation: JSON Schema's `uniqueItems` compares entire objects, not their `id` fields. These are interface clarification requests, not claims of observed runtime failure.

## Verification limits

This review establishes source-level consistency and the issues above only. It does not establish schema-parser compatibility, realpath enforcement, discovery after installation, effective permission isolation, actual fresh-context behavior, model routing, cancellation, durable budget accounting, or passing B01–B10. Those require the other contributor's technical validation and fresh runtime evidence. No agent execution or test outcome was inferred from these artifacts.

## Follow-up review of corrections

Re-read the revised schema, contract prose, examples, adversarial mechanism guidance and integration handoff. Scope was limited to the previously reported issues and regressions from their corrections; no repository edits or technical tests.

- **Path finding resolved at source level.** Schema lines 229 and 589 now exclude control characters instead of all whitespace, so ordinary spaces are representable. Absolute slash paths, drive prefixes, backslashes and parent traversal remain rejected by the pattern, with realpath containment still required separately. The same update is consistently applied to canonical resource paths.
- **Independence overlap resolved at source level.** `skills/adversarial-consensus/SKILL.md:126–142` now bases eligibility on verified fresh context, expressly disclaims independence for sequential passes, and no longer assumes a vendor command exists. `docs/orchestration-handoff.md:24–28,41–43` accurately discloses this scoped change to an existing skill. No new unconditional delegation or external-service authority was introduced.
- **Dispatch and criterion identity clarified.** `contracts/README.md:104–110,164–166` requires dispatch IDs, orchestrator-owned persistent attempt accounting, unique criterion IDs and at-most-once dispatch acceptance. The schema requires `dispatch_id` and `attempt` for tasks and matching fields for results; both examples carry `example-dispatch-one` / attempt 1. Cross-document equality and uniqueness remain semantic adapter obligations, as documented.

**Remaining P2 regression — incompatible envelope change retained under the same exact version.** The earlier `0.1.0` task shape did not include `dispatch_id` or `attempt`, and result did not include `dispatch_id`; the revised schema requires those fields while keeping `contract_version` at `0.1.0`. `contracts/README.md:190–195` explicitly promises exact-version compatibility and requires a new contract version for any schema/enum change. An adapter built against the earlier draft rejects the new fields because unknown properties are forbidden, while the revised validator rejects its old envelopes. Bump the contract version consistently across schema/profiles/catalog/examples/docs and communicate the revision, or explicitly define the unpublished-draft compatibility policy before distributing this draft. This is a concrete violation of the contract's own version rule, not evidence that an existing deployed adapter has failed.

Follow-up verdict: original issues resolved, but REQUEST CHANGES on version handling before treating the revised interface as compatible. Static source review only; parser and runtime behavior remain unverified here.
