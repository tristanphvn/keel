#!/usr/bin/env python3
"""Render canonical role profiles into runtime-native agent definitions.

    python3 scripts/routing/render.py --runtime claude --target ~/.claude
    python3 scripts/routing/render.py --runtime codex  --target ~/.codex --apply
    python3 scripts/routing/render.py --runtime claude --target ~/.claude --check
    python3 scripts/routing/render.py --runtime claude --target ~/.claude --remove --apply

Source of truth
---------------
`roles/catalog.json` and the `roles/<id>.json` profiles it references, against
agent-work contract **0.3.0**. This renderer holds no second role source: it
authors no purpose, no responsibility and no instruction text. Everything in a
generated file is either copied from a canonical artifact or is adapter-owned
routing configuration.

Generated files are build outputs. Each one records the canonical source path,
its sha256 and the distribution revision, so any line can be traced back.

Adapter-owned configuration
---------------------------
`config/routing/models.yaml` binds the contract's logical model policies
(`default`, `escalated`) to concrete provider/model identifiers per runtime, and
carries per-role runtime options (tool restrictions, sandbox mode). A policy that
does not resolve for the target runtime is a configuration error — never a
guessed model name.

Skill delivery
--------------
A role's `skill_refs` must reach the executing agent. Two mechanisms:

  reference  the agent loads the skill itself through its Skill tool
  preload    the canonical skill bodies are embedded in the generated
             instructions, with provenance

`preload` exists because restricting an agent's tools removes its Skill tool, and
with it every skill — measured on Claude Code 2.1.220. Preloading delivers the
instructions without widening permissions. Selected automatically from the role's
configured tool restriction; override with `skill_delivery` in the routing file.

Exit codes: 0 ok · 1 collision or write failure · 2 contract/config error
"""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys

CONTRACT_VERSION = "0.3.0"
# The contract's permission classes. Tool NAMES stay adapter-owned; these are
# the runtime-independent classes the contract itself defines.
PERMISSION_CLASSES = ["read", "write", "execute", "network", "delegate"]

# --- YAML ---------------------------------------------------------------------
# PyYAML when present; otherwise a parser for the restricted subset the routing
# file is specified in (documented in docs/routing.md). The contract itself is
# JSON and never depends on this.

try:
    import yaml  # type: ignore

    def load_yaml(text, where):
        try:
            return yaml.safe_load(text) or {}
        except Exception as exc:  # pragma: no cover - host dependent
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
                out[key] = self._block(nxt[0]) if (nxt is not None and nxt[0] > ind) else None
            else:
                out[key] = self._scalar(val, lineno)

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
                    entry.update(self._mapping(nxt[0]))
                out.append(entry)
            else:
                out.append(self._scalar(body, lineno))

    def _scalar(self, val, lineno):
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            return [] if not inner else [self._scalar(p.strip(), lineno) for p in inner.split(",")]
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


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    with open(path, "rb") as fh:
        return sha256_bytes(fh.read())


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


def revision_of(root):
    """The distribution revision, for provenance. Never fatal."""
    try:
        out = subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"],
                                      stderr=subprocess.DEVNULL)
        rev = out.decode("ascii").strip()
    except Exception:
        return "unversioned"
    try:
        dirty = subprocess.check_output(["git", "-C", root, "status", "--porcelain"],
                                        stderr=subprocess.DEVNULL).decode("utf-8").strip()
    except Exception:
        dirty = ""
    return rev + ("+dirty" if dirty else "")


# --- reference resolution -----------------------------------------------------
# The contract requires every reference to resolve inside one pinned root, with
# real paths checked so a symlink cannot lead outside it.

BAD_REF = re.compile(r"^(/|[A-Za-z]:)|(^|/)\.\.(/|$)|\\")


def resolve_ref(root, ref, where):
    if not isinstance(ref, str) or not ref:
        die(2, "%s: reference must be a non-empty string" % where)
    if BAD_REF.search(ref):
        die(2, "%s: reference %r must be repository-relative with no traversal, "
               "drive letter or backslash" % (where, ref))
    real_root = os.path.realpath(root)
    path = os.path.realpath(os.path.join(root, ref))
    if path != real_root and not path.startswith(real_root + os.sep):
        die(2, "%s: reference %r resolves outside the distribution root (%s)"
               % (where, ref, path))
    if not os.path.isfile(path):
        die(2, "%s: reference %r does not exist" % (where, ref))
    return path


