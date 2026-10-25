---
name: principle-encode-lessons-in-structure
description: "Apply when you catch yourself writing the same instruction a second time, or notice a recurring correction. Encode the rule as a lint, metadata flag, runtime check, or script instead of more text."
disable-model-invocation: true
---

# Encode Lessons in Structure

When an instruction or correction recurs, encode it as a mechanism (lint rule, metadata flag, runtime check, script) and delete the instruction. Text needs the reader to notice, remember, and comply. A mechanism enforces the rule without cooperation.

**Pick the strongest mechanism.** When more than one would work, choose the strongest the situation allows: an unrepresentable state that cannot compile, then a lint or banned API that fails CI, then a canonical helper, then a runtime check. Agents copy whatever the surrounding code already does, so a weaker guard becomes the next template.

If the lesson needs judgment and cannot be encoded, make the instruction more prominent and add an example of the failure mode.

**Corollary:** If the fix is structural, only use the structural fix. The instruction is the symptom.
