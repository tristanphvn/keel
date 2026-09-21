#!/usr/bin/env python3
"""Validate runtime capability records — shape and semantics, separately.

    python3 scripts/capabilities/validate.py --schema
    python3 scripts/capabilities/validate.py --semantic
    python3 scripts/capabilities/validate.py --schema --semantic --record path.json

Why two modes
-------------
The schema checks shape: states are from the enum, digests look like digests. It
cannot check that a record claiming `enforced` actually carries enforcement-kind
evidence, that a cited probe still exists, or that the probe's digest still
matches the file in the tree. Those are the checks that keep a record honest as
the repository moves, and they are reported as their own result so a shape pass
is never mistaken for them.

Neither mode is a measurement. A record that validates here has not re-run any
probe; it says the claims are well-formed and internally consistent.

Exit codes: 0 pass · 1 validation failure · 2 usage/missing dependency
"""

import argparse
import hashlib
import json
import os
import sys

RECORD_VERSION = 1


def read_json(path):
    with open(path, "rb") as fh:
        return json.loads(fh.read().decode("utf-8"))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def evidence_requirements(root):
    """The required evidence level per capability, read from the schema.

    Kept in the schema rather than in code so the renderer and this validator
    cannot drift apart on what `tool-isolation` demands.
    """
    schema = read_json(os.path.join(root, "capabilities", "runtime-capability.schema.json"))
    return schema["$defs"]["evidence_requirements"]["const"]


def discover(root, explicit):
    if explicit:
        return list(explicit)
    out = []
    for sub in ("records", "examples"):
        d = os.path.join(root, "capabilities", sub)
        if os.path.isdir(d):
            out += [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".json")]
    return out


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


def run_schema(root, records):
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        sys.stderr.write(
            "FATAL: the `jsonschema` package is required for schema validation.\n"
            "       pip install jsonschema\n"
            "       Reported as unavailable, never as a pass.\n")
        return 2

    rep = Report("CAPABILITY SCHEMA VALIDATION")
    schema_path = os.path.join(root, "capabilities", "runtime-capability.schema.json")
    schema = read_json(schema_path)
    try:
        Draft202012Validator.check_schema(schema)
        rep.check("record schema is valid Draft 2020-12", True)
    except Exception as exc:
        rep.check("record schema is valid Draft 2020-12", False, str(exc))
        return rep.done()

    validator = Draft202012Validator(schema)
    for path in records:
        name = os.path.basename(path)
        errors = sorted(validator.iter_errors(read_json(path)), key=lambda e: list(e.path))
        rep.check(name, not errors, errors[0].message[:160] if errors else "")
    return rep.done()


def semantic_record(root, path, requirements, rep):
    name = os.path.basename(path)
    rec = read_json(path)

    rep.check("%s: record_version is %d" % (name, RECORD_VERSION),
              rec.get("record_version") == RECORD_VERSION, repr(rec.get("record_version")))

    # A record filename that disagrees with its content is a trap for whoever
    # picks a record by name later.
    if rec.get("status") == "measured":
        expected = "%s-%s-%s.json" % (rec["runtime"]["family"], rec["runtime"]["version"],
                                      rec["platform"]["os"])
        rep.check("%s: filename matches runtime, version and platform" % name,
                  name == expected, "expected %s" % expected)

    for cap, entry in sorted((rec.get("capabilities") or {}).items()):
        state = entry.get("state")
        evidence = entry.get("evidence") or []

        if state in ("enforced", "observed", "unavailable"):
            rep.check("%s/%s: a claim about the runtime cites evidence" % (name, cap),
                      bool(evidence), "state %r with no evidence" % state)
        if state == "unmeasured":
            rep.check("%s/%s: unmeasured records why" % (name, cap), bool(entry.get("reason")))
            rep.check("%s/%s: unmeasured cites no evidence" % (name, cap), not evidence)
        if state == "documented":
            rep.check("%s/%s: documented names its source" % (name, cap), bool(entry.get("source")))
            rep.check("%s/%s: documented cites no probe evidence" % (name, cap), not evidence)

        # The core rule: enforcement is not a synonym for observation.
        if state == "enforced":
            rep.check("%s/%s: enforced carries enforcement-kind evidence" % (name, cap),
                      any(e.get("kind") == "enforcement" for e in evidence),
                      "only observation-kind evidence present")

        # An example must never read as a measurement, whatever it claims.
        if rec.get("status") == "example":
            rep.check("%s/%s: an example claims no measured state" % (name, cap),
                      state in ("unmeasured", "documented"),
                      "example records may not claim %r" % state)

        for e in evidence:
            probe = e.get("probe", "")
            probe_path = os.path.join(root, probe)
            exists = os.path.isfile(probe_path)
            rep.check("%s/%s: probe %s exists" % (name, cap, probe), exists)
            if exists:
                # Probe drift invalidates the claim: the script that produced
                # this observation is not the script in the tree any more.
                actual = sha256_file(probe_path)
                rep.check("%s/%s: probe digest still matches the tree" % (name, cap),
                          actual == e.get("probe_sha256"),
                          "recorded %s, actual %s" % (str(e.get("probe_sha256"))[:12], actual[:12]))

    for cap in sorted(requirements):
        if cap not in (rec.get("capabilities") or {}):
            print("  note  %s: %s is absent — unknown, and unknown fails closed" % (name, cap))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=None)
    ap.add_argument("--schema", action="store_true")
    ap.add_argument("--semantic", action="store_true")
    ap.add_argument("--record", action="append", default=[])
    args = ap.parse_args(argv)

    if not (args.schema or args.semantic):
        ap.error("choose --schema, --semantic, or both (they are reported separately)")

    root = os.path.abspath(args.root) if args.root else \
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    records = discover(root, args.record)
    if not records:
        sys.stderr.write("FATAL: no capability records found under %s/capabilities\n" % root)
        return 2

    rc = 0
    if args.schema:
        print("== schema ==")
        rc |= run_schema(root, records)
        print("")

    if args.semantic:
        print("== semantics ==")
        rep = Report("CAPABILITY SEMANTIC VALIDATION")
        requirements = evidence_requirements(root)
        for path in records:
            semantic_record(root, path, requirements, rep)
        rc |= rep.done()

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