def load_contract_json(path, expected_kind):
    try:
        data = json.loads(read_text(path))
    except ValueError as exc:
        die(2, "%s: invalid JSON: %s" % (path, exc))
    if not isinstance(data, dict):
        die(2, "%s: top level must be an object" % path)
    version = data.get("contract_version")
    if version != CONTRACT_VERSION:
        die(2, "%s: contract_version %r is not supported; this renderer implements "
               "%s exactly and will not reinterpret another version"
               % (path, version, CONTRACT_VERSION))
    if data.get("kind") != expected_kind:
        die(2, "%s: kind %r, expected %r" % (path, data.get("kind"), expected_kind))
    return data


ROLE_REQUIRED = ["id", "purpose", "responsibilities", "boundaries", "inputs", "outputs",
                 "completion_criteria", "skill_refs", "model_policy_ref",
                 "required_capabilities", "optional_capabilities", "permission_ceiling"]


def load_catalog(root, catalog_ref):
    path = resolve_ref(root, catalog_ref, "catalog")
    cat = load_contract_json(path, "catalog")
    for key in ("rule_refs", "role_refs", "model_policy_refs", "default_limits"):
        if key not in cat:
            die(2, "%s: catalog is missing %r" % (path, key))
    for ref in cat["rule_refs"]:
        resolve_ref(root, ref, "catalog rule_refs")
    return cat


def load_roles(root, catalog):
    roles = []
    seen = set()
    for ref in catalog["role_refs"]:
        path = resolve_ref(root, ref, "catalog role_refs")
        role = load_contract_json(path, "role")
        for key in ROLE_REQUIRED:
            if key not in role:
                die(2, "%s: role is missing required field %r" % (path, key))
        rid = role["id"]
        if rid in seen:
            die(2, "%s: duplicate role id %r" % (path, rid))
        seen.add(rid)
        if role["model_policy_ref"] not in catalog["model_policy_refs"]:
            die(2, "%s: model_policy_ref %r is not declared in the catalog"
                   % (path, role["model_policy_ref"]))
        if not role["skill_refs"]:
            die(2, "%s: role declares no skill_refs" % path)
        role["_path"] = path
        role["_ref"] = ref
        role["_skills"] = []
        for sref in role["skill_refs"]:
            spath = resolve_ref(root, sref, "%s skill_refs" % rid)
            role["_skills"].append({"ref": sref, "path": spath, "sha256": sha256_file(spath)})
        roles.append(role)
    return roles


# --- adapter-owned routing configuration --------------------------------------

def load_routing(cfg_path, runtime, catalog):
    """Bind logical policies to concrete models. Never invents one."""
    if not os.path.isfile(cfg_path):
        die(2, "no routing configuration at %s. The contract defines logical policies "
               "(%s) but no model names; the adapter must bind them. Copy "
               "config/routing/models.example.yaml to models.yaml."
               % (cfg_path, ", ".join(catalog["model_policy_refs"])))
    cfg = load_yaml(read_text(cfg_path), cfg_path)
    if not isinstance(cfg, dict):
        die(2, "%s: top level must be a mapping" % cfg_path)
    if cfg.get("version") != 3:
        die(2, "%s: version must be 3 (got %r). Version 3 replaced per-role `tools`"
               " lists with a permission-class `tool_map`; see docs/routing.md."
               % (cfg_path, cfg.get("version")))

    # A per-role tool list invented by the adapter is behavioural policy: removing
    # an execute tool can turn a role's result from completed into blocked. Under
    # version 3 restrictions are derived from the role's declared
    # `required_permissions` through this map, and an adapter-declared exception
    # has to say so out loud (`tools_override` + `justification`).
    tool_map = (cfg.get("tool_map") or {}).get(runtime)
    if tool_map is not None and not isinstance(tool_map, dict):
        die(2, "%s: tool_map.%s must be a mapping of permission class to tool names"
               % (cfg_path, runtime))
    for entry in ((cfg.get("roles") or {}).items()):
        rid, spec = entry
        spec = spec or {}
        per = spec.get(runtime) or {}
        if "tools" in per:
            die(2, "%s: role %r still uses `tools:`. Version 3 derives tool limits from "
                   "the role's required_permissions; use `tools_override` with a "
                   "`justification` if an adapter-declared exception is genuinely needed."
                   % (cfg_path, rid))
        if per.get("tools_override") is not None and not per.get("justification"):
            die(2, "%s: role %r sets tools_override without a justification. An "
                   "adapter-declared restriction must be visible, not silent."
                   % (cfg_path, rid))

    policies = cfg.get("policies") or {}
    errors = []
    for name in catalog["model_policy_refs"]:
        entry = policies.get(name)
        if entry is None:
            errors.append("policy %r is declared by the catalog but absent here" % name)
            continue
        per = entry.get(runtime)
        if not isinstance(per, dict) or not per.get("model"):
            errors.append("policy %r has no %s model binding" % (name, runtime))
    if errors:
        for e in errors:
            sys.stderr.write("  configuration error: %s\n" % e)
        die(2, "%s: %d unresolved model policy binding(s). An unresolved policy is a "
               "configuration error; no model is guessed." % (cfg_path, len(errors)))
    return cfg


