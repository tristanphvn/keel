#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile, time, unittest

GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lead-gate.py")
LEAD_SKILL = "/home/u/.claude/plugins/cache/keel/keel/0.9.0/skills/lead/SKILL.md"
SESSION = "s-1"


class LeadGate(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.env = dict(os.environ, CLAUDE_CONFIG_DIR=self.home.name)
        self.env.pop("KEEL_LEAD_GATE", None)
        self.env.pop("CLAUDE_PLUGIN_ROOT", None)
        self.markers = os.path.join(self.home.name, ".keel-lead-gate")

    def tearDown(self):
        self.home.cleanup()

    def run_hook(self, mode, payload, **env):
        result = subprocess.run(
            [sys.executable, GATE, mode], input=json.dumps(payload).encode("utf-8"),
            capture_output=True, env=dict(self.env, **env), check=True,
        )
        return result.stdout.decode("utf-8").strip()

    def decision(self, tool, session=SESSION, **tool_input):
        out = self.run_hook("gate", {"session_id": session, "tool_name": tool, "tool_input": tool_input})
        return json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def test_denies_every_workspace_tool_before_the_lead_loads(self):
        for tool, args in [
            ("Bash", {"command": "ls"}), ("Read", {"file_path": "/repo/a.ts"}), ("Grep", {"pattern": "x"}),
            ("Edit", {"file_path": "/repo/a.md"}), ("Write", {"file_path": "/repo/a.json"}),
            ("Agent", {"prompt": "x"}), ("mcp__linear__get_issue", {"id": "X-1"}),
        ]:
            self.assertEqual(self.decision(tool, **args), "deny", tool)

    def test_allows_the_tools_that_load_the_lead_or_cannot_touch_the_workspace(self):
        self.assertEqual(self.decision("Skill", skill="keel:help"), "allow")
        self.assertEqual(self.decision("ToolSearch", query="select:Read"), "allow")
        self.assertEqual(self.decision("AskUserQuestion", questions=[]), "allow")
        self.assertEqual(self.decision("Read", file_path=LEAD_SKILL), "allow")
        self.assertEqual(self.decision("Read", file_path=LEAD_SKILL.replace("/", "\\")), "allow")

    def test_loading_the_lead_skill_opens_the_gate_for_that_session_only(self):
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Skill", "tool_input": {"skill": "keel:lead"}})
        self.assertEqual(self.decision("Bash", command="ls"), "allow")
        self.assertEqual(self.decision("Bash", session="s-2", command="ls"), "deny")

    def test_reading_the_lead_skill_file_opens_the_gate(self):
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Read", "tool_input": {"file_path": LEAD_SKILL}})
        self.assertEqual(self.decision("Edit", file_path="/repo/a.ts"), "allow")

    def test_typing_the_lead_command_opens_the_gate(self):
        self.run_hook("prompt", {"session_id": SESSION, "prompt": "/keel:lead fix the login bug"})
        self.assertEqual(self.decision("Bash", command="ls"), "allow")

    def test_other_skills_reads_and_prompts_keep_it_closed(self):
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Skill", "tool_input": {"skill": "keel:help"}})
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Skill", "tool_input": {"skill": "lead"}})
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Read", "tool_input": {"file_path": "/repo/skills/lead/SKILL.md"}})
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Read", "tool_input": {"file_path": LEAD_SKILL.replace("lead/SKILL", "why/SKILL")}})
        self.run_hook("prompt", {"session_id": SESSION, "prompt": "please do not use /keel:lead"})
        self.assertEqual(self.decision("Bash", command="ls"), "deny")

    def test_session_id_cannot_escape_the_marker_directory(self):
        self.run_hook("mark", {"session_id": "../../evil", "tool_name": "Skill", "tool_input": {"skill": "keel:lead"}})
        self.assertEqual(os.listdir(self.markers), ["______evil.open"])

    def test_plugin_root_anchors_the_lead_skill_file(self):
        root = "/opt/keel-fork"
        self.assertEqual(self.run_hook("gate", {"session_id": SESSION, "tool_name": "Read",
                         "tool_input": {"file_path": root + "/skills/help/../lead/SKILL.md"}}, CLAUDE_PLUGIN_ROOT=root), "")
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Read", "tool_input": {"file_path": LEAD_SKILL}},
                      CLAUDE_PLUGIN_ROOT=root)
        self.assertEqual(self.decision("Bash", command="ls"), "deny")

    def test_missing_session_fails_open_and_writes_nothing(self):
        self.assertEqual(self.run_hook("gate", {"tool_name": "Bash", "tool_input": {"command": "ls"}}), "")
        self.run_hook("mark", {"tool_name": "Skill", "tool_input": {"skill": "keel:lead"}})
        self.assertFalse(os.path.exists(self.markers))

    def test_unwritable_marker_directory_fails_open(self):
        with open(self.markers, "w") as blocker:
            blocker.write("not a directory")
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Skill", "tool_input": {"skill": "keel:lead"}})
        self.assertEqual(self.decision("Bash", command="ls"), "allow")

    def test_opening_a_gate_prunes_markers_older_than_30_days(self):
        os.makedirs(self.markers)
        stale, fresh = os.path.join(self.markers, "old.open"), os.path.join(self.markers, "new.open")
        for path in (stale, fresh):
            open(path, "w").close()
        month_ago = time.time() - 31 * 24 * 3600
        os.utime(stale, (month_ago, month_ago))
        self.run_hook("mark", {"session_id": SESSION, "tool_name": "Skill", "tool_input": {"skill": "keel:lead"}})
        self.assertEqual(sorted(os.listdir(self.markers)), ["new.open", SESSION + ".open"])

    def test_off_switch_and_bad_input_never_deny(self):
        out = self.run_hook("gate", {"session_id": SESSION, "tool_name": "Bash", "tool_input": {}}, KEEL_LEAD_GATE="off")
        self.assertEqual(out, "")
        result = subprocess.run([sys.executable, GATE, "gate"], input=b"not json", capture_output=True, env=self.env)
        self.assertEqual((result.returncode, result.stdout), (0, b""))


if __name__ == "__main__":
    unittest.main(verbosity=1)
