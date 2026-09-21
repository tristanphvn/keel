#!/usr/bin/env python3
"""Validate agent-work contract documents — shape and semantics, separately.

    python3 scripts/contracts/validate.py --schema               # JSON Schema shape only
    python3 scripts/contracts/validate.py --semantic             # canonical roles/catalog
    python3 scripts/contracts/validate.py --semantic \
        --task contracts/examples/task.json \
        --result contracts/examples/result.json \
        [--ledger accepted.json]

Why two modes
-------------
The schema checks shape. It cannot check that a result's acceptance entries
refer to criteria the task actually declared, that an evidence ID exists, that a
dependency graph is acyclic, or that a dispatch is accepted only once. The
contract says so itself, and requires adapters to enforce those separately.
Running them as one pass would let a shape pass be mistaken for a semantic pass.

Neither mode is runtime enforcement. A document that validates here says nothing
about whether a runtime honoured a permission, a budget or a tool boundary.

Exit codes: 0 pass · 1 validation failure · 2 usage/missing dependency
"""

import argparse
import json
import os
import re
import sys

CONTRACT_VERSION = "0.2.0"
BAD_REF = re.compile(r"^(/|[A-Za-z]:)|(^|/)\.\.(/|$)|\\")


def read_json(path):
    with open(path, "rb") as fh:
        return json.loads(fh.read().decode("utf-8"))


class Report(object):
    def __init__(self, title):
        self.title = title
        self.failures = []
        self.checks = 0

    def check(self, name, ok, detail=""):
        self.checks += 1
        if ok:
            print("  ok    %s" % name)
        else:
            print("  FAIL  %s%s" % (name, (" — " + detail) if detail else ""))
            self.failures.append(name)
        return ok

    def done(self):
        print("")
        if self.failures:
            print("%s: FAIL (%d of %d)" % (self.title, len(self.failures), self.checks))
            return 1
        print("%s: PASS (%d checks)" % (self.title, self.checks))
        return 0


# --- schema mode --------------------------------------------------------------

def run_schema(root, extra_docs):
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        sys.stderr.write(
            "FATAL: the `jsonschema` package is required for schema validation.\n"
            "       pip install jsonschema\n"
            "       This is reported as unavailable, never as a pass.\n")
        return 2

    rep = Report("SCHEMA VALIDATION")
    schema_path = os.path.join(root, "contracts", "agent-work.schema.json")
    schema = read_json(schema_path)
    try:
        Draft202012Validator.check_schema(schema)
        rep.check("schema itself is valid Draft 2020-12", True)
    except Exception as exc:
        rep.check("schema itself is valid Draft 2020-12", False, str(exc))
        return rep.done()

    validator = Draft202012Validator(schema)
    docs = [os.path.join(root, "roles", "catalog.json")]
    roles_dir = os.path.join(root, "roles")
    docs += sorted(os.path.join(roles_dir, f) for f in os.listdir(roles_dir)
                   if f.endswith(".json") and f != "catalog.json")
    ex = os.path.join(root, "contracts", "examples")
    if os.path.isdir(ex):
        docs += sorted(os.path.join(ex, f) for f in os.listdir(ex) if f.endswith(".json"))
    docs += list(extra_docs)

    for path in docs:
        try:
            rel = os.path.relpath(path, root)
        except ValueError:
            # A document supplied from another drive (Windows): name it in full
            # rather than failing the run over a display detail.
            rel = path
        errors = sorted(validator.iter_errors(read_json(path)), key=lambda e: list(e.path))
        rep.check(rel, not errors, errors[0].message if errors else "")
    return rep.done()


# --- semantic mode ------------------------------------------------------------

def semantic_canonical(root, rep):
    """Checks across the canonical role set that shape validation cannot make."""
    catalog = read_json(os.path.join(root, "roles", "catalog.json"))
    rep.check("catalog contract_version is %s" % CONTRACT_VERSION,
              catalog.get("contract_version") == CONTRACT_VERSION,
              repr(catalog.get("contract_version")))

    roles = {}
    ids = []
    for ref in catalog.get("role_refs", []):
        ok_ref = not BAD_REF.search(ref)
        if not rep.check("role ref %s is contained" % ref, ok_ref, "traversal or absolute path"):
            continue
        path = os.path.realpath(os.path.join(root, ref))
        if not rep.check("role ref %s exists" % ref, os.path.isfile(path)):
            continue
        role = read_json(path)
        ids.append(role.get("id"))
        roles[role.get("id")] = role

    rep.check("role ids are unique", len(ids) == len(set(ids)),
              "duplicates: %s" % [i for i in set(ids) if ids.count(i) > 1])
    rep.check("every catalog role_ref resolved", len(roles) == len(catalog.get("role_refs", [])))

    policies = set(catalog.get("model_policy_refs", []))
    for rid, role in sorted(roles.items()):
        rep.check("role %s uses a declared model policy" % rid,
                  role.get("model_policy_ref") in policies,
                  repr(role.get("model_policy_ref")))
        refs = role.get("skill_refs") or []
        rep.check("role %s declares at least one skill" % rid, bool(refs))
        for sref in refs:
            contained = not BAD_REF.search(sref)
            exists = contained and os.path.isfile(os.path.realpath(os.path.join(root, sref)))
            rep.check("role %s skill %s resolves inside the root" % (rid, sref),
                      bool(contained and exists))

    for ref in catalog.get("rule_refs", []):
        rep.check("catalog rule %s exists" % ref,
                  os.path.isfile(os.path.join(root, ref)))

    limits = catalog.get("default_limits") or {}
    for key in ("max_attempts", "max_delegation_depth", "max_parallel_agents",
                "max_model_escalations"):
        rep.check("default limit %s is a positive integer" % key,
                  isinstance(limits.get(key), int) and limits[key] >= 0, repr(limits.get(key)))
    return roles, catalog


