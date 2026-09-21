#!/usr/bin/env python3
"""Render role-to-model routing into runtime-native agent definitions.

    python3 scripts/routing/render.py --runtime claude --target ~/.claude
    python3 scripts/routing/render.py --runtime codex  --target ~/.codex --apply
    python3 scripts/routing/render.py --runtime claude --target ~/.claude --check

What it does
------------
Reads a routing file (config/routing/models.yaml) that maps opaque ROLE ids onto
model tiers, reasoning levels and per-runtime options, and writes one agent
definition per role in the format the target runtime actually reads:

    claude -> <target>/agents/<id>.md    (YAML frontmatter: name, description, model, tools)
    codex  -> <target>/agents/<id>.toml  (name, description, developer_instructions, model, ...)

What it deliberately does not do
--------------------------------
It never authors role instructions. Every role must point at a profile file, and
the instructions are copied from there verbatim. A routing file with no roles
renders nothing and says so — that is the expected state until canonical role
profiles exist.

Ownership
---------
Every file written is recorded in <target>/.agent-skills/routing-manifest.tsv
with its hash. A pre-existing file that is not in the manifest is a collision:
it is reported and skipped, never overwritten. Removal is by the same rule.

Exit codes: 0 ok · 1 collision or write failure · 2 schema/config error
"""

import argparse
import hashlib
import os
import re
import sys

# --- YAML ---------------------------------------------------------------------
# PyYAML when present. Otherwise a parser for the restricted subset this config
# is specified in: 2-space indentation, `key: value` mappings, `- ` sequences
# (of scalars or of mappings), inline `[a, b]` flow sequences, `#` comments.
# The subset is documented in docs/routing.md; anything outside it is an error
# rather than a guess.

try:
    import yaml  # type: ignore

    def load_yaml(text, where):
        try:
            return yaml.safe_load(text) or {}
        except Exception as exc:  # pragma: no cover - depends on host
            die(2, "%s: %s" % (where, str(exc).replace("\n", " ")))
except ImportError:
    def load_yaml(text, where):
        return _MiniYaml(text, where).parse()


class _MiniYaml(object):
    SCALAR = re.compile(r"^(?P<key>[A-Za-z0-9_.-]+):\s*(?P<val>.*)$")

    def __init__(self, text, where):
        self.where = where
        self.lines = []
        for n, raw in enumerate(text.splitlines(), 1):
            if not raw.strip() or raw.lstrip().startswith("#"):
                continue
            stripped = raw.split(" #", 1)[0].rstrip() if " #" in raw else raw.rstrip()
            indent = len(stripped) - len(stripped.lstrip(" "))
            if (indent % 2) != 0:
                die(2, "%s:%d: indentation must be a multiple of 2 spaces" % (where, n))
            self.lines.append((indent, stripped.strip(), n))
        self.pos = 0

    def parse(self):
        return self._block(0)

    def _peek(self):
        return self.lines[self.pos] if self.pos < len(self.lines) else None

    def _block(self, indent):
        item = self._peek()
        if item is None:
            return {}
        if item[1].startswith("- "):
            return self._sequence(indent)
        return self._mapping(indent)

    def _mapping(self, indent):
        out = {}
        while True:
            item = self._peek()
            if item is None or item[0] < indent or item[1].startswith("- "):
                return out
            ind, text, lineno = item
            if ind > indent:
                die(2, "%s:%d: unexpected indentation" % (self.where, lineno))
            m = self.SCALAR.match(text)
            if not m:
                die(2, "%s:%d: not a `key: value` line: %s" % (self.where, lineno, text))
            self.pos += 1
            key, val = m.group("key"), m.group("val").strip()
            if val == "":
                nxt = self._peek()
                if nxt is not None and nxt[0] > ind:
                    out[key] = self._block(nxt[0])
                else:
                    out[key] = None
            else:
                out[key] = self._scalar(val, lineno)
        return out

    def _sequence(self, indent):
        out = []
        while True:
            item = self._peek()
            if item is None or item[0] < indent or not item[1].startswith("- "):
                return out
            ind, text, lineno = item
            body = text[2:].strip()
            self.pos += 1
            if self.SCALAR.match(body) and not body.startswith("["):
                # A mapping whose first key shares the dash line.
                m = self.SCALAR.match(body)
                entry = {}
                key, val = m.group("key"), m.group("val").strip()
                if val == "":
                    nxt = self._peek()
                    entry[key] = self._block(nxt[0]) if (nxt and nxt[0] > ind) else None
                else:
                    entry[key] = self._scalar(val, lineno)
                while True:
                    nxt = self._peek()
                    if nxt is None or nxt[0] <= ind or nxt[1].startswith("- "):
                        break
                    rest = self._mapping(nxt[0])
                    entry.update(rest)
                out.append(entry)
            else:
                out.append(self._scalar(body, lineno))
        return out

    def _scalar(self, val, lineno):
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            if not inner:
                return []
            return [self._scalar(p.strip(), lineno) for p in inner.split(",")]
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            return val[1:-1]
        low = val.lower()
        if low in ("true", "false"):
            return low == "true"
        if low in ("null", "~"):
            return None
        if re.match(r"^-?\d+$", val):
            return int(val)
        return val


