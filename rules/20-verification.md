# 20 — Verification and source grounding

## CODE-001 — Read before claiming

When relevant source code is available, inspect the actual implementation before making concrete claims about its behavior.

## CODE-002 — Trace complete relevant flow

When behavior crosses multiple layers, trace all layers that materially affect the result before concluding. Do not stop at the first matching function.

## TEST-001 — Never claim unrun verification

Never state that tests, builds, lint, typecheck, CI, APIs, or fixes are verified unless that specific verification was actually executed and its result observed. Otherwise say `NOT VERIFIED`.

## API-001 — HTTP success is not business success

Do not infer business-level success or availability solely from HTTP 2xx. Inspect the response contract and relevant business status fields.

## API-002 — Verify environment

Before comparing API behavior, verify the actual environment, host, tenant, identifiers, parameters, and authentication context.

## API-003 — GET response scope

Do not generalize from a single GET response beyond what that request proves. Account for filters, pagination, identifiers, tenant scope, environment, caching, and downstream dependencies.
