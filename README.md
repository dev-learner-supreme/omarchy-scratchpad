# Omarchy Scratchpad & Task Manager

A high-performance Markdown Scratchpad and interactive Todoist-style Task Manager widget built natively for Omarchy Linux with QtQuick and Quickshell.

---

## Features

### 1. Interactive Tasks & Checklists
* **Keyboard Reordering:** `Up/Down` selects a task (highlighted, auto-scrolled into view), `Alt+Up/Down` moves it, `Space` toggles it. Rapid moves are coalesced into a single write.
* **Auto-Categorization:** Checking off a task automatically transitions it to the `### Completed` section with strikeout formatting. Unchecking a completed task moves it back into active tasks.
* **Inline Task Editing:** Click anywhere on a task description or timestamp to edit in place with multi-line text wrapping.
* **Rapid Task Entry:** Press `Enter` to commit the active task and immediately spawn the next item. Press `Escape` or `Backspace` on an empty task to dismiss.
* **Template Defaulting:** Adding a new task without typing text preserves `"New task"` rather than discarding the entry.
* **Clear Completed:** Trash icon beside the Completed heading purges completed items permanently (backups keep a snapshot).

### 2. Typora-Style Scratchpad
* **Live Markdown Rendering:** Renders headers, lists, code blocks, blockquotes, and formatting live in preview mode.
* **Preview First:** The Scratchpad tab opens in read-only preview. The eye/pencil icon in the header or `Ctrl+E` toggles editing. Edits autosave 350 ms after you stop typing; `Ctrl+S` saves immediately and returns to preview. Tasks edit inline and shift back to preview after 3 seconds idle.
* **Decoupled Tabs:** Dedicated storage buffers for `Tasks` (`tasks.md`) and freeform `Scratchpad` (`scratchpad.md`), preserving independent view modes and last-opened state across restarts.

### 3. Native Due Dates & Reminders
* **Timestamp Syntax:** Inline due dates using `[YY-MM-DD HH:MM]` format.
* **Visual Status Badges:** Visual calendar badges indicating scheduled time with automatic overdue highlighting.
* **Omarchy Notification Daemon:** Native desktop notifications triggered via `omarchy-notification-send --app-name omarchy-scratchpad`. Fully respects Omarchy Do Not Disturb and notification silencing rules.

### 4. Hardware Harmony & Performance
* **Minimal Footprint:** Consumes ~4-6 MB resident memory in Quickshell with 0.0% idle CPU overhead.
* **Atomic Persistence:** Content is piped to `save.py` over stdin (no argv size limit), writes are serialized through a single queue, use a unique temp file plus `fsync` and rename, and the file watcher ignores reloads while local changes are unsaved.
* **Rolling Backups:** Up to 30 snapshots per note in `backups/`, taken at most every 2 minutes, or immediately when a save shrinks a note by more than half (e.g. Clear). Restore by copying a snapshot over `tasks.md` or `scratchpad.md`.
* **Reminders:** Due tasks notify once, up to 6 hours late (covers shell restarts); dedupe entries expire after 30 days.

---

## Installation

Install directly using the Omarchy CLI:

```bash
omarchy plugin add https://github.com/dev-learner-supreme/omarchy-scratchpad.git --enable
```

Or clone manually into your Omarchy plugins directory:

```bash
git clone https://github.com/dev-learner-supreme/omarchy-scratchpad.git ~/.config/omarchy/plugins/arun.scratchpad
omarchy plugin enable arun.scratchpad
omarchy restart shell
```

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Alt + \`` | Toggle Scratchpad panel open / close |
| `Ctrl + 1` | Switch to Tasks tab |
| `Ctrl + 2` | Switch to Scratchpad tab |
| `Ctrl + E` | Toggle between Edit and Preview modes |
| `Ctrl + D` | Insert current timestamp `[YY-MM-DD HH:MM]` at cursor |
| `Ctrl + Shift + K` | Clear completed tasks (also the trash icon beside the Completed heading) |
| `Ctrl + O` | Open the current note in the external editor (also right-click on the bar icon) |
| `Up / Down` | Select previous / next task (Tasks, preview) |
| `Alt + Up / Down` | Move selected task (or current line while editing) up or down |
| `Space` | Toggle the selected task |
| `Tab / Shift + Tab` | Indent / unindent line |
| `Esc` | Close panel or cancel active task edit |

---

## Storage & Files

All user notes and state persist under standard XDG state paths:

* `~/.local/state/omarchy/scratchpad/tasks.md` - Active and completed markdown tasks
* `~/.local/state/omarchy/scratchpad/scratchpad.md` - Freeform markdown notes
* `~/.local/state/omarchy/scratchpad/active_tab.txt` - Remembers last open tab
* `~/.local/state/omarchy/scratchpad/tasks_view.txt` - Remembers Tasks view mode
* `~/.local/state/omarchy/scratchpad/scratchpad_view.txt` - Remembers Scratchpad view mode
* `~/.local/state/omarchy/scratchpad/backups/` - Rolling snapshots

---

## License

MIT License. See [LICENSE](LICENSE) for details.

Authored by Arun Rao Balappa.
