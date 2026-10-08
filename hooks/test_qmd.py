#!/usr/bin/env python3
import json, os, stat, subprocess, sys, tempfile, time, unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qmd.py")


def clean_env():
    return {k: v for k, v in os.environ.items() if not k.startswith("KEEL_QMD")}


def write_fake_qmd(dir_path, log_path):
    """A tiny recording stand-in for the real qmd binary: appends its argv to log_path and exits 0.
    When called as `qmd embed` with QMD_FAKE_SLEEP set, it sleeps first, to let a test hold the lock open."""
    if os.name == "nt":
        script = os.path.join(dir_path, "qmd.cmd")
        with open(script, "w") as f:
            f.write(
                "@echo off\r\n"
                f'echo %* >> "{log_path}"\r\n'
                'if "%1"=="embed" if defined QMD_FAKE_SLEEP ping -n %QMD_FAKE_SLEEP% 127.0.0.1>nul\r\n'
                "exit /b 0\r\n"
            )
    else:
        script = os.path.join(dir_path, "qmd")
        with open(script, "w") as f:
            f.write(
                "#!/bin/sh\n"
                f'echo "$@" >> "{log_path}"\n'
                'if [ "$1" = "embed" ] && [ -n "$QMD_FAKE_SLEEP" ]; then sleep "$QMD_FAKE_SLEEP"; fi\n'
                "exit 0\n"
            )
        st = os.stat(script)
        os.chmod(script, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return script


def path_without_qmd():
    parts = os.environ.get("PATH", "").split(os.pathsep)
    kept = [p for p in parts if not (os.path.exists(os.path.join(p, "qmd.cmd")) or os.path.exists(os.path.join(p, "qmd")))]
    return os.pathsep.join(kept)


def run(mode, payload, path=None, timeout=15, **env):
    full_env = clean_env()
    if path is not None:
        full_env["PATH"] = path
    full_env.update(env)
    result = subprocess.run(
        [sys.executable, HOOK, mode], input=payload, capture_output=True, text=True, encoding="utf-8",
        env=full_env, timeout=timeout,
    )
    return result.returncode, result.stdout


def event(**fields):
    return json.dumps({"session_id": "s", "transcript_path": "/t.jsonl", **fields}, ensure_ascii=False)


def transcript(tmp_dir, name, entries):
    path = os.path.join(tmp_dir, name)
    with open(path, "w", encoding="utf-8") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")
    return path


def user_entry(text):
    return {"type": "user", "message": {"content": text}}


def assistant_tool_use(*names):
    return {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": n} for n in names]}}


def assistant_text(text):
    return {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}


class QmdHookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fake_dir = self.tmp.name
        self.log = os.path.join(self.fake_dir, "calls.log")
        write_fake_qmd(self.fake_dir, self.log)
        self.path_with_fake = self.fake_dir + os.pathsep + os.environ.get("PATH", "")
        self.path_no_qmd = path_without_qmd()

    def tearDown(self):
        self.tmp.cleanup()

    def test_stop_warns_when_the_turn_searched_without_qmd(self):
        with tempfile.TemporaryDirectory() as d:
            t = transcript(d, "t.jsonl", [user_entry("find the bug"), assistant_tool_use("Read")])
            code, out = run("stop", event(transcript_path=t), path=self.path_with_fake)
            self.assertEqual(code, 0)
            self.assertEqual(
                json.loads(out),
                {"systemMessage": "qmd check: this turn searched/read but never queried qmd."},
            )

    def test_stop_does_not_warn_when_qmd_was_queried(self):
        with tempfile.TemporaryDirectory() as d:
            t = transcript(d, "t.jsonl", [user_entry("find the bug"), assistant_tool_use("Read", "mcp__qmd__query")])
            self.assertEqual(run("stop", event(transcript_path=t), path=self.path_with_fake), (0, ""))

    def test_stop_does_not_warn_on_a_chat_only_turn(self):
        with tempfile.TemporaryDirectory() as d:
            t = transcript(d, "t.jsonl", [user_entry("thanks"), assistant_text("you're welcome")])
            self.assertEqual(run("stop", event(transcript_path=t), path=self.path_with_fake), (0, ""))

    def test_off_switch_silences_every_mode(self):
        with tempfile.TemporaryDirectory() as d:
            t = transcript(d, "t.jsonl", [user_entry("find the bug"), assistant_tool_use("Read")])
            self.assertEqual(
                run("stop", event(transcript_path=t), path=self.path_with_fake, KEEL_QMD="off"), (0, "")
            )
            self.assertEqual(run("start", event(), path=self.path_with_fake, KEEL_QMD="off"), (0, ""))
        self.assertEqual(os.path.exists(self.log), False)

    def test_every_mode_is_a_noop_without_qmd_on_path(self):
        with tempfile.TemporaryDirectory() as d:
            t = transcript(d, "t.jsonl", [user_entry("find the bug"), assistant_tool_use("Read")])
            self.assertEqual(run("stop", event(transcript_path=t), path=self.path_no_qmd), (0, ""))
            self.assertEqual(run("start", event(), path=self.path_no_qmd), (0, ""))
            self.assertEqual(run("embed", event(), path=self.path_no_qmd), (0, ""))
        self.assertEqual(os.path.exists(self.log), False)

    def test_session_conversion_writes_literal_markdown(self):
        with tempfile.TemporaryDirectory() as d:
            src = transcript(
                d,
                "fixture.jsonl",
                [
                    {
                        "type": "user",
                        "cwd": "/repo",
                        "gitBranch": "main",
                        "timestamp": "2026-01-01T00:00:00Z",
                        "message": {"content": "hello there"},
                    },
                    {
                        "type": "assistant",
                        "timestamp": "2026-01-01T00:00:05Z",
                        "message": {"content": [{"type": "text", "text": "hi back"}]},
                    },
                ],
            )
            dst = src[: -len(".jsonl")] + ".md"
            code, out = run(
                "start", event(), path=self.path_with_fake,
                KEEL_QMD_SESSIONS=os.path.join(d, "*.jsonl"),
            )
            self.assertEqual((code, out), (0, ""))
            with open(dst, encoding="utf-8") as f:
                content = f.read()
            expected = (
                "# Session fixture\n\n"
                "- cwd: `/repo`\n"
                "- branch: `main`\n"
                "- time: 2026-01-01T00:00:00Z → 2026-01-01T00:00:05Z\n\n"
                "## User\n\n"
                "hello there\n\n"
                "## Claude\n\n"
                "hi back\n"
            )
            self.assertEqual(content, expected)

    def test_session_conversion_skips_prompts_starting_with_angle_bracket(self):
        with tempfile.TemporaryDirectory() as d:
            src = transcript(
                d,
                "fixture2.jsonl",
                [
                    {"type": "user", "message": {"content": "<system-reminder>skip me</system-reminder>"}},
                    {"type": "assistant", "message": {"content": [{"type": "text", "text": "noted"}]}},
                ],
            )
            dst = src[: -len(".jsonl")] + ".md"
            run("start", event(), path=self.path_with_fake, KEEL_QMD_SESSIONS=os.path.join(d, "*.jsonl"))
            with open(dst, encoding="utf-8") as f:
                content = f.read()
            self.assertNotIn("skip me", content)
            self.assertIn("## Claude", content)

    def test_embed_lock_blocks_a_concurrent_second_holder(self):
        env = clean_env()
        env["PATH"] = self.path_with_fake
        env["QMD_FAKE_SLEEP"] = "4"
        first = subprocess.Popen(
            [sys.executable, HOOK, "embed"], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
        )
        try:
            deadline = time.time() + 5
            while time.time() < deadline and not os.path.exists(self.log):
                time.sleep(0.05)
            self.assertTrue(os.path.exists(self.log), "first embed never reached the fake qmd")

            second_env = clean_env()
            second_env["PATH"] = self.path_with_fake
            second = subprocess.run(
                [sys.executable, HOOK, "embed"], input="", capture_output=True, text=True,
                env=second_env, timeout=15,
            )
            self.assertEqual((second.returncode, second.stdout), (0, ""))

            with open(self.log) as f:
                calls = f.read().strip().splitlines()
            self.assertEqual(len(calls), 1, "second holder must not have run qmd embed")
        finally:
            first.communicate(timeout=15)


if __name__ == "__main__":
    unittest.main()