# --- helpers ------------------------------------------------------------------

def die(code, msg):
    sys.stderr.write("FATAL: %s\n" % msg)
    raise SystemExit(code)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def read_text(path):
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8")


def write_text(path, text):
    """Write through a temporary file so a failure cannot truncate the target."""
    tmp = path + ".routing-tmp.%d" % os.getpid()
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with open(tmp, "wb") as fh:
        fh.write(text.encode("utf-8"))
    if os.path.exists(path):
        os.remove(path)
    os.rename(tmp, path)


def parse_profile(path, where):
    """Split a role profile into (frontmatter dict, body). Never invents fields."""
    text = read_text(path)
    if not text.startswith("---"):
        die(2, "%s: profile %s has no frontmatter" % (where, path))
    parts = text.split("---", 2)
    if len(parts) < 3:
        die(2, "%s: profile %s has an unterminated frontmatter block" % (where, path))
    meta = load_yaml(parts[1], path) or {}
    body = parts[2].lstrip("\n")
    if not isinstance(meta, dict) or not meta.get("description"):
        die(2, "%s: profile %s has no `description` — routing will not invent one" % (where, path))
    if not body.strip():
        die(2, "%s: profile %s has an empty body — nothing to instruct the agent with" % (where, path))
    return meta, body


# --- schema -------------------------------------------------------------------

REASONING_DEFAULT_LEVELS = ["low", "medium", "high", "xhigh"]


