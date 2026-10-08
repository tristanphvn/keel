#!/usr/bin/env python3
# Wire qmd (https://github.com/tobi/qmd) in as keel's memory layer, so the agent searches recorded
# memory and task history before answering instead of guessing or rereading whole folders.
#   qmd.py start  (SessionStart) ensures the daemon is up, converts recorded sessions to markdown,
#                 runs `qmd update`, then spawns `qmd.py embed` detached. Always returns fast.
#   qmd.py stop   (Stop) warns once when the turn searched or read but never queried qmd.
#   qmd.py embed  takes an exclusive lock and runs `qmd embed`; a concurrent second call is a no-op.
#   qmd.py watch  long-running poll loop: debounced `qmd update` + embed on *.md changes under
#                 KEEL_QMD_WATCH, daemon health check, and a keep-warm query, so the daemon's
#                 5-minute idle context eviction never bites a real query.
# Set KEEL_QMD=off to silence every mode. Every mode is a silent no-op when `qmd` is not on PATH.
import glob, json, os, shutil, subprocess, sys, time, urllib.request

try:
    import msvcrt
except ImportError:
    msvcrt = None
    import fcntl

DAEMON_URL = "http://localhost:8181"
MAX_TEXT = 4000
SEARCH_TOOLS = {"Grep", "Glob", "Read", "Bash", "WebSearch", "WebFetch", "Agent"}
SKIP_DIR_NAMES = {".git", ".obsidian", ".trash", "node_modules"}


def read_event():
    try:
        event = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    except ValueError:
        return {}
    return event if isinstance(event, dict) else {}


def http_ok(url, timeout=2):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return 200 <= resp.status < 300
    except Exception:
        return False


def http_post_json(url, payload, timeout=5):
    try:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=timeout)
    except Exception:
        pass


def spawn_detached(args):
    kwargs = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    try:
        subprocess.Popen(args, **kwargs)
    except OSError:
        pass


def run_quiet(args, timeout=None):
    try:
        subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError):
        pass


def ensure_daemon(qmd):
    if not http_ok(f"{DAEMON_URL}/health"):
        spawn_detached([qmd, "mcp", "--http", "--daemon"])


# --- cross-platform exclusive, non-blocking file lock (msvcrt on Windows, flock elsewhere) ---

def lock_path(name):
    path = os.path.join(os.path.expanduser("~"), ".cache", "qmd", name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def acquire_lock(path):
    f = open(path, "a+b")
    try:
        if msvcrt is not None:
            if os.fstat(f.fileno()).st_size == 0:
                f.write(b"0")
                f.flush()
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        f.close()
        return None
    return f


def release_lock(f):
    try:
        if msvcrt is not None:
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    finally:
        f.close()


# --- session transcript (.jsonl) -> compact markdown, so qmd can search past turns ---

def user_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list) and not any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""


def convert_session(src, dst):
    turns, meta = [], {}
    with open(src, encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("cwd"):
                meta.setdefault("cwd", e["cwd"])
            if e.get("gitBranch"):
                meta.setdefault("branch", e["gitBranch"])
            if e.get("timestamp"):
                meta.setdefault("start", e["timestamp"])
                meta["end"] = e["timestamp"]
            content = (e.get("message") or {}).get("content")
            if e.get("type") == "user" and not e.get("isMeta"):
                text = user_text(content).strip()
                if text and not text.startswith("<"):
                    turns.append(("User", text))
            elif e.get("type") == "assistant" and isinstance(content, list):
                text = "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text").strip()
                if text:
                    turns.append(("Claude", text))
    if not turns:
        return False
    sid = os.path.splitext(os.path.basename(src))[0]
    out = [
        f"# Session {sid}",
        "",
        f"- cwd: `{meta.get('cwd')}`",
        f"- branch: `{meta.get('branch')}`",
        f"- time: {meta.get('start')} → {meta.get('end')}",
        "",
    ]
    for who, text in turns:
        if len(text) > MAX_TEXT:
            text = text[:MAX_TEXT] + "\n…(truncated)"
        out += [f"## {who}", "", text, ""]
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    return True


