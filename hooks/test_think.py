#!/usr/bin/env python3
import json, os, subprocess, sys, unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "think.py")


def run(mode, payload, **env):
    result = subprocess.run(
        [sys.executable, HOOK, mode], input=payload, capture_output=True, text=True, encoding="utf-8",
        env={**{k: v for k, v in os.environ.items() if k != "KEEL_THINK"}, **env},
    )
    return result.returncode, result.stdout


def event(**fields):
    return json.dumps({"session_id": "s", "transcript_path": "/t.jsonl", **fields}, ensure_ascii=False)


class ThinkTest(unittest.TestCase):
    def test_start_injects_the_dig_protocol_on_every_prompt(self):
        for prompt in ("ok", "cảm ơn", "refactor the auth module", ""):
            with self.subTest(prompt=prompt):
                code, out = run("start", event(hook_event_name="UserPromptSubmit", prompt=prompt))
                context = json.loads(out)["hookSpecificOutput"]
                self.assertEqual((code, context["hookEventName"]), (0, "UserPromptSubmit"))
                self.assertIn("before you answer, dig", context["additionalContext"])

    def test_stop_blocks_the_first_stop_of_a_turn(self):
        code, out = run("stop", event(hook_event_name="Stop", stop_hook_active=False))
        decision = json.loads(out)
        self.assertEqual((code, decision["decision"]), (0, "block"))
        self.assertIn("review before you send", decision["reason"])

    def test_stop_lets_the_review_continuation_end(self):
        self.assertEqual(run("stop", event(hook_event_name="Stop", stop_hook_active=True)), (0, ""))

    def test_stop_never_blocks_without_the_loop_flag(self):
        for payload in (event(hook_event_name="Stop"), "not json", "[]", '{"stop_hook_active": "false"}'):
            with self.subTest(payload=payload):
                self.assertEqual(run("stop", payload), (0, ""))

    def test_off_switch_silences_both_modes(self):
        self.assertEqual(run("start", event(prompt="x"), KEEL_THINK="off"), (0, ""))
        self.assertEqual(run("stop", event(stop_hook_active=False), KEEL_THINK="off"), (0, ""))

    def test_unknown_mode_does_nothing(self):
        self.assertEqual(run("bogus", event(stop_hook_active=False)), (0, ""))


if __name__ == "__main__":
    unittest.main()
