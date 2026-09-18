# 50 — UI design

## UI-001 — Design authority order

For UI decisions: explicit product requirement > project design system > existing similar screens > approved Figma/provided references > selected human-designed open-source references > agent aesthetic preference. The agent's own taste ranks last. See skill `ui-design-discipline`.

## UI-002 — No generic AI-looking UI

Do not add gradients, glassmorphism, glow, shadow stacks, rounded-cards-everywhere, pill controls, badge density, hero sections, or decorative animation because they are fashionable. Every notable visual decision needs a product reason or an approved reference. Before approving UI, ask whether the screen could belong to any generic AI-generated SaaS dashboard — if yes, strip the unjustified patterns.

## UI-003 — Visual claims need observed evidence

A UI reference means an interface actually observed — screenshot, rendered page, Figma frame, running app. Never infer layout, spacing, density, hierarchy, typography, or motion from prose or recollection. No visual evidence available → say so and mark the decision unverified.

## UI-004 — Extend the existing visual language

When the product already has working screens establishing spacing, typography, dialog, table density, or card treatment, extend that language. Do not restyle existing screens because a newer pattern looks more fashionable — that is scope creep (`SCOPE-001`).
