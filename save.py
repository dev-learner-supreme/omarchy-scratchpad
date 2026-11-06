#!/usr/bin/env python3
"""Atomic note writer. Usage: save.py <name>   (content on stdin, never argv).

Writes <state>/omarchy/scratchpad/<name>[.md] via unique temp file + fsync + rename.
For notes (tasks, scratchpad) commits the replaced version to a local git repo
(history.git) so any earlier state is recoverable.
"""
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

NOTES = ("tasks", "scratchpad")
HISTORY_MIN_GAP_S = 120   # commit at most this often unless a save shrinks the note hard
GIT_TIMEOUT_S = 15

# Isolate from the user's git config (hooks, signing, templates): history must never
# depend on or be blocked by global settings.
GIT_ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_SYSTEM": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "scratchpad",
    "GIT_AUTHOR_EMAIL": "scratchpad@localhost",
    "GIT_COMMITTER_NAME": "scratchpad",
    "GIT_COMMITTER_EMAIL": "scratchpad@localhost",
}


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "omarchy" / "scratchpad"


def sync_write(target: Path, content: str) -> None:
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=target.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    try:
        dfd = os.open(target.parent, os.O_DIRECTORY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except OSError:
        pass


def git(d: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", f"--git-dir={d / 'history.git'}", f"--work-tree={d}",
         "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
         "-c", "gc.auto=200", *args],
        env=GIT_ENV, cwd=d, capture_output=True, text=True, timeout=GIT_TIMEOUT_S,
    )


def record_history(d: Path, name: str, target: Path, new_content: str) -> None:
    """Commit the on-disk (about to be replaced) note to the local history repo.

    Committing the old state means a bad save, Clear, or wipe is always recoverable.
    Best effort: any failure is swallowed so saving is never blocked.
    """
    try:
        old = target.read_text(encoding="utf-8")
    except OSError:
        return
    if not old.strip() or old == new_content:
        return
    try:
        if not (d / "history.git").exists():
            git(d, "init", "-q")
        last = git(d, "log", "-1", "--format=%ct")
        last_ts = int(last.stdout.strip()) if last.returncode == 0 and last.stdout.strip() else 0
        shrinking = len(new_content) < len(old) * 0.5
        if last_ts and not shrinking and time.time() - last_ts < HISTORY_MIN_GAP_S:
            return
        git(d, "add", "--", name)
        git(d, "commit", "-q", "--no-verify", "-m",
            f"{name[:-3]} {time.strftime('%Y-%m-%d %H:%M:%S')} ({len(old)} -> {len(new_content)} chars)",
            "--", name)
        git(d, "gc", "--auto", "--quiet")
    except (OSError, subprocess.SubprocessError, ValueError):
        pass


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: save.py <name>  (content on stdin)", file=sys.stderr)
        return 2
    name = os.path.basename(sys.argv[1])  # no path traversal
    base, ext = os.path.splitext(name)
    if ext not in (".md", ".txt", ".json"):
        base, name = name, name + ".md"
    d = state_dir()
    d.mkdir(parents=True, exist_ok=True)
    content = sys.stdin.read()
    target = d / name
    if base in NOTES and name.endswith(".md"):
        record_history(d, name, target, content)
    sync_write(target, content)
    return 0


if __name__ == "__main__":
    sys.exit(main())