def role_options(cfg, rid, runtime):
    entry = (cfg.get("roles") or {}).get(rid) or {}
    opts = entry.get(runtime) or {}
    return entry, opts


def classes_for_tools(tool_map, tools):
    """Which permission classes a tool list can satisfy, per the adapter's map.

    Used to check an operator override against the role's floor. A tool may span
    classes — a shell can write files and reach the network — so this says which
    classes are *covered*, never which effects are denied.
    """
    covered = set()
    for cls, names in (tool_map or {}).items():
        for name in names or []:
            if name in tools:
                covered.add(cls)
    return covered


def authorized_permissions(role, cfg, opts, entry):
    """The explicitly authorized permission classes for this role, or None.

    The floor is a minimum, not an authorization and not an allowlist: a review
    role with a `read` floor may be authorized to write its report. So the
    authorized set is supplied by the operator — per role, or as a default for
    the run — and is then checked against floor and ceiling. Nothing is inferred
    from the floor alone.
    """
    for source in (opts.get("permissions"), entry.get("permissions"),
                   cfg.get("default_authorized_permissions")):
        if source is not None:
            return list(source)
    return None


def effective_tools(role, cfg, rid, runtime):
    """(tools, origin, note) for a role.

    tools is None only for a template: a file explicitly marked non-executable.
    Otherwise it is a concrete list, possibly empty.

    Origins, all distinguishable in the generated file:

      authorized  derived from an explicit authorized permission set through the
                  adapter's tool_map. The floor is checked as a minimum and the
                  ceiling as a bound; the set may sit anywhere between them.
      adapter     an explicit tools_override. Still checked against the floor —
                  a justification does not exempt an override from the contract.
      template    no authorization context was supplied, so no executable
                  configuration is produced. The contract allows a template; it
                  does not allow claiming an authorized, restricted execution
                  from a profile alone, and an agent file with no tool limit
                  inherits whatever the parent has.
    """
    entry, opts = role_options(cfg, rid, runtime)
    floor = set(role.get("required_permissions") or [])
    ceiling = set(role.get("permission_ceiling") or [])
    tool_map = (cfg.get("tool_map") or {}).get(runtime) or {}

    # `tools_override` present but empty is a decision, not an absence: it means
    # no tools. Previously an empty list was falsy and fell through to inherited
    # or floor-derived tools — the opposite of what the operator wrote.
    if "tools_override" in opts:
        override = opts.get("tools_override")
        if not isinstance(override, list):
            die(2, "role %s: tools_override must be a list (use [] for no tools)" % role["id"])
        if not override:
            # An empty allowlist must mean no tools. Whether this runtime
            # represents that is unmeasured here, so the renderer refuses rather
            # than emitting something whose meaning it cannot state.
            die(2, "role %s: tools_override is explicitly empty, which means NO tools. "
                   "Whether %s represents an empty tool list as 'no tools' rather than "
                   "'unrestricted' has not been measured in this repository, so the "
                   "renderer will not emit it. Measure it and record the evidence, or "
                   "remove the override. It is never treated as inherited tools."
                   % (role["id"], runtime))
        if floor and not tool_map:
            die(2, "role %s: tools_override cannot be checked against the role's floor "
                   "because the %s tool_map is empty, so which classes those tools cover "
                   "is unknown. Declare the map, or do not override."
                   % (role["id"], runtime))
        covered = classes_for_tools(tool_map, override)
        unmet = sorted(floor - covered)
        if unmet:
            die(2, "role %s: tools_override does not cover its required permission "
                   "class(es) %s. An override is subject to the same floor as anything "
                   "else, justified or not."
                   % (role["id"], ", ".join(unmet)))
        return list(override), "adapter", opts.get("justification", "")

    granted = authorized_permissions(role, cfg, opts, entry)
    if granted is None:
        return None, "template", ""

    granted_set = set(granted)
    unknown = sorted(granted_set - set(PERMISSION_CLASSES))
    if unknown:
        die(2, "role %s: unknown permission class(es) %s" % (role["id"], ", ".join(unknown)))

    # floor <= authorized <= ceiling, the same inequality the contract states.
    unmet = sorted(floor - granted_set)
    if unmet:
        die(2, "role %s: the authorized permissions %s do not meet its floor; %s missing. "
               "A role cannot discharge its responsibility below its floor — grant them "
               "or do not dispatch this role."
               % (role["id"], ", ".join(sorted(granted_set)) or "(none)", ", ".join(unmet)))
    excess = sorted(granted_set - ceiling)
    if excess:
        die(2, "role %s: the authorized permissions exceed its ceiling by %s. The ceiling "
               "is a bound on what the role may ever be granted."
               % (role["id"], ", ".join(excess)))

    missing = [c for c in sorted(granted_set) if not tool_map.get(c)]
    if missing:
        die(2, "role %s is authorized for permission class(es) %s, which the %s tool_map "
               "does not map to any tool. An unmapped class is a configuration error; the "
               "renderer will not silently drop an authorized permission."
               % (role["id"], ", ".join(missing), runtime))

    tools = []
    for cls in granted:
        for name in tool_map[cls]:
            if name not in tools:
                tools.append(name)
    return tools, "authorized", ",".join(sorted(granted_set))


