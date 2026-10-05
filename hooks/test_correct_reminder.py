#!/usr/bin/env python3
import json, os, subprocess, sys, unicodedata, unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "correct-reminder.py")

CORRECTIONS = [
    "sai rồi, branch phải tạo từ main",
    "sai r, xem lại",
    "lại sai nữa, đã bảo rồi là không push thẳng",
    "bạn làm sai, sửa lại đi",
    "không đúng rồi, phải dùng squash",
    "không đúng, phải dùng squash",
    "chưa đúng đâu",
    "vẫn lỗi y như cũ",
    "lại lỗi rồi kìa",
    "nhầm rồi, repo là tristanphvn/keel",
    "lần này tái phạm lỗi cũ",
    "sao lại quên chạy test",
    "không phải ý tôi",
    "ko phải vậy",
    "sai roi ban oi",
    "lai sai, check lai di",
    "khong dung roi",
    "ko dung roi",
    "da bao roi ma",
    "lai loi roi",
    "van loi nhu cu",
    "van con loi roi",
    "That's wrong, the remote is origin",
    "wrong, use the other remote",
    "you forgot to update the README",
    "this is not what i asked for",
    "I told you not to commit",
    "tests broken again",
    "same mistake again",
    unicodedata.normalize("NFD", "vẫn lỗi y như cũ"),
]

NOT_CORRECTIONS = [
    "kiểm tra xem có lỗi không",
    "hãy sửa lỗi trong file api.py",
    "không dùng thư viện này nữa",
    "có đúng không, kiểm tra giúp",
    "đáp án sai ở câu 3 của đề thi, giải thích vì sao",
    "khi password bị sai thì báo lỗi",
    "xử lý case token bị sai",
    "nếu còn lỗi thì log ra",
    "vẫn lỗi thì retry 3 lần",
    "thêm handler: nếu lại lỗi thì báo user",
    "user bi sai mat khau",
    "đều sai số nhỏ hơn 1e-6",
    "đã bảo là dùng pnpm, cài pnpm giúp",
    "sao lại làm vậy được nhỉ, giải thích cơ chế",
    "không phải lo phần deploy",
    "is this wrong?",
    "write a test for the wrong-password case",
    "you missed nothing, looks good",
    "add a stop doing button",
    "i asked you to look at this, thanks",
    "it's not right-aligned",
    "fix the message `That's wrong, try again`",
    'đổi text thành "sai rồi, thử lại"',
    "<task-notification>critic: the hook fires on sai rồi</task-notification>",
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

    def test_points_at_the_codex_plugin_root(self):
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PLUGIN_ROOT"}
        result = subprocess.run(
            [sys.executable, HOOK], input=json.dumps({"prompt": CORRECTIONS[0]}, ensure_ascii=False),
            capture_output=True, text=True, encoding="utf-8", env={**env, "PLUGIN_ROOT": "/codex/keel"},
        )
        context = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn(os.path.join("/codex/keel", "skills", "correct", "SKILL.md"), context)

    def test_ignores_non_string_prompt(self):
        for payload in ('{"prompt": 123}', '{"prompt": ["sai rồi"]}', '["sai rồi"]', "{}"):
            with self.subTest(payload=payload):
                result = subprocess.run([sys.executable, HOOK], input=payload, capture_output=True, text=True, encoding="utf-8")
                self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_ignores_malformed_input(self):
        result = subprocess.run([sys.executable, HOOK], input="not json", capture_output=True, text=True)
        self.assertEqual((result.returncode, result.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