def validate(cfg, where, runtime):
    """Check the routing file, and resolve every role. Errors are fatal and listed."""
    errors = []
    if not isinstance(cfg, dict):
        die(2, "%s: top level must be a mapping" % where)
    if cfg.get("version") != 1:
        errors.append("version must be 1 (got %r)" % cfg.get("version"))

    catalog = {}
    for entry in cfg.get("catalog") or []:
        if not isinstance(entry, dict) or "tier" not in entry:
            errors.append("catalog entries need a `tier`")
            continue
        per_runtime = entry.get(runtime)
        if per_runtime is None:
            continue
        if not isinstance(per_runtime, dict) or not per_runtime.get("model"):
            errors.append("catalog tier %r has no `model` for runtime %r" % (entry["tier"], runtime))
            continue
        catalog[entry["tier"]] = per_runtime

    reasoning = cfg.get("reasoning") or {}
    levels = reasoning.get("levels") or REASONING_DEFAULT_LEVELS
    default_reasoning = reasoning.get("default")
    if default_reasoning is not None and default_reasoning not in levels:
        errors.append("reasoning.default %r is not one of %s" % (default_reasoning, levels))

    fallback = cfg.get("fallback") or {}
    unknown_model = fallback.get("on_unknown_model", "deny")
    if unknown_model not in ("deny", "use_default"):
        errors.append("fallback.on_unknown_model must be `deny` or `use_default`")

    roles = cfg.get("roles") or []
    if not isinstance(roles, list):
        errors.append("roles must be a list")
        roles = []

    resolved = []
    base = os.path.dirname(os.path.abspath(where))
    seen = set()
    for role in roles:
        if not isinstance(role, dict):
            errors.append("each role must be a mapping")
            continue
        rid = role.get("id")
        if not rid:
            errors.append("a role has no `id`")
            continue
        if rid in seen:
            errors.append("duplicate role id %r" % rid)
            continue
        seen.add(rid)
        if not re.match(r"^[a-z0-9][a-z0-9_-]*$", str(rid)):
            errors.append("role id %r must be lowercase alphanumeric with - or _" % rid)
            continue

        profile = role.get("profile")
        if not profile:
            errors.append("role %r has no `profile`; routing never authors instructions" % rid)
            continue
        ppath = profile if os.path.isabs(profile) else os.path.join(base, profile)
        if not os.path.isfile(ppath):
            errors.append("role %r: profile not found: %s" % (rid, ppath))
            continue

        tier = role.get("tier")
        if tier is None:
            errors.append("role %r has no `tier`" % rid)
            continue
        if tier not in catalog:
            if unknown_model == "deny":
                errors.append(
                    "role %r asks for tier %r, which has no %s model. "
                    "fallback.on_unknown_model is `deny`, so this is an error rather "
                    "than a silent substitution." % (rid, tier, runtime))
                continue
            catalog_entry = {"model": None}
        else:
            catalog_entry = catalog[tier]

        effort = role.get("reasoning", default_reasoning)
        if effort is not None and effort not in levels:
            errors.append("role %r: reasoning %r is not one of %s" % (rid, effort, levels))
            continue

        meta, body = parse_profile(ppath, where)
        resolved.append({
            "id": str(rid),
            "description": str(meta["description"]).strip(),
            "instructions": body.rstrip() + "\n",
            "model": catalog_entry.get("model"),
            "reasoning": effort,
            "opts": role.get(runtime) or {},
            "profile": ppath,
        })

    if errors:
        for e in errors:
            sys.stderr.write("  schema error: %s\n" % e)
        die(2, "%s: %d problem(s)" % (where, len(errors)))
    return resolved


# --- rendering ----------------------------------------------------------------

def render_claude(role):
    """Claude Code agent definition: markdown with YAML frontmatter.

    No reasoning key is emitted: Claude Code does not document a per-agent
    reasoning setting, and inventing one would put an unknown key in the
    frontmatter. The capability matrix records this gap.
    """
    lines = ["---", "name: %s" % role["id"], "description: %s" % role["description"]]
    if role["model"]:
        lines.append("model: %s" % role["model"])
    tools = role["opts"].get("tools")
    if tools:
        lines.append("tools: %s" % ", ".join(tools))
    lines.append("---")
    lines.append("")
    lines.append("<!-- generated from %s by scripts/routing/render.py — do not edit here -->" %
                 os.path.basename(role["profile"]))
    lines.append("")
    return "\n".join(lines) + "\n" + role["instructions"]


def toml_str(value):
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % escaped


def render_codex(role):
    """Codex agent definition: one standalone TOML file per agent."""
    out = [
        "# generated from %s by scripts/routing/render.py — do not edit here" %
        os.path.basename(role["profile"]),
        "name = %s" % toml_str(role["id"]),
        "description = %s" % toml_str(role["description"]),
    ]
    if role["model"]:
        out.append("model = %s" % toml_str(role["model"]))
    if role["reasoning"]:
        out.append("model_reasoning_effort = %s" % toml_str(role["reasoning"]))
    sandbox = role["opts"].get("sandbox_mode")
    if sandbox:
        out.append("sandbox_mode = %s" % toml_str(sandbox))
    body = role["instructions"].replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    out.append('developer_instructions = """')
    out.append(body.rstrip("\n"))
    out.append('"""')
    return "\n".join(out) + "\n"


RENDERERS = {"claude": ("agents", ".md", render_claude),
             "codex": ("agents", ".toml", render_codex)}


# --- manifest -----------------------------------------------------------------

def manifest_path(target):
    return os.path.join(target, ".agent-skills", "routing-manifest.tsv")


def read_manifest(target):
    path = manifest_path(target)
    owned = {}
    if os.path.isfile(path):
        for line in read_text(path).splitlines():
            if not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) == 2:
                owned[parts[0]] = parts[1]
    return owned


def write_manifest(target, entries):
    path = manifest_path(target)
    body = "".join("%s\t%s\n" % (p, h) for p, h in sorted(entries.items()))
    write_text(path, body)


