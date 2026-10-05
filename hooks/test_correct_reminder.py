#!/usr/bin/env python3
import json, os, subprocess, sys, unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "correct-reminder.py")

CORRECTIONS = [
    "sai rồi, branch phải tạo từ main",
    "lại sai nữa, đã bảo rồi là không push thẳng",
    "cái này làm sai, sửa lại đi",
    "không đúng rồi, phải dùng squash",
    "vẫn lỗi y như cũ",
    "nhầm rồi, repo là tristanphvn/keel",
    "lần này tái phạm lỗi cũ",
    "sao lại quên chạy test",
    "sai roi ban oi",
    "lai sai, check lai di",
    "That's wrong, the remote is origin",
    "you forgot to update the README",
    "this is not what i asked for",
    "I told you not to commit",
    "tests broken again",
]

NOT_CORRECTIONS = [
    "kiểm tra xem có lỗi không",
    "hãy sửa lỗi trong file api.py",
    "không dùng thư viện này nữa",
    "có đúng không, kiểm tra giúp",
    "đáp án sai ở câu 3 của đề thi, giải thích vì sao",
    "is this wrong?",
    "write a test for the wrong-password case",
    "",
]


def run(prompt, **env):
    result = subprocess.run(
        [sys.executable, HOOK], input=json.dumps({"prompt": prompt}, ensure_ascii=False), capture_output=True,
        text=True, encoding="utf-8", env={**os.environ, **env},
    )
    return result.stdout


class CorrectReminderTest(unittest.TestCase):
    def test_flags_corrections(self):
        for prompt in CORRECTIONS:
            with self.subTest(prompt=prompt):
                out = json.loads(run(prompt))
                self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
                self.assertIn("keel correct", out["hookSpecificOutput"]["additionalContext"])

    def test_stays_quiet_on_ordinary_prompts(self):
        for prompt in NOT_CORRECTIONS:
            with self.subTest(prompt=prompt):
                self.assertEqual(run(prompt), "")

    def test_off_switch(self):
        self.assertEqual(run(CORRECTIONS[0], KEEL_CORRECT="off"), "")

    def test_points_at_the_installed_skill(self):
        out = json.loads(run(CORRECTIONS[0], CLAUDE_PLUGIN_ROOT="/plugins/keel"))
        self.assertIn(os.path.join("/plugins/keel", "skills", "correct", "SKILL.md"), out["hookSpecificOutput"]["additionalContext"])

    def test_ignores_malformed_input(self):
        result = subprocess.run([sys.executable, HOOK], input="not json", capture_output=True, text=True)
        self.assertEqual((result.returncode, result.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