def convert_sessions():
    patterns = os.environ.get("KEEL_QMD_SESSIONS")
    if not patterns:
        return 0
    written = 0
    for pattern in patterns.split(os.pathsep):
        if not pattern:
            continue
        for src in glob.glob(pattern, recursive=True):
            if not src.endswith(".jsonl"):
                continue
            dst = src[: -len(".jsonl")] + ".md"
            if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
                continue
            if convert_session(src, dst):
                written += 1
    return written


# --- modes ---

def start():
    read_event()
    qmd = shutil.which("qmd")
    ensure_daemon(qmd)
    convert_sessions()
    run_quiet([qmd, "update"], timeout=20)
    spawn_detached([sys.executable, os.path.abspath(__file__), "embed"])
    return None


def is_user_prompt(entry):
    if entry.get("type") != "user":
        return False
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        return True
    return isinstance(content, list) and not any(
        isinstance(c, dict) and c.get("type") == "tool_result" for c in content
    )


def tools_in_last_turn(path):
    entries = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                entries.append(json.loads(line))
            except ValueError:
                continue
    start_i = max((i for i, e in enumerate(entries) if is_user_prompt(e)), default=-1)
    names = []
    for e in entries[start_i + 1:]:
        if e.get("type") != "assistant":
            continue
        for c in e.get("message", {}).get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                names.append(c.get("name", ""))
    return names


def stop():
    event = read_event()
    try:
        names = tools_in_last_turn(event["transcript_path"])
    except (KeyError, OSError):
        return None
    used_qmd = any(n.startswith("mcp__qmd__") for n in names)
    searched = any(n in SEARCH_TOOLS for n in names)
    if searched and not used_qmd:
        return {"systemMessage": "qmd check: this turn searched/read but never queried qmd."}
    return None


def embed():
    qmd = shutil.which("qmd")
    lock = acquire_lock(lock_path("keel-embed.lock"))
    if lock is None:
        return None
    try:
        run_quiet([qmd, "embed"])
    finally:
        release_lock(lock)
    return None


def scan_latest_mtime(roots):
    latest = 0.0
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIR_NAMES]
            for name in filenames:
                if name.endswith(".md"):
                    try:
                        latest = max(latest, os.path.getmtime(os.path.join(dirpath, name)))
                    except OSError:
                        pass
    return latest


def watch():
    qmd = shutil.which("qmd")
    roots = [p for p in os.environ.get("KEEL_QMD_WATCH", "").split(os.pathsep) if p]
    if not roots:
        return None
    lock = acquire_lock(lock_path("keel-watch.lock"))
    if lock is None:
        return None
    try:
        pending = None
        last_health = 0.0
        last_warm = 0.0
        last_seen = scan_latest_mtime(roots)
        while True:
            time.sleep(2)
            now = time.time()
            seen = scan_latest_mtime(roots)
            if seen > last_seen:
                last_seen = seen
                pending = now
            if pending is not None and now - pending >= 10:
                pending = None
                run_quiet([qmd, "update"], timeout=60)
                spawn_detached([sys.executable, os.path.abspath(__file__), "embed"])
            if now - last_health >= 60:
                last_health = now
                ensure_daemon(qmd)
            if now - last_warm >= 240:
                last_warm = now
                http_post_json(
                    f"{DAEMON_URL}/query",
                    {"searches": [{"type": "vec", "query": "warm"}], "rerank": False, "limit": 1},
                    timeout=120,
                )
    finally:
        release_lock(lock)


MODES = {"start": start, "stop": stop, "watch": watch, "embed": embed}


def main():
    mode = MODES.get(sys.argv[1] if len(sys.argv) > 1 else "")
    if mode is None or os.environ.get("KEEL_QMD", "on") == "off" or not shutil.which("qmd"):
        return
    try:
        output = mode()
    except Exception:
        output = None
    if output:
        json.dump(output, sys.stdout)


if __name__ == "__main__":
    main()