def semantic_task(task, roles, catalog, rep, task_graph=None):
    tid = task.get("task_id")
    role = roles.get(task.get("role_id"))
    rep.check("task role %r exists in the catalog" % task.get("role_id"), role is not None)

    # Criterion IDs: array-item uniqueness in the schema does not make IDs unique.
    crit_ids = [c.get("id") for c in task.get("acceptance_criteria", [])]
    rep.check("task %s criterion IDs are unique" % tid,
              len(crit_ids) == len(set(crit_ids)),
              "duplicates: %s" % sorted(i for i in set(crit_ids) if crit_ids.count(i) > 1))
    rep.check("task %s has at least one acceptance criterion" % tid, bool(crit_ids))

    # Permissions are bounded by the role ceiling; a ceiling grants nothing.
    if role:
        ceiling = set(role.get("permission_ceiling", []))
        asked = set(task.get("permissions", []))
        rep.check("task %s permissions are within the role ceiling" % tid,
                  asked <= ceiling, "excess: %s" % sorted(asked - ceiling))
        req = set(task.get("required_capabilities", []))
        unknown = req - set(role.get("required_capabilities", [])) - set(role.get("optional_capabilities", []))
        rep.check("task %s requires no capability the role does not name" % tid,
                  not unknown, "extra: %s" % sorted(unknown))

    # Write paths: workspace-relative, contained, directory prefixes end in "/".
    for p in (task.get("scope") or {}).get("write_paths", []):
        rep.check("task %s write path %r is contained" % (tid, p), not BAD_REF.search(p),
                  "absolute, traversing or backslash-separated")

    # Budgets may not exceed catalog defaults without explicit authorization.
    defaults = catalog.get("default_limits") or {}
    limits = task.get("limits") or {}
    for key, value in limits.items():
        if key in defaults:
            rep.check("task %s limit %s is within the catalog default" % (tid, key),
                      value <= defaults[key], "%s > %s" % (value, defaults[key]))

    # Dependencies: exist, no self-reference, acyclic.
    deps = task.get("dependencies") or []
    rep.check("task %s does not depend on itself" % tid, tid not in deps)
    if task_graph is not None:
        missing = [d for d in deps if d not in task_graph]
        rep.check("task %s dependencies exist in the graph" % tid, not missing,
                  "missing: %s" % missing)


def detect_cycles(graph):
    """graph: {task_id: [dependency_id, ...]} — returns a cycle or None."""
    WHITE, GREY, BLACK = 0, 1, 2
    colour = dict((k, WHITE) for k in graph)
    stack = []

    def visit(node):
        colour[node] = GREY
        stack.append(node)
        for dep in graph.get(node, []):
            if dep not in colour:
                continue
            if colour[dep] == GREY:
                return stack[stack.index(dep):] + [dep]
            if colour[dep] == WHITE:
                found = visit(dep)
                if found:
                    return found
        colour[node] = BLACK
        stack.pop()
        return None

    for node in graph:
        if colour[node] == WHITE:
            found = visit(node)
            if found:
                return found
    return None