# --- main ---------------------------------------------------------------------

def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runtime", required=True, choices=sorted(RENDERERS))
    ap.add_argument("--target", required=True,
                    help="runtime config directory (e.g. ~/.claude, ~/.codex)")
    ap.add_argument("--config", default=None,
                    help="routing file (default: config/routing/models.yaml)")
    ap.add_argument("--apply", action="store_true", help="write; default is a dry run")
    ap.add_argument("--check", action="store_true", help="verify an existing render")
    ap.add_argument("--remove", action="store_true", help="remove what this renderer owns")
    args = ap.parse_args(argv)

    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    cfg_path = args.config or os.path.join(repo, "config", "routing", "models.yaml")
    target = os.path.expanduser(args.target)
    subdir, ext, renderer = RENDERERS[args.runtime]
    outdir = os.path.join(target, subdir)
    owned = read_manifest(target)

    print("runtime:  %s" % args.runtime)
    print("config:   %s" % cfg_path)
    print("target:   %s" % outdir)
    mode = "apply" if args.apply else "dry run"
    if args.check:
        mode = "check"
    elif args.remove:
        mode = "remove (%s)" % ("apply" if args.apply else "dry run")
    print("mode:     %s" % mode)
    print("")

    # --- remove ---------------------------------------------------------------
    if args.remove:
        removed = kept = 0
        remaining = dict(owned)
        for path, digest in sorted(owned.items()):
            if not os.path.exists(path):
                remaining.pop(path, None)
                continue
            if sha256(path) != digest:
                print("  KEPT (modified since render) %s" % path)
                kept += 1
                continue
            print("  REMOVE   %s" % path)
            if args.apply:
                os.remove(path)
                remaining.pop(path, None)
            removed += 1
        if args.apply:
            write_manifest(target, remaining)
        print("")
        print("%d file(s) removed, %d kept." % (removed, kept))
        return 0

    if not os.path.isfile(cfg_path):
        print("No routing file at %s — routing is optional and nothing is rendered." % cfg_path)
        print("Copy config/routing/models.example.yaml to models.yaml to enable it.")
        return 0

    roles = validate(load_yaml(read_text(cfg_path), cfg_path), cfg_path, args.runtime)
    if not roles:
        print("The routing file declares no roles, so there is nothing to render.")
        print("This is the expected state until canonical role profiles exist.")
        return 0

    # --- check ----------------------------------------------------------------
    if args.check:
        problems = 0
        for role in roles:
            path = os.path.join(outdir, role["id"] + ext)
            if not os.path.isfile(path):
                print("  FAIL  %s not rendered" % path)
                problems += 1
                continue
            if read_text(path) != renderer(role):
                print("  FAIL  %s is stale — re-run without --check" % path)
                problems += 1
                continue
            if path not in owned:
                print("  FAIL  %s is not in the routing manifest" % path)
                problems += 1
                continue
            print("  ok    %s" % path)
        print("")
        print("ROUTING CHECK: %s" % ("PASS" if problems == 0 else "FAIL (%d)" % problems))
        return 0 if problems == 0 else 1

    # --- render ---------------------------------------------------------------
    collisions = written = unchanged = 0
    entries = dict(owned)
    for role in roles:
        path = os.path.join(outdir, role["id"] + ext)
        content = renderer(role)
        if os.path.exists(path) and path not in owned:
            print("  COLLISION %s exists and is not ours — not overwriting" % path)
            collisions += 1
            continue
        if os.path.exists(path) and read_text(path) == content:
            print("  ok        %s (unchanged)" % path)
            unchanged += 1
            entries[path] = sha256(path)
            continue
        print("  %s %s -> model=%s reasoning=%s" % (
            "WRITE    " if not os.path.exists(path) else "UPDATE   ",
            path, role["model"], role["reasoning"]))
        written += 1
        if args.apply:
            write_text(path, content)
            entries[path] = sha256(path)

    if args.apply:
        write_manifest(target, entries)

    print("")
    print("%d written, %d unchanged, %d collision(s)." % (written, unchanged, collisions))
    if collisions:
        sys.stderr.write("Nothing was overwritten. Move or delete the colliding file(s) first.\n")
        return 1
    if not args.apply:
        print("Nothing written. Re-run with --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