# --- instruction body ---------------------------------------------------------

def bullets(items):
    return "".join("- %s\n" % i for i in items)


def execution_instructions(role, catalog, delivery, skills_inline, root_hint):
    """The behavioural half of a generated agent, copied from the contract.

    Every contract field that constrains behaviour is carried through:
    responsibilities, boundaries, inputs, outputs and completion criteria. The
    renderer adds no requirement of its own.
    """
    out = []
    out.append("# Role: %s\n" % role["id"])
    out.append("\n%s\n" % role["purpose"])
    out.append("\n## Responsibilities\n\n%s" % bullets(role["responsibilities"]))
    out.append("\n## Boundaries\n\n%s" % bullets(role["boundaries"]))
    out.append("\n## Inputs\n\n%s" % bullets(role["inputs"]))
    out.append("\n## Outputs\n\n%s" % bullets(role["outputs"]))
    out.append("\n## Completion criteria\n\nThe work is complete only when all of these hold.\n\n%s"
               % bullets(role["completion_criteria"]))

    caps = []
    if role["required_capabilities"]:
        caps.append("Required: %s" % ", ".join(role["required_capabilities"]))
    if role["optional_capabilities"]:
        caps.append("Optional: %s" % ", ".join(role["optional_capabilities"]))
    out.append("\n## Capabilities and permissions\n\n")
    if caps:
        out.append(bullets(caps))
    out.append("- Permission ceiling: %s\n" % ", ".join(role["permission_ceiling"]))
    out.append("\nThe ceiling is an upper bound, not a grant. A capability this runtime does not\n"
               "actually provide counts as unavailable: report it and stop rather than simulating it.\n")

    out.append("\n## Canonical skills\n\n")
    if delivery == "preload":
        out.append("The skill instructions below are delivered inline because this agent's tool\n"
                   "restriction removes its Skill tool. They are copies of the canonical files —\n"
                   "the sources named below remain authoritative.\n\n")
    else:
        out.append("Load each of these before acting. They are canonical sources; the paths are\n"
                   "repository-relative to the installed distribution%s.\n\n" % root_hint)
    for s in role["_skills"]:
        out.append("- `%s` (sha256 %s)\n" % (s["ref"], s["sha256"][:16]))

    if delivery == "preload":
        for s in skills_inline:
            out.append("\n---\n\n")
            out.append("<!-- begin canonical skill: %s sha256=%s -->\n\n" % (s["ref"], s["sha256"]))
            out.append(s["body"].rstrip() + "\n")
            out.append("\n<!-- end canonical skill: %s -->\n" % s["ref"])
    return "".join(out)


def load_skill_bodies(role):
    out = []
    for s in role["_skills"]:
        out.append({"ref": s["ref"], "sha256": s["sha256"], "body": read_text(s["path"])})
    return out


def describe_tool_origin(origin, note):
    """Say where a tool limit came from, so adapter policy is never mistaken for
    something the contract required, and an unauthorized template is never
    mistaken for a restricted execution."""
    if origin == "authorized":
        return "derived from the authorized permissions [%s]" % note
    if origin == "adapter":
        return "ADAPTER-DECLARED override - %s" % (note or "no justification given")
    return ("NONE - no authorized permission set was supplied, so this file is a "
            "template and carries no tool limit")


