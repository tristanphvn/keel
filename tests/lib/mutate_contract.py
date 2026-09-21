#!/usr/bin/env python3
"""Generate negative contract fixtures from the canonical examples.

    python3 tests/lib/mutate_contract.py <examples-dir> <output-dir>

Each fixture is a minimal, deliberate corruption of a valid task/result pair, so
a failing check names one defect rather than a pile of them. Kept out of the
shell test so the mutations stay readable and reviewable as data.
"""

import copy
import json
import os
import sys

ZERO_REV = "0" * 40


def write(out, name, task, result):
    json.dump(task, open(os.path.join(out, name + "-task.json"), "w", encoding="utf-8"))
    json.dump(result, open(os.path.join(out, name + "-result.json"), "w", encoding="utf-8"))


def main(argv):
    ex, out = argv[0], argv[1]
    task0 = json.load(open(os.path.join(ex, "task.json"), encoding="utf-8"))
    result0 = json.load(open(os.path.join(ex, "result.json"), encoding="utf-8"))
    crit = task0["acceptance_criteria"][0]["id"]

    def pair():
        return copy.deepcopy(task0), copy.deepcopy(result0)

    # --- the schema accepts these; only semantics can reject them -------------

    t, r = pair()
    r["dispatch_id"] = "example-dispatch-two"
    write(out, "dispatch", t, r)

    t, r = pair()
    t["limits"]["max_attempts"] = 2
    t["attempt"] = 5
    r["attempt"] = 5
    write(out, "attempt", t, r)

    # Same id, different text: uniqueItems cannot see this, which is exactly the
    # limitation the contract calls out.
    t, r = pair()
    dup = dict(t["acceptance_criteria"][0])
    dup["description"] = "a second criterion reusing an existing id"
    t["acceptance_criteria"].append(dup)
    write(out, "dupcrit", t, r)

    t, r = pair()
    r["acceptance"] = [{"criterion_id": crit, "status": "pass", "evidence_ids": ["ev-0009"]}]
    write(out, "dangling", t, r)

    t, r = pair()
    r["acceptance"] = [{"criterion_id": "ac-0009", "status": "pass", "evidence_ids": []}]
    write(out, "invented", t, r)

    t, r = pair()
    t["permissions"] = ["read", "write", "execute", "network", "delegate"]
    write(out, "perms", t, r)

    t, r = pair()
    t["dependencies"] = [t["task_id"]]
    write(out, "selfdep", t, r)

    t, r = pair()
    r["changed_files"] = [{"path": "somewhere/else.txt", "change": "modified",
                           "revision": ZERO_REV}]
    write(out, "outofscope", t, r)

    t, r = pair()
    write(out, "replay", t, r)
    json.dump({"accepted_dispatch_ids": [result0["dispatch_id"]]},
              open(os.path.join(out, "ledger.json"), "w", encoding="utf-8"))

    # --- the schema rejects these too; asserted so it stays that way ----------

    t, r = pair()
    t["scope"]["write_paths"] = ["../outside/"]
    write(out, "escape", t, r)

    t, r = pair()
    r["status"] = "completed"
    r["unresolved"] = [{"description": "still broken", "blocking": True,
                        "next_action": "fix it"}]
    write(out, "blockcomplete", t, r)

    # --- delivery provenance (contract 0.3.0) --------------------------------
    # The completed pair is the one that carries delivered_skills, so the
    # delivery mutations are built from it.
    task1 = json.load(open(os.path.join(ex, "task-completed.json"), encoding="utf-8"))
    result1 = json.load(open(os.path.join(ex, "result-completed.json"), encoding="utf-8"))

    def pair1():
        return copy.deepcopy(task1), copy.deepcopy(result1)

    # Claiming delivery of a skill the role never declared.
    t, r = pair1()
    r["provenance"]["delivered_skills"][0]["ref"] = "skills/review-code/SKILL.md"
    write(out, "undeclared-skill", t, r)

    # A digest that is not a sha256 — traceability that cannot be checked.
    t, r = pair1()
    r["provenance"]["delivered_skills"][0]["sha256"] = "not-a-digest"
    write(out, "bad-digest", t, r)

    # The same skill claimed twice.
    t, r = pair1()
    r["provenance"]["delivered_skills"].append(
        dict(r["provenance"]["delivered_skills"][0]))
    write(out, "dup-delivery", t, r)

    # --- dependency graphs ----------------------------------------------------

    a, _ = pair(); a["task_id"] = "t-cycle-a"; a["dependencies"] = ["t-cycle-b"]
    b, _ = pair(); b["task_id"] = "t-cycle-b"; b["dependencies"] = ["t-cycle-a"]
    b["dispatch_id"] = "example-dispatch-two"
    json.dump(a, open(os.path.join(out, "cycle-a.json"), "w", encoding="utf-8"))
    json.dump(b, open(os.path.join(out, "cycle-b.json"), "w", encoding="utf-8"))

    a, _ = pair(); a["task_id"] = "t-dag-a"; a["dependencies"] = []
    b, _ = pair(); b["task_id"] = "t-dag-b"; b["dependencies"] = ["t-dag-a"]
    b["dispatch_id"] = "example-dispatch-two"
    json.dump(a, open(os.path.join(out, "dag-a.json"), "w", encoding="utf-8"))
    json.dump(b, open(os.path.join(out, "dag-b.json"), "w", encoding="utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
