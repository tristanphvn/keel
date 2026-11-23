---
name: principle-type-system-discipline
description: "Apply when designing types, reviewing a function signature, or writing code in any statically-typed language. Make illegal states unrepresentable, brand semantic primitives, parse external data at boundaries, exhaust variants, derive from authoritative schemas."
disable-model-invocation: true
---

# Type System Discipline

Make the compiler reject impossible states, mismatched primitives, and unhandled variants.

- **Make illegal states unrepresentable.** Model variants as sum types (discriminated unions, enums with payloads, sealed classes), not as a bag of optional fields where contradictory combinations compile. `{ completed: boolean; completedAt?: Date }` admits `completed: true` with no date; model `{ kind: 'open' } | { kind: 'done'; at: Date }` instead. If you can write a comment explaining when a combination of fields is valid, split it into a sum type. Match on it exhaustively, so the compiler fails when a new variant is added without handling.
- **Brand semantic primitives.** If two arguments share a primitive type but mean different things, give each its own type. Validate once at creation.
- **External data is untyped until parsed.** JSON, RPC payloads, CLI args, config, environment variables, and database rows go through a parse function at the boundary that returns the typed model.
- **Derive types from authoritative schemas.** When a schema file owns a shape, derive the type from it instead of hand-rolling a parallel one.
- **Strengthen a type only where partiality appears.** A runtime assertion, null check, or "this should never happen" throw marks the place a type is too weak. Push that check up into the type, then stop. `head` of an empty list has no answer, so it takes a non-empty list; `sum` of an empty list is 0, so it takes the plain one. If nothing would otherwise panic, keep the plain type.

For TypeScript syntax, see the **typescript-best-practices** skill.
