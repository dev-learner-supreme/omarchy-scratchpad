#!/usr/bin/env python3
import os
import sys
from pathlib import Path

def sync_write(target_path: Path, content: str):
    """Write content to target_path atomically and flush to physical storage via fsync."""
    tmp = target_path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())

    tmp.replace(target_path)

    # Sync parent directory to persist directory entry metadata on journaling filesystems
    try:
        dir_fd = os.open(target_path.parent, os.O_DIRECTORY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except Exception:
        pass

def main():
    state_dir = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "omarchy" / "scratchpad"
    state_dir.mkdir(parents=True, exist_ok=True)

    if len(sys.argv) > 2:
        note_name = sys.argv[1]
        content = sys.argv[2]
    elif len(sys.argv) == 2:
        note_name = sys.argv[1]
        content = sys.stdin.read()
    else:
        note_name = "scratchpad"
        content = sys.stdin.read()

    if not note_name.endswith(".md") and not note_name.endswith(".txt") and not note_name.endswith(".json"):
        filename = f"{note_name}.md"
    else:
        filename = note_name

    target = state_dir / filename
    sync_write(target, content)

    # Also record active tab if saving one of the standard tabs
    base = filename.replace(".md", "").replace(".txt", "").replace(".json", "")
    if base in ("tasks", "scratchpad"):
        sync_write(state_dir / "active_tab.txt", base)

if __name__ == "__main__":
    main()
