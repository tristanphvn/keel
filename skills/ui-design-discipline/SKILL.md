---
name: ui-design-discipline
description: Reference-backed UI design discipline — never freestyle generic AI-looking interfaces. Use when designing, building, restyling, or reviewing any product UI, screen, component, layout, landing page, dashboard, form, dialog, or visual treatment, when choosing spacing/typography/color/density/motion, when picking design references, and before approving UI work. Enforces design authority order, human-designed references, anti-AI-slop review, and functional hierarchy before visual fashion.
---

# Human-Referenced Design — Never Freestyle Generic AI UI

## Core rule

Do not invent a product UI primarily from the model's own aesthetic preferences, current AI-generated design trends, or whatever visual style is fashionable in recent generated interfaces.

The UI should look intentionally designed for the product.

It should not look like:

> "an AI generated a modern SaaS screen."

---

# Design authority order

```text
1. Explicit product requirement
2. Existing project design system
3. Existing similar screens/components
4. Approved Figma / provided references
5. Selected human-designed open-source references
6. Agent aesthetic preference
```

The agent's personal visual preference is last.

When a project carries its own design constitution, design system, or design academy (e.g. a vault `design-system/` or `_common/academy/`), it outranks everything in this skill except an explicit product requirement. This skill is the floor for projects that have no such direction — never a substitute for one that does.

---

# Do not freestyle

For non-trivial UI, do not start with:

```text
"What modern UI should I generate?"
```

Start with:

```text
"What visual language does this product already use?"
"What human-designed references fit this product?"
"What existing pattern should this screen belong to?"
```

---

# Avoid recognizable AI-generated UI patterns

Do not add these merely because they are popular:

- excessive gradients;
- glassmorphism;
- glow effects;
- excessive shadows;
- rounded cards everywhere;
- nested cards without hierarchy reason;
- floating pills for every action/filter;
- badges on every row;
- huge marketing-style headings inside product UI;
- unnecessary hero sections;
- decorative icons everywhere;
- excessive animation;
- abstract colored blobs;
- oversized empty whitespace;
- generic SaaS dashboard layouts;
- unnecessary dark-mode neon styling;
- visual effects that do not improve comprehension or interaction.

These are not forbidden absolutely. They are forbidden when no product-specific reason or approved reference supports them.

---

# Reference-backed design

For non-trivial UI design:

1. inspect the current project's visual language;
2. identify the screen/use-case type;
3. identify a small set of relevant human-designed references;
4. compare them for product fit;
5. extract patterns;
6. adapt those patterns to the existing design system.

Do not blindly copy a reference. Do not combine unrelated visual systems.

---

## Visual evidence is mandatory

A "reference" means an interface that was actually **observed** — a screenshot, a rendered page, a Figma frame, a running app. Not a remembered impression of a product, not a prose description, not a name recalled from training data.

Never conclude what a reference looks like from text or recollection. If no visual evidence is available for a claim about layout, spacing, density, hierarchy, typography, or motion, say so plainly and either obtain the evidence or mark the decision `UNVERIFIED` — see `TEST-001` and `VERIFY-002`.

Evidence hierarchy for UI claims:

```text
1. the running interface (screenshot / browser / device)
2. the design file (Figma frame)
3. the project's own shipped screens and component source
4. documented design-system rules
5. reasoned inference        ← label as inference
6. recollection              ← not evidence
```

---

# Human-designed reference preference

Prefer references showing evidence of deliberate product design:

- established open-source design systems;
- mature product interfaces;
- approved Figma work;
- well-maintained component systems;
- consistent real-world applications.

Use references to derive:

```text
hierarchy
spacing
density
interaction patterns
component composition
responsive behavior
state design
```

not merely decoration.

---

# No style mixing

Do not build a screen like:

```text
header from reference A
cards from reference B
buttons from reference C
animations from reference D
colors from current AI trend
```

unless they share a coherent design language.

A UI should feel like one product designed by one team.

---

# Product-specific design

Ask:

```text
What kind of product is this?
Who uses it?
How dense should it be?
How frequently is this screen used?
Is this an operational interface or a marketing surface?
What existing screens must it visually belong to?
```

A builder, admin portal, dashboard, consumer app, and marketing landing page should not share the same aesthetic treatment by default.

---

# If the project has no clear visual direction

Do NOT invent one directly.

```text
1. identify product category;
2. select 2–3 compatible human-designed reference systems;
3. define a small visual direction;
4. keep that direction internally consistent;
5. then design.
```

Reference-backed authorship, not model-generated fashion.

---

# Existing UI first

If the product already contains a working screen establishing:

- toolbar style;
- spacing;
- form layout;
- dialog pattern;
- table density;
- typography;
- card treatment;

prefer extending that language.

Do not replace it with a newer-looking pattern solely because the new one appears more fashionable. Restyling existing screens is scope expansion unless requested — see `SCOPE-001`.

---

# AI-Looking Design Review

Before approving a UI, explicitly inspect for generic AI-design artifacts.

Ask:

```text
Does this look product-specific?

or

Could this screen belong to any generic AI-generated SaaS dashboard?
```

Check for:

- decorative gradients without purpose;
- too many rounded containers;
- excessive pill controls;
- unnecessary glow/shadow;
- giant headings inappropriate for the workflow;
- unnecessary cards;
- unnecessary badge density;
- excessive animation;
- generic empty-state illustrations;
- fashionable patterns unsupported by existing screens;
- visual inconsistency caused by mixing references.

If such patterns exist without a clear product reason: remove them.

---

# Functional hierarchy before visual fashion

```text
information hierarchy
→ workflow
→ layout
→ density
→ spacing
→ typography
→ states
→ visual refinement
```

Do not start from:

```text
gradient
→ card
→ shadow
→ animation
```

---

# Open-source references

Open-source design systems are references, not automatic dependencies.

Do not install another UI framework merely because its examples are visually useful.

Prefer:

```text
inspect pattern
→ understand why it works
→ adapt using existing project components
```

over:

```text
find nice component
→ install library
```

---

# Preserve intentional imperfections

Do not homogenize every screen into one generic visual template.

Real products can have:

- different information density;
- different layout structures;
- different component compositions;

while still following the same design system.

Consistency does not mean every screen must look identical.

---

# Final test

```text
Would an experienced designer recognize why each major visual decision exists?
```

and:

```text
Does this look specifically designed for this product?
```

If the justification is mostly:

```text
"because it looks modern"
```

the design is not ready.

Final rule:

> Do not generate fashionable UI.
> Design a coherent product interface grounded in real references.

---

# Related

- `artifact-design` (builtin) — design investment calibration for published Artifacts; this skill's authority order and AI-slop review still apply on top
- `dataviz` (builtin) — charts, palettes, stat tiles; its palette/accessibility rules govern chart internals
- `figma-*` skills — reading approved design context (`get_design_context`, `get_screenshot`) is the preferred way to obtain visual evidence
- `intent-first-review` — judge UI findings by product impact, not taste
- `adversarial-consensus` — for contested design decisions: defend, falsify, adjudicate on evidence
