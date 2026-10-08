#!/usr/bin/env python3
import importlib.util, json, os, stat, subprocess, sys, tempfile, time, unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qmd.py")

# Load qmd.py as a module too, for tests that check an internal helper directly
# instead of shelling out (e.g. scan_signature).
_spec = importlib.util.spec_from_file_location("qmd_hook", HOOK)
qmd_hook = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(qmd_hook)

# Shared across this whole test run so two subprocess calls in the same test contend for the
# same lock file, while staying off the real ~/.cache/qmd that a live qmd daemon also uses.
STATE_DIR = tempfile.mkdtemp(prefix="keel-qmd-test-state-")


def clean_env():
    env = {k: v for k, v in os.environ.items() if not k.startswith("KEEL_QMD")}
    env["KEEL_QMD_STATE_DIR"] = STATE_DIR
    return env


def write_fake_qmd(dir_path, log_path):
    """A tiny recording stand-in for the real qmd binary: appends its argv to log_path and exits 0.
    With QMD_FAKE_SLEEP set, it sleeps first (any subcommand), to let a test hold the lock open or
    time how long a caller blocks on it."""
    if os.name == "nt":
        script = os.path.join(dir_path, "qmd.cmd")
        with open(script, "w") as f:
            f.write(
                "@echo off\r\n"
                f'echo %* >> "{log_path}"\r\n'
                "if defined QMD_FAKE_SLEEP ping -n %QMD_FAKE_SLEEP% 127.0.0.1>nul\r\n"
                "exit /b 0\r\n"
            )
    else:
        script = os.path.join(dir_path, "qmd")
        with open(script, "w") as f:
            f.write(
                "#!/bin/sh\n"
                f'echo "$@" >> "{log_path}"\n'
                'if [ -n "$QMD_FAKE_SLEEP" ]; then sleep "$QMD_FAKE_SLEEP"; fi\n'
                "exit 0\n"
            )
        st = os.stat(script)
        os.chmod(script, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return script


def path_without_qmd():
    parts = os.environ.get("PATH", "").split(os.pathsep)
    kept = [p for p in parts if not (os.path.exists(os.path.join(p, "qmd.cmd")) or os.path.exists(os.path.join(p, "qmd")))]
    return os.pathsep.join(kept)


def run_result(mode, payload, path=None, timeout=15, **env):
    full_env = clean_env()
    if path is not None:
        full_env["PATH"] = path
    full_env.update(env)
    return subprocess.run(
        [sys.executable, HOOK, mode], input=payload, capture_output=True, text=True, encoding="utf-8",
        env=full_env, timeout=timeout,
    )


def run(mode, payload, path=None, timeout=15, **env):
    result = run_result(mode, payload, path=path, timeout=timeout, **env)
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


def tool_result_entry():
    return {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "x", "content": "ok"}]}}


def meta_user_entry(text):
    return {"type": "user", "isMeta": True, "message": {"content": [{"type": "text", "text": text}]}}


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

    def wait_for_file(self, path, timeout=5):
        deadline = time.time() + timeout
        while time.time() < deadline and not os.path.exists(path):
            time.sleep(0.05)
        self.assertTrue(os.path.exists(path), f"{path} never appeared")

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

    def test_stop_counts_tools_used_before_an_ismeta_entry(self):
        # Claude Code injects skill bodies and other context as type:"user", isMeta:true text
        # entries. That must not read as a new turn boundary, or tools used earlier in the real
        # turn (Grep here) fall outside "last turn" and the warning never fires.
        with tempfile.TemporaryDirectory() as d:
            t = transcript(
                d,
                "t.jsonl",
                [
                    user_entry("find the bug"),
                    assistant_tool_use("Skill"),
                    tool_result_entry(),
                    assistant_tool_use("Grep"),
                    meta_user_entry("<skill body injected as context>"),
                ],
            )
            code, out = run("stop", event(transcript_path=t), path=self.path_with_fake)
            self.assertEqual(code, 0)
            self.assertEqual(
                json.loads(out),
                {"systemMessage": "qmd check: this turn searched/read but never queried qmd."},
            )

    def test_stop_reads_only_the_transcript_tail_on_a_large_file(self):
        # Stop must not parse the whole transcript. A filler entry alone past the 1 MiB tail
        # window still has to leave the real prompt and the tool use after it readable.
        with tempfile.TemporaryDirectory() as d:
            filler = assistant_text("x" * (2 * 1024 * 1024))
            t = transcript(d, "t.jsonl", [filler, user_entry("find the bug"), assistant_tool_use("Grep")])
            code, out = run("stop", event(transcript_path=t), path=self.path_with_fake)
            self.assertEqual(code, 0)
            self.assertEqual(
                json.loads(out),
                {"systemMessage": "qmd check: this turn searched/read but never queried qmd."},
            )

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
            # start() only spawns the embed pass that does the conversion; it does not do it inline.
            code, out = run(
                "start", event(), path=self.path_with_fake,
                KEEL_QMD_SESSIONS=os.path.join(d, "*.jsonl"),
            )
            self.assertEqual((code, out), (0, ""))
            self.wait_for_file(dst)
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
            self.wait_for_file(dst)
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
            with open(self.log) as f:
                calls_before = f.read().strip().splitlines()

            second_env = clean_env()
            second_env["PATH"] = self.path_with_fake
            second = subprocess.run(
                [sys.executable, HOOK, "embed"], input="", capture_output=True, text=True,
                env=second_env, timeout=15,
            )
            self.assertEqual((second.returncode, second.stdout), (0, ""))

            with open(self.log) as f:
                calls_after = f.read().strip().splitlines()
            self.assertEqual(calls_after, calls_before, "second holder must not have run qmd update/embed")
        finally:
            first.communicate(timeout=15)

    def test_start_returns_quickly_even_when_qmd_is_slow(self):
        # start() must only ensure the daemon and spawn the embed pass detached; the slow work
        # (session conversion, `qmd update`, `qmd embed`) happens in that detached child, not inline.
        began = time.time()
        code, out = run("start", event(), path=self.path_with_fake, QMD_FAKE_SLEEP="5")
        elapsed = time.time() - began
        self.assertEqual((code, out), (0, ""))
        self.assertLess(elapsed, 2, f"start blocked for {elapsed:.1f}s")

    def test_watch_skips_missing_roots_and_exits_when_none_exist(self):
        missing = os.path.join(self.fake_dir, "does-not-exist")
        result = run_result(
            "watch", "", path=self.path_with_fake, timeout=10, KEEL_QMD_WATCH=missing,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn(missing, result.stderr)
        self.assertEqual(os.path.exists(self.log), False)

    def test_scan_signature_changes_on_deletion(self):
        # A pure mtime signature misses a deletion when the remaining file's mtime doesn't
        # change; pairing it with a file count catches it.
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "a.md"), "w").close()
            open(os.path.join(d, "b.md"), "w").close()
            before = qmd_hook.scan_signature([d])
            self.assertEqual(before[0], 2)
            os.remove(os.path.join(d, "b.md"))
            after = qmd_hook.scan_signature([d])
            self.assertEqual(after[0], 1)
            self.assertNotEqual(before, after)


if __name__ == "__main__":
    unittest.main()
