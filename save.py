#!/usr/bin/env python3
"""Atomic note writer. Usage: save.py <name>   (content on stdin, never argv).

Writes <state>/omarchy/scratchpad/<name>[.md] via unique temp file + fsync + rename.
For notes (tasks, scratchpad) keeps rolling backups in backups/ so a clear or bad
save is recoverable.
"""
import os
import sys
import tempfile
import time
from pathlib import Path

NOTES = ("tasks", "scratchpad")
BACKUP_KEEP = 30          # per note
BACKUP_MIN_GAP_S = 120    # snapshot at most this often unless content is shrinking hard


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


def backup(target: Path, base: str, new_content: str) -> None:
    """Snapshot the file about to be replaced."""
    try:
        old = target.read_text(encoding="utf-8")
    except OSError:
        return
    if not old.strip() or old == new_content:
        return
    bdir = target.parent / "backups"
    bdir.mkdir(exist_ok=True)
    existing = sorted(bdir.glob(f"{base}.*.md"))
    shrinking = len(new_content) < len(old) * 0.5
    if existing and not shrinking:
        if time.time() - existing[-1].stat().st_mtime < BACKUP_MIN_GAP_S:
            return
    stamp = time.strftime("%Y%m%d-%H%M%S") + f"{int(time.time() * 1000) % 1000:03d}"
    sync_write(bdir / f"{base}.{stamp}.md", old)
    existing = sorted(bdir.glob(f"{base}.*.md"))
    for stale in existing[:-BACKUP_KEEP]:
        try:
            stale.unlink()
        except OSError:
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
        backup(target, base, content)
    sync_write(target, content)
    return 0


if __name__ == "__main__":
    sys.exit(main())
