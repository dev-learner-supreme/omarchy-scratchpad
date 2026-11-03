# Omarchy Scratchpad & Task Manager

A high-performance Markdown Scratchpad and interactive Todoist-style Task Manager widget built natively for Omarchy Linux with QtQuick and Quickshell.

---

## Features

### 1. Interactive Tasks & Checklists
* **Todoist-Style Grab Handles:** 6-dot vertical drag handles with detached floating drag ghosts and real-time slot indicators for reordering tasks.
* **Auto-Categorization:** Checking off a task automatically transitions it to the `### Completed` section with strikeout formatting. Unchecking a completed task moves it back into active tasks.
* **Inline Task Editing:** Click anywhere on a task description or timestamp to edit in place with multi-line text wrapping.
* **Rapid Task Entry:** Press `Enter` to commit the active task and immediately spawn the next item. Press `Escape` or `Backspace` on an empty task to dismiss.
* **Template Defaulting:** Adding a new task without typing text preserves `"New task"` rather than discarding the entry.
* **Permanent Sweep:** Dedicated trash action to purge completed items from storage permanently.

### 2. Typora-Style Scratchpad
* **Live Markdown Rendering:** Renders headers, lists, code blocks, blockquotes, and formatting live in preview mode.
* **Seamless Edit/Preview Shift:** Tap anywhere on the preview canvas to place a cursor. Typing immediately activates inline edit mode. Pausing typing for 3 seconds automatically shifts back to rendered preview.
* **Decoupled Tabs:** Dedicated storage buffers for `Tasks` (`tasks.md`) and freeform `Scratchpad` (`scratchpad.md`), preserving independent view modes and last-opened state across restarts.

### 3. Native Due Dates & Reminders
* **Timestamp Syntax:** Inline due dates using `[YY-MM-DD HH:MM]` format.
* **Visual Status Badges:** Visual calendar badges indicating scheduled time with automatic overdue highlighting.
* **Omarchy Notification Daemon:** Native desktop notifications triggered via `omarchy-notification-send --app-name omarchy-scratchpad`. Fully respects Omarchy Do Not Disturb and notification silencing rules.

### 4. Hardware Harmony & Performance
* **Minimal Footprint:** Consumes ~4-6 MB resident memory in Quickshell with 0.0% idle CPU overhead.
* **Atomic Persistence:** Non-blocking atomic writes via `save.py` with durable `fsync` protection.

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
| `Ctrl + Shift + K` | Sweep and permanently purge completed tasks |
| `Alt + Up / Down` | Move current line up or down |
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

---

## License

MIT License. See [LICENSE](LICENSE) for details.

Authored by Arun Rao Balappa.
