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

RECORD_VERSION = 2


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


class _Collector(object):
    """A Report that keeps failures instead of printing them."""

    def __init__(self):
        self.failures = []
        self.checks = 0

    def check(self, name, ok, detail=""):
        self.checks += 1
        if not ok:
            self.failures.append("%s%s" % (name, (" — " + detail) if detail else ""))
        return ok


def validate_record_file(root, path):
    """Canonically validate ONE record. Returns (ok, [problem, ...]).

    This is the entry point other tooling calls — notably the renderer, before a
    record is allowed to authorise anything. Keeping it here rather than
    reimplementing the checks at the call site is the point: a second, weaker
    copy of "is this record trustworthy" is how a record claiming `enforced`
    with no evidence gets accepted.

    It validates a record. It does not re-run a probe, and says nothing about
    whether the runtime still behaves as the record says.
    """
    problems = []
    try:
        read_json(path)
    except ValueError as exc:
        return False, ["%s: invalid JSON: %s" % (os.path.basename(path), exc)]
    except IOError as exc:
        return False, ["%s: cannot read: %s" % (os.path.basename(path), exc)]

    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        # Fail closed: an unvalidated record must not authorise rendering.
        return False, [
            "the `jsonschema` package is required to validate a capability record "
            "before it authorises rendering (pip install jsonschema). An unvalidated "
            "record is not evidence."]

    schema = read_json(os.path.join(root, "capabilities", "runtime-capability.schema.json"))
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(read_json(path)), key=lambda e: list(e.path))
    problems += ["schema: %s" % e.message for e in errors[:5]]

    collector = _Collector()
    semantic_record(root, path, evidence_requirements(root), collector)
    problems += collector.failures
    return (not problems), problems


def semantic_record(root, path, requirements, rep):
    name = os.path.basename(path)
    rec = read_json(path)

    rep.check("%s: record_version is %d" % (name, RECORD_VERSION),
              rec.get("record_version") == RECORD_VERSION, repr(rec.get("record_version")))

    # A record filename that disagrees with its content is a trap for whoever
    # picks a record by name later — but that is a convention of this
    # repository's records directory, not a property of a record. An operator
    # keeping records elsewhere, or passing one by an arbitrary path, is not
    # writing an invalid record, so the check is scoped to where the convention
    # applies.
    in_records_dir = os.path.dirname(os.path.abspath(path)) == \
        os.path.join(os.path.abspath(root), "capabilities", "records")
    if rec.get("status") == "measured" and in_records_dir:
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

    # Observations are not capability claims, but their evidence is held to the
    # same standard: a probe that no longer exists, or whose content has since
    # changed, cannot support the observation recorded from it.
    for obs in rec.get("observations") or []:
        oid = obs.get("id")
        for e in obs.get("evidence") or []:
            probe = e.get("probe", "")
            probe_path = os.path.join(root, probe)
            exists = os.path.isfile(probe_path)
            rep.check("%s: observation %s probe %s exists" % (name, oid, probe), exists)
            if exists:
                actual = sha256_file(probe_path)
                rep.check("%s: observation %s probe digest still matches" % (name, oid),
                          actual == e.get("probe_sha256"),
                          "recorded %s, actual %s" % (str(e.get("probe_sha256"))[:12], actual[:12]))
        # An observation that silently decided a capability is the failure this
        # section exists to prevent, so the disclaimer is required to be honest.
        for cap in obs.get("not_a_claim_about") or []:
            state = ((rec.get("capabilities") or {}).get(cap) or {}).get("state")
            rep.check("%s: observation %s does not also decide %s" % (name, oid, cap),
                      state in (None, "unmeasured", "documented"),
                      "%s is recorded as %r while an observation disclaims measuring it"
                      % (cap, state))

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
