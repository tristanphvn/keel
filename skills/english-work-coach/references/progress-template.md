# Progress record schema

Keep the live record outside the installed skill. Start with unknown values, never invented achievements.

- Learner / goals / daily budget:
- Baseline date and evidence by modality:
- Current week and focus:
- Latest observed rubric dimensions (0–3 or N/A), task and support:
- Active phrases (phrase, learner example, last independent recall, next review):
- Recurring errors (up to 3, original, correction):
- Next session:

Append session entries:
- Unique session ID / date / assistant:
- Mode / minutes and timing source:
- Task / modality / independent or supported:
- Evidence and selective corrections:
- Recall results and due reviews:
- Next action:

For chat handoff, emit only current week, evidence, active phrases due, recurring errors, and next action. Never imply that this text was saved automatically.

## Coordination

Use one explicit learner-approved record location across assistants. Before each update, read the latest record and compare its revision or content with the version read earlier. If it changed, reread and append only your new session entry; preserve other entries. Do not keep separate Claude and Codex records or put personal progress in a shared project repository. If no shared location is accessible, return a compact handoff labelled not saved; do not invent a shared path.

Record current mode and the amount of help separately from performance scores. Keep baseline pending until the learner answers assessment tasks. Pasted plans, assistant-written models, and quoted prompts are not independent learner performance. Text-only sessions leave listening, pronunciation, and speaking fluency unassessed.