def decide_delivery(role, entry, tools, runtime):
    """reference | preload, and why.

    Measured on Claude Code 2.1.220: a sub-agent given an explicit `tools` list
    without `Skill` has no Skill tool and sees no skills at all, and a control
    run with `reference` delivery confirmed such a child receives nothing.
    Preloading is how a restricted role still receives its required
    instructions, without widening its permissions, which the contract forbids.
    """
    explicit = entry.get("skill_delivery")
    if explicit in ("reference", "preload"):
        return explicit, "configured explicitly"
    if runtime == "claude":
        if tools is not None and "Skill" not in tools:
            return "preload", "tool restriction excludes the Skill tool"
        return "reference", "agent retains its Skill tool"
    # Codex: skills load from its own skills path; that is unverified here, and a
    # sandboxed agent's access to them is not documented. Default to reference,
    # and let the routing file force preload where an operator needs certainty.
    return "reference", "Codex skill discovery is documented, not measured"


# --- renderers ----------------------------------------------------------------

def render_claude(role, catalog, cfg, revision):
    entry, opts = role_options(cfg, role["id"], "claude")
    policy = role["model_policy_ref"]
    model = cfg["policies"][policy]["claude"]["model"]
    tools, origin, justification = effective_tools(role, cfg, role["id"], "claude")
    delivery, why = decide_delivery(role, entry, tools, "claude")
    skills_inline = load_skill_bodies(role) if delivery == "preload" else []

    head = ["---", "name: %s" % role["id"],
            "description: %s" % role["purpose"].replace("\n", " ")]
    if model:
        head.append("model: %s" % model)
    if tools:
        head.append("tools: %s" % ", ".join(tools))
    head.append("---")
    head.append("")
    head.append("<!-- generated by scripts/routing/render.py — do not edit here -->")
    head.append("<!-- source: %s · contract %s · revision %s -->" %
                (role["_ref"], CONTRACT_VERSION, revision))
    head.append("<!-- model policy: %s -> %s · skill delivery: %s (%s) -->" %
                (policy, model, delivery, why))
    head.append("<!-- tool limit: %s -->" % describe_tool_origin(origin, justification))
    if origin == "template":
        head.append("<!-- NON-EXECUTABLE TEMPLATE: no authorized permission set was supplied, "
                    "so this agent has no tool limit and would inherit the parent's tools. "
                    "Do not dispatch it. Supply authorized permissions to render an "
                    "executable configuration. -->")
    head.append("")
    return "\n".join(head) + "\n" + execution_instructions(
        role, catalog, delivery, skills_inline, "")


def toml_str(value):
    return '"%s"' % str(value).replace("\\", "\\\\").replace('"', '\\"')


def render_codex(role, catalog, cfg, revision):
    entry, opts = role_options(cfg, role["id"], "codex")
    policy = role["model_policy_ref"]
    binding = cfg["policies"][policy]["codex"]
    tools, origin, justification = effective_tools(role, cfg, role["id"], "codex")
    delivery, why = decide_delivery(role, entry, tools, "codex")
    skills_inline = load_skill_bodies(role) if delivery == "preload" else []

    body = execution_instructions(role, catalog, delivery, skills_inline, "")
    out = [
        "# generated by scripts/routing/render.py — do not edit here",
        "# source: %s · contract %s · revision %s" % (role["_ref"], CONTRACT_VERSION, revision),
        "# model policy: %s · skill delivery: %s (%s)" % (policy, delivery, why),
        "# tool limit: %s" % describe_tool_origin(origin, justification),
    ]
    if origin == "template":
        out.append("# NON-EXECUTABLE TEMPLATE: no authorized permission set was supplied, so")
        out.append("# this agent carries no tool limit and would inherit. Do not dispatch it.")
    out += [
        "name = %s" % toml_str(role["id"]),
        "description = %s" % toml_str(role["purpose"].replace("\n", " ")),
        "model = %s" % toml_str(binding["model"]),
    ]
    if binding.get("reasoning"):
        out.append("model_reasoning_effort = %s" % toml_str(binding["reasoning"]))
    if opts.get("sandbox_mode"):
        out.append("sandbox_mode = %s" % toml_str(opts["sandbox_mode"]))
    escaped = body.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    out.append('developer_instructions = """')
    out.append(escaped.rstrip("\n"))
    out.append('"""')
    return "\n".join(out) + "\n"


RENDERERS = {"claude": (".md", render_claude), "codex": (".toml", render_codex)}


# --- runtime capability gate --------------------------------------------------
# Roles state what they require; a capability record states what a runtime was
# measured to prove. The renderer matches the two and refuses when the evidence
# does not reach the level the capability demands. It never decides either side.