def semantic_result(task, result, rep, ledger=None):
    tid = task.get("task_id")

    # Dispatch identity: all three fields must be echoed exactly.
    rep.check("result echoes task_id", result.get("task_id") == tid,
              "%r != %r" % (result.get("task_id"), tid))
    rep.check("result echoes dispatch_id",
              result.get("dispatch_id") == task.get("dispatch_id"),
              "%r != %r" % (result.get("dispatch_id"), task.get("dispatch_id")))
    rep.check("result echoes attempt", result.get("attempt") == task.get("attempt"),
              "%r != %r" % (result.get("attempt"), task.get("attempt")))

    # Attempt within the effective budget.
    max_attempts = (task.get("limits") or {}).get("max_attempts")
    if isinstance(max_attempts, int):
        rep.check("attempt %s is within the budget of %s" % (result.get("attempt"), max_attempts),
                  isinstance(result.get("attempt"), int) and 1 <= result["attempt"] <= max_attempts)

    # Evidence IDs unique; every referenced ID exists.
    ev_ids = [e.get("id") for e in result.get("evidence", [])]
    rep.check("evidence IDs are unique", len(ev_ids) == len(set(ev_ids)),
              "duplicates: %s" % sorted(i for i in set(ev_ids) if ev_ids.count(i) > 1))
    ev_set = set(ev_ids)

    crit_ids = set(c.get("id") for c in task.get("acceptance_criteria", []))
    seen = []
    for entry in result.get("acceptance", []):
        cid = entry.get("criterion_id")
        seen.append(cid)
        rep.check("acceptance entry %r resolves to a task criterion" % cid, cid in crit_ids,
                  "not declared by the task")
        missing = [e for e in entry.get("evidence_ids", []) if e not in ev_set]
        rep.check("acceptance %r references only existing evidence" % cid, not missing,
                  "dangling: %s" % missing)
        if entry.get("status") == "pass":
            rep.check("passing criterion %r cites at least one evidence ID" % cid,
                      bool(entry.get("evidence_ids")))

    rep.check("every task criterion is recorded exactly once",
              sorted(seen) == sorted(crit_ids) and len(seen) == len(set(seen)),
              "recorded %s, declared %s" % (sorted(seen), sorted(crit_ids)))

    # A completed result may not leave a blocking unresolved item.
    if result.get("status") == "completed":
        blocking = [u for u in result.get("unresolved", []) if u.get("blocking")]
        rep.check("completed result has no blocking unresolved item", not blocking)
        failed = [a.get("criterion_id") for a in result.get("acceptance", [])
                  if a.get("status") != "pass"]
        rep.check("completed result passes every criterion", not failed,
                  "not passing: %s" % failed)
    if result.get("status") == "blocked":
        rep.check("blocked result names a blocking item with a next action",
                  any(u.get("blocking") and u.get("next_action")
                      for u in result.get("unresolved", [])))

    # Changed files must be inside the task's allowed write scope.
    write_paths = (task.get("scope") or {}).get("write_paths", [])
    for cf in result.get("changed_files", []):
        p = cf.get("path", "")
        allowed = any(p == w or (w.endswith("/") and p.startswith(w)) for w in write_paths)
        rep.check("changed file %r is within the write scope" % p, allowed,
                  "write_paths: %s" % write_paths)

    # Observed runtime identity is never invented.
    prov = result.get("provenance") or {}
    for key in ("runtime", "runtime_version", "model"):
        value = prov.get(key)
        rep.check("provenance %s is stated (or explicitly unverified)" % key,
                  isinstance(value, str) and value != "", repr(value))

    # A dispatch may be accepted at most once.
    if ledger is not None:
        did = result.get("dispatch_id")
        rep.check("dispatch %r has not already been accepted" % did,
                  did not in set(ledger.get("accepted_dispatch_ids", [])))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=None)
    ap.add_argument("--schema", action="store_true", help="JSON Schema shape validation")
    ap.add_argument("--semantic", action="store_true", help="cross-document semantic checks")
    ap.add_argument("--task", action="append", default=[])
    ap.add_argument("--result", action="append", default=[])
    ap.add_argument("--ledger", default=None, help="JSON with accepted_dispatch_ids")
    args = ap.parse_args(argv)

    if not (args.schema or args.semantic):
        ap.error("choose --schema, --semantic, or both (they are reported separately)")

    root = os.path.abspath(args.root) if args.root else \
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    rc = 0
    if args.schema:
        print("== schema ==")
        rc |= run_schema(root, args.task + args.result)
        print("")

    if args.semantic:
        print("== semantics ==")
        rep = Report("SEMANTIC VALIDATION")
        roles, catalog = semantic_canonical(root, rep)

        tasks = [read_json(p) for p in args.task]
        graph = dict((t.get("task_id"), t.get("dependencies") or []) for t in tasks)
        for task in tasks:
            semantic_task(task, roles, catalog, rep, graph)
        if graph:
            cycle = detect_cycles(graph)
            rep.check("dependency graph is acyclic", cycle is None, "cycle: %s" % cycle)

        ledger = read_json(args.ledger) if args.ledger else None
        by_id = dict((t.get("task_id"), t) for t in tasks)
        for path in args.result:
            result = read_json(path)
            task = by_id.get(result.get("task_id"))
            if task is None:
                rep.check("result %s matches a supplied task" % os.path.basename(path), False,
                          "no task with task_id %r was provided" % result.get("task_id"))
                continue
            semantic_result(task, result, rep, ledger)
        rc |= rep.done()

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