RUNTIME_FAMILY = {"claude": "claude-code", "codex": "codex"}


def canonical_capability_validator(repo_root):
    """Import the canonical capability validator, so this path cannot drift."""
    path = os.path.join(repo_root, "scripts", "capabilities", "validate.py")
    spec = importlib.util.spec_from_file_location("agent_skills_capability_validate", path)
    if spec is None or spec.loader is None:
        die(2, "cannot load the canonical capability validator at %s" % path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_capability_record(path, repo_root):
    """Load a record only after it passes canonical validation.

    A label is not evidence. Before this, the renderer read `state: enforced` and
    believed it — a record with its evidence array emptied still authorised a
    role that required enforcement. The record now goes through the same schema
    and semantic checks the capability validator applies, including evidence
    presence and kind, probe containment, existence and digest.

    Validation is not measurement: passing here says the record is well-formed
    and internally consistent, not that the runtime still behaves that way.
    """
    rec = load_json_file(path)
    if rec.get("record_version") != 2:
        die(2, "%s: record_version %r is not supported; this renderer implements 2 exactly"
               % (path, rec.get("record_version")))

    validator = canonical_capability_validator(repo_root)
    ok, problems = validator.validate_record_file(repo_root, path)
    if not ok:
        for problem in problems[:8]:
            sys.stderr.write("  invalid record: %s\n" % problem)
        die(2, "%s did not pass canonical capability validation, so it authorises nothing. "
               "Nothing was written." % path)

    rec["_path"] = path
    rec["_requirements"] = evidence_requirements(repo_root)
    return rec


def evidence_requirements(repo_root):
    """Required evidence level per capability, read from the record schema.

    One definition, shared with scripts/capabilities/validate.py. A copy here
    would be a second source of truth for what `enforced` means.
    """
    schema = load_json_file(os.path.join(repo_root, "capabilities",
                                         "runtime-capability.schema.json"))
    return schema["$defs"]["evidence_requirements"]["const"]


def load_json_file(path):
    try:
        return json.loads(read_text(path))
    except ValueError as exc:
        die(2, "%s: invalid JSON: %s" % (path, exc))
    except IOError as exc:
        die(2, "%s: cannot read: %s" % (path, exc))


def capability_verdict(record, capability):
    """(satisfied, explanation) for one capability against one record."""
    if record is None:
        return False, "no capability record was supplied for this runtime"
    if record["status"] != "measured":
        return False, ("record %s is a %s, not a measurement"
                       % (os.path.basename(record["_path"]), record["status"]))

    entry = (record.get("capabilities") or {}).get(capability)
    if entry is None:
        return False, "absent from the record — unknown, and unknown fails closed"

    state = entry.get("state")
    required = record["_requirements"].get(capability, "enforcement")

    if state == "enforced":
        return True, "enforced"
    if state == "observed":
        if required == "observation":
            return True, "observed"
        return False, ("observed but not proven enforced, and %s requires enforcement "
                       "— model compliance is not runtime enforcement" % capability)
    if state == "unavailable":
        return False, "measured as unavailable on this runtime"
    if state == "unmeasured":
        return False, "unmeasured: %s" % (entry.get("reason") or "no reason recorded")
    if state == "documented":
        return False, ("documented only (%s) — documentation is not an observation"
                       % (entry.get("source") or "no source recorded"))
    return False, "unrecognised state %r" % state


def check_capabilities(roles, record, runtime, version, platform):
    """Every role's required capabilities, against the record. Returns failures.

    Runs before anything is written, so a refusal leaves the target untouched.
    """
    failures = []

    needs_evidence = any(role.get("required_capabilities") for role in roles)

    if record is not None:
        family = RUNTIME_FAMILY[runtime]
        if record["runtime"].get("family") != family:
            die(2, "%s: record is for runtime family %r, but rendering %r. A record proves "
                   "nothing about another runtime."
                   % (record["_path"], record["runtime"].get("family"), family))

        # An optional match flag cannot establish compatibility with a target
        # nobody named. When a record is what permits an evidence-dependent
        # render, the target it is being matched against has to be stated.
        if needs_evidence and (version is None or platform is None):
            die(2, "a role requires a capability, so the target runtime must be identified: "
                   "pass --runtime-version and --platform. %s measures %s %s on %s; without a "
                   "stated target there is nothing to compare it against."
                   % (record["_path"], record["runtime"].get("family"),
                      record["runtime"].get("version"), record["platform"].get("os")))

        if version is not None and record["runtime"].get("version") != version:
            die(2, "%s: record measures version %r, but --runtime-version says %r. A "
                   "measurement of one version does not carry to another."
                   % (record["_path"], record["runtime"].get("version"), version))
        if platform is not None and record["platform"].get("os") != platform:
            die(2, "%s: record measures platform %r, but --platform says %r. Evidence from "
                   "one platform does not certify another."
                   % (record["_path"], record["platform"].get("os"), platform))

    for role in roles:
        required = role.get("required_capabilities") or []
        for capability in required:
            ok, why = capability_verdict(record, capability)
            if not ok:
                failures.append((role["id"], capability, why))
    return failures


def delivery_record(roles, cfg, runtime, revision):
    """What this render delivered, per role, for a result's `delivered_skills`.

    The contract lets a result record which skill bodies the adapter placed in,
    or made available to, the executing context. Only the adapter knows that, so
    the adapter writes it down here. It is a delivery claim and nothing more:
    `preload` means the body was embedded in the generated instructions,
    `reference` means it was named and left to be loaded. Neither says the
    instructions were read, and no field in the contract claims that.
    """
    out = {"contract_version": CONTRACT_VERSION, "runtime": runtime,
           "profile_revision": revision, "roles": {}}
    for role in roles:
        entry, opts = role_options(cfg, role["id"], runtime)
        tools, _origin, _just = effective_tools(role, cfg, role["id"], runtime)
        delivery, _why = decide_delivery(role, entry, tools, runtime)
        out["roles"][role["id"]] = [
            {"ref": s["ref"], "sha256": s["sha256"], "method": delivery}
            for s in role["_skills"]
        ]
    return json.dumps(out, indent=2, sort_keys=True) + "\n"

# Codex reads the instruction chain up to project_doc_max_bytes (32 KiB default).
# An agent definition is a separate file, but a preloaded role can still grow
# past any sane per-file expectation, so the budget is checked and never
# silently exceeded.
DEFAULT_BUDGET = {"codex": 32768, "claude": 0}  # 0 = no documented limit


# --- manifest -----------------------------------------------------------------

def manifest_path(target):
    return os.path.join(target, ".agent-skills", "routing-manifest.tsv")


def read_manifest(target):
    path = manifest_path(target)
    owned = {}
    if os.path.isfile(path):
        for line in read_text(path).splitlines():
            parts = line.split("\t")
            if len(parts) == 2:
                owned[parts[0]] = parts[1]
    return owned


def write_manifest(target, entries):
    write_text(manifest_path(target),
               "".join("%s\t%s\n" % (p, h) for p, h in sorted(entries.items())))


# --- main ---------------------------------------------------------------------

def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runtime", required=True, choices=sorted(RENDERERS))
    ap.add_argument("--target", required=True, help="runtime config directory")
    ap.add_argument("--root", default=None, help="pinned distribution root (default: this repo)")
    ap.add_argument("--catalog", default="roles/catalog.json", help="root-relative catalog path")
    ap.add_argument("--config", default=None, help="routing file (default: config/routing/models.yaml)")
    ap.add_argument("--budget", type=int, default=None, help="per-file instruction budget in bytes")
    ap.add_argument("--capabilities", default=None,
                    help="runtime capability record for the target runtime. Required only "
                         "when a role declares required_capabilities; without it such a "
                         "role is refused rather than rendered.")
    ap.add_argument("--runtime-version", default=None,
                    help="version the record must have measured; mismatch is refused")
    ap.add_argument("--platform", default=None, choices=["windows", "linux", "darwin"],
                    help="platform the record must have measured; mismatch is refused")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--remove", action="store_true")
    args = ap.parse_args(argv)

    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    root = os.path.abspath(os.path.expanduser(args.root)) if args.root else repo
    cfg_path = args.config or os.path.join(repo, "config", "routing", "models.yaml")
    target = os.path.expanduser(args.target)
    ext, renderer = RENDERERS[args.runtime]
    outdir = os.path.join(target, "agents")
    owned = read_manifest(target)
    budget = args.budget if args.budget is not None else DEFAULT_BUDGET[args.runtime]

    mode = "check" if args.check else ("remove" if args.remove else "render")
    print("runtime:  %s" % args.runtime)
    print("root:     %s" % root)
    print("target:   %s" % outdir)
    print("mode:     %s%s" % (mode, "" if args.check else (" (apply)" if args.apply else " (dry run)")))
    print("")

    # --- remove ---------------------------------------------------------------
    if args.remove:
        removed = kept = 0
        remaining = dict(owned)
        for path, digest in sorted(owned.items()):
            if not os.path.exists(path):
                remaining.pop(path, None)
                continue
            if sha256_file(path) != digest:
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
        print("\n%d file(s) removed, %d kept." % (removed, kept))
        return 0

    catalog = load_catalog(root, args.catalog)
    roles = load_roles(root, catalog)
    cfg = load_routing(cfg_path, args.runtime, catalog)
    revision = revision_of(root)
    print("contract: %s (%s), %d role(s), revision %s" %
          (CONTRACT_VERSION, catalog.get("status", "?"), len(roles), revision))
    print("")

    # --- capability gate, before a single byte is written ---------------------
    capability_record = None
    if args.capabilities:
        capability_record = load_capability_record(args.capabilities, repo)
        print("capabilities: %s (%s, %s %s, %s)" % (
            args.capabilities, capability_record["status"],
            capability_record["runtime"]["family"], capability_record["runtime"]["version"],
            capability_record["platform"]["os"]))

    cap_failures = check_capabilities(roles, capability_record, args.runtime,
                                      args.runtime_version, args.platform)
    if cap_failures:
        for rid, capability, why in cap_failures:
            sys.stderr.write("  refused: role %s requires %s — %s\n" % (rid, capability, why))
        die(2, "%d role(s) require a capability this runtime cannot prove. Nothing was "
               "written. A role runs only where its requirements are evidenced: supply a "
               "measured record, or measure the capability." % len(set(f[0] for f in cap_failures)))

    rendered = {}
    oversize = []
    for role in roles:
        content = renderer(role, catalog, cfg, revision)
        size = len(content.encode("utf-8"))
        if budget and size > budget:
            oversize.append((role["id"], size))
        rendered[role["id"]] = content

    if oversize:
        for rid, size in oversize:
            sys.stderr.write("  over budget: role %s renders %dB, limit %dB\n" % (rid, size, budget))
        die(2, "%d role(s) exceed the instruction budget. Required instructions are never "
               "truncated: raise the runtime's limit and pass --budget, or switch those roles "
               "to `skill_delivery: reference` in the routing file." % len(oversize))

    # --- check ----------------------------------------------------------------
    if args.check:
        problems = 0
        for rid, content in sorted(rendered.items()):
            path = os.path.join(outdir, rid + ext)
            if not os.path.isfile(path):
                print("  FAIL  %s not rendered" % path); problems += 1; continue
            if read_text(path) != content:
                print("  FAIL  %s is stale" % path); problems += 1; continue
            if path not in owned:
                print("  FAIL  %s is not in the routing manifest" % path); problems += 1; continue
            print("  ok    %s" % path)
        print("\nROUTING CHECK: %s" % ("PASS" if problems == 0 else "FAIL (%d)" % problems))
        return 0 if problems == 0 else 1

    # --- render ---------------------------------------------------------------
    collisions = written = unchanged = 0
    entries = dict(owned)
    for role in roles:
        rid = role["id"]
        path = os.path.join(outdir, rid + ext)
        content = rendered[rid]
        if os.path.exists(path) and path not in owned:
            print("  COLLISION %s exists and is not ours — not overwriting" % path)
            collisions += 1
            continue
        if os.path.exists(path) and read_text(path) == content:
            print("  ok        %s (unchanged)" % path)
            unchanged += 1
            entries[path] = sha256_file(path)
            continue
        policy = role["model_policy_ref"]
        model = cfg["policies"][policy][args.runtime]["model"]
        print("  %s %s  policy=%s model=%s %dB" % (
            "WRITE   " if not os.path.exists(path) else "UPDATE  ",
            rid + ext, policy, model, len(content.encode("utf-8"))))
        written += 1
        if args.apply:
            write_text(path, content)
            entries[path] = sha256_file(path)

    # The delivery record is written only when the render itself succeeded: a
    # record of what was delivered must never outlive a run that delivered
    # nothing.
    if args.apply and not collisions:
        record_path = os.path.join(target, ".agent-skills",
                                   "delivered-skills-%s.json" % args.runtime)
        write_text(record_path, delivery_record(roles, cfg, args.runtime, revision))
        entries[record_path] = sha256_file(record_path)
        print("  record    %s" % record_path)

    if args.apply:
        write_manifest(target, entries)

    print("\n%d written, %d unchanged, %d collision(s)." % (written, unchanged, collisions))
    if collisions:
        sys.stderr.write("Nothing was overwritten. Move or delete the colliding file(s) first.\n")
        return 1
    if not args.apply:
        print("Nothing written. Re-run with --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
