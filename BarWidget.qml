import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "arun.scratchpad"

  readonly property string storageDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/scratchpad"
  property string activeTab: "tasks"
  readonly property var tabNames: ["tasks", "scratchpad"]
  readonly property var tabFiles: ({ "tasks": "tasks.md", "scratchpad": "scratchpad.md" })
  readonly property string currentFilePath: storageDir + "/" + (tabFiles[activeTab] || "tasks.md")

  property string tasksText: ""
  property string lastSavedTasksText: ""
  property string tasksViewMode: "preview"

  property string scratchpadText: ""
  property string lastSavedScratchpadText: ""
  property string scratchpadViewMode: "preview"

  // Active viewMode dynamically bound to current tab's viewMode
  readonly property string viewMode: (activeTab === "tasks") ? tasksViewMode : scratchpadViewMode
  readonly property bool autoShiftEnabled: true

  property bool dragActive: false
  property int draggedLineIndex: -1
  property int draggedItemIndex: -1
  property string draggedContent: ""
  property bool draggedChecked: false
  property string draggedDueDate: ""
  property real dragGhostY: 0
  property int dropTargetIndex: -1
  property int dropTargetLineIndex: -1
  property bool dropBefore: true
  property int editingLineIndex: -1
  signal requestTaskFocus(int lineIndex)

  readonly property int pendingTaskCount: {
    var count = 0
    var lines = tasksText.split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].match(/^\s*[-*]\s*\[ \]\s*/)) count++
    }
    return count
  }
  property var notifiedReminders: ({})

  property string currentText: ""
  property string statusMessage: "Saved"
  property int wordCount: 0
  property int charCount: 0
  property var parsedItems: []

  property int pendingCursorPos: -1
  property int pendingLineIndex: -1
  property int pendingCharOffset: -1
  property bool pendingAfterLast: false

  function persistViewMode(tab, mode) {
    var filename = (tab === "tasks") ? "tasks_view.txt" : "scratchpad_view.txt"
    Quickshell.execDetached(["sh", "-c", "echo -n '" + mode + "' > '" + storageDir + "/" + filename + "'"])
  }

  function pad2(n) {
    return (n < 10 ? "0" : "") + n
  }

  function formatCurrentTimestamp() {
    var d = new Date()
    var yy = String(d.getFullYear()).slice(-2)
    var mm = pad2(d.getMonth() + 1)
    var dd = pad2(d.getDate())
    var hh = pad2(d.getHours())
    var min = pad2(d.getMinutes())
    return "[" + yy + "-" + mm + "-" + dd + " " + hh + ":" + min + "]"
  }

  function sweepCompletedTasks() {
    if (activeTab !== "tasks") return
    var lines = tasksText.split("\n")
    var newLines = []
    var inCompletedHeader = false

    for (var i = 0; i < lines.length; i++) {
      var l = lines[i]
      var trimmed = l.trim()

      if (trimmed.match(/^#{1,6}\s+Completed$/i)) {
        inCompletedHeader = true
        continue
      }

      if (inCompletedHeader) {
        if (trimmed.match(/^#{1,6}\s+/)) {
          inCompletedHeader = false
          newLines.push(l)
        }
        continue
      }

      if (l.match(/^\s*[-*]\s*\[[xX]\]/)) {
        continue
      }

      newLines.push(l)
    }

    while (newLines.length > 0 && newLines[newLines.length - 1].trim() === "") {
      newLines.pop()
    }

    var newText = newLines.join("\n") + "\n"
    tasksText = newText
    currentText = newText
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = newText
    }
    refreshParsedItems()
    saveNow()
  }

  function applyTaskDrop(fromLineIdx, targetLineIdx, dropBefore) {
    if (fromLineIdx < 0 || targetLineIdx < 0) return

    var lines = tasksText.split("\n")
    if (fromLineIdx >= lines.length || targetLineIdx >= lines.length) return
    if (fromLineIdx === targetLineIdx) return

    var taskLine = lines[fromLineIdx]
    var insertLine = dropBefore ? targetLineIdx : (targetLineIdx + 1)

    var compIdx = -1
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().match(/^#{1,6}\s+Completed$/i)) {
        compIdx = i
        break
      }
    }

    if (compIdx !== -1) {
      if (insertLine <= compIdx) {
        taskLine = taskLine.replace(/^(\s*[-*]\s*)\[[xX]\]/, "$1[ ]")
      } else {
        taskLine = taskLine.replace(/^(\s*[-*]\s*)\[ \]/, "$1[x]")
      }
    }

    lines.splice(fromLineIdx, 1)
    var destLine = insertLine
    if (fromLineIdx < destLine) {
      destLine--
    }
    lines.splice(destLine, 0, taskLine)

    var newText = lines.join("\n")
    tasksText = newText
    currentText = newText
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = newText
    }
    refreshParsedItems()
    saveNow()
  }

  function commitTaskDrop() {
    var fromLineIdx = root.draggedLineIndex
    var targetLineIdx = root.dropTargetLineIndex
    var dropBefore = root.dropBefore
    root.applyTaskDrop(fromLineIdx, targetLineIdx, dropBefore)
  }

  function commitTaskEdit(lineIdx, newContent, createNext) {
    var lines = tasksText.split("\n")
    if (lineIdx < 0 || lineIdx >= lines.length) return
    var oldLine = lines[lineIdx]

    var m = oldLine.match(/^(\s*[-*]\s*\[[ xX]\]\s*)(.*)$/)
    var prefix = m ? m[1] : "- [ ] "
    var cleanTrimmed = (newContent || "").trim()

    if (cleanTrimmed.length === 0) {
      cleanTrimmed = "New task"
    }

    if (createNext) {
      lines[lineIdx] = prefix + cleanTrimmed
      lines.splice(lineIdx + 1, 0, "- [ ] ")
      root.editingLineIndex = lineIdx + 1
      root.pendingCharOffset = 0
      Qt.callLater(function() {
        root.requestTaskFocus(lineIdx + 1)
      })
    } else {
      lines[lineIdx] = prefix + cleanTrimmed
      root.editingLineIndex = -1
    }

    var newText = lines.join("\n")
    tasksText = newText
    currentText = newText
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = newText
    }
    refreshParsedItems()
    saveNow()
  }

  function deleteTaskAtLine(lineIdx) {
    var lines = tasksText.split("\n")
    if (lineIdx < 0 || lineIdx >= lines.length) return
    lines.splice(lineIdx, 1)

    var prevLineIdx = -1
    for (var i = lineIdx - 1; i >= 0; i--) {
      if (lines[i].match(/^\s*[-*]\s*\[ \]/)) {
        prevLineIdx = i
        break
      }
    }
    root.editingLineIndex = prevLineIdx
    root.pendingCharOffset = 0

    var newText = lines.join("\n")
    tasksText = newText
    currentText = newText
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = newText
    }
    refreshParsedItems()
    saveNow()

    if (prevLineIdx >= 0) {
      Qt.callLater(function() {
        root.requestTaskFocus(prevLineIdx)
      })
    }
  }

  function addNewTaskAtEnd(initialText) {
    var initStr = (typeof initialText === "string") ? initialText : ""
    var lines = tasksText.split("\n")
    var compIdx = -1
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().match(/^#{1,6}\s+Completed$/i)) {
        compIdx = i
        break
      }
    }

    var insertIdx = compIdx !== -1 ? compIdx : lines.length
    while (insertIdx > 0 && lines[insertIdx - 1].trim() === "") {
      insertIdx--
    }

    if (insertIdx > 0 && lines[insertIdx - 1].match(/^\s*[-*]\s*\[ \]\s*$/)) {
      if (initStr.length > 0) {
        lines[insertIdx - 1] = "- [ ] " + initStr
        var newT = lines.join("\n")
        tasksText = newT
        currentText = newT
        if (panel.loadedContent && panel.loadedContent.editor) {
          panel.loadedContent.editor.text = newT
        }
        refreshParsedItems()
        saveNow()
      }
      root.editingLineIndex = insertIdx - 1
      root.pendingCharOffset = initStr.length
      Qt.callLater(function() {
        root.requestTaskFocus(insertIdx - 1)
      })
      return
    }

    lines.splice(insertIdx, 0, "- [ ] " + initStr)
    root.editingLineIndex = insertIdx
    root.pendingCharOffset = initStr.length

    var newText = lines.join("\n")
    tasksText = newText
    currentText = newText
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = newText
    }
    refreshParsedItems()
    saveNow()

    Qt.callLater(function() {
      root.requestTaskFocus(insertIdx)
    })
  }

  function moveTaskLine(fromLineIdx, direction) {
    var lines = tasksText.split("\n")
    if (fromLineIdx < 0 || fromLineIdx >= lines.length) return false

    var targetIdx = fromLineIdx + direction
    while (targetIdx >= 0 && targetIdx < lines.length && lines[targetIdx].trim() === "") {
      targetIdx += direction
    }

    if (targetIdx < 0 || targetIdx >= lines.length) return false
    if (targetIdx === 0 && lines[0].startsWith("#")) return false

    var temp = lines[fromLineIdx]
    lines[fromLineIdx] = lines[targetIdx]
    lines[targetIdx] = temp

    var newText = lines.join("\n")
    tasksText = newText
    currentText = newText
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = newText
    }
    refreshParsedItems()
    saveNow()
    return true
  }

  function moveCurrentLine(editor, direction) {
    var pos = editor.cursorPosition
    var txt = editor.text
    var lines = txt.split("\n")

    var lineIdx = 0
    var offset = 0
    for (var i = 0; i < lines.length; i++) {
      var nextOffset = offset + lines[i].length + 1
      if (pos <= nextOffset || i === lines.length - 1) {
        lineIdx = i
        break
      }
      offset = nextOffset
    }

    var targetIdx = lineIdx + direction
    if (targetIdx < 0 || targetIdx >= lines.length) return

    var col = pos - offset
    var temp = lines[lineIdx]
    lines[lineIdx] = lines[targetIdx]
    lines[targetIdx] = temp

    var newTxt = lines.join("\n")
    editor.text = newTxt
    root.onTextEdited(newTxt)

    var newOffset = 0
    for (var j = 0; j < targetIdx; j++) {
      newOffset += lines[j].length + 1
    }
    editor.cursorPosition = Math.min(newOffset + col, newOffset + lines[targetIdx].length)
  }

  function checkTaskReminders() {
    if (!tasksText) return
    var lines = tasksText.split("\n")
    var now = new Date()
    var nowMs = now.getTime()
    var modified = false

    // Cleanup reminders older than 30 days
    for (var k in notifiedReminders) {
      if (nowMs - notifiedReminders[k] > 30 * 24 * 60 * 60 * 1000) {
        delete notifiedReminders[k]
        modified = true
      }
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var match = line.match(/^\s*[-*]\s*\[ \]\s*(.*)$/)
      if (!match) continue

      var taskBody = match[1]
      var tsMatch = taskBody.match(/\[(?:20)?(\d{2})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})\]/)
      if (!tsMatch) continue

      var year = 2000 + parseInt(tsMatch[1], 10)
      var month = parseInt(tsMatch[2], 10) - 1
      var day = parseInt(tsMatch[3], 10)
      var hour = parseInt(tsMatch[4], 10)
      var min = parseInt(tsMatch[5], 10)

      var dueDate = new Date(year, month, day, hour, min, 0, 0)
      var dueMs = dueDate.getTime()
      if (isNaN(dueMs)) continue
      var reminderKey = line.trim() + "@" + dueMs

      if (nowMs >= dueMs && (nowMs - dueMs) <= 15 * 60 * 1000) {
        if (!notifiedReminders[reminderKey]) {
          var cleanTask = taskBody.replace(tsMatch[0], "").trim()
          if (!cleanTask) cleanTask = "Task reminder"

          // Omarchy notification send with app-name omarchy-scratchpad respects Omarchy DND/silence rules
          Quickshell.execDetached([
            "omarchy-notification-send",
            "--app-name", "omarchy-scratchpad",
            "-g", "\uf073",
            "-u", "normal",
            "Task Reminder",
            cleanTask + " [" + tsMatch[1] + "-" + tsMatch[2] + "-" + tsMatch[3] + " " + tsMatch[4] + ":" + tsMatch[5] + "]"
          ])

          notifiedReminders[reminderKey] = nowMs
          modified = true
        }
      }
    }

    if (modified) {
      var scriptPath = Qt.resolvedUrl("save.py").toString().replace("file://", "")
      var jsonStr = JSON.stringify(notifiedReminders)
      Quickshell.execDetached([scriptPath, "notified_reminders.json", jsonStr])
    }
  }

  function getLineStartOffset(lineIdx) {
    var lines = currentText.split("\n")
    var offset = 0
    for (var k = 0; k < lineIdx && k < lines.length; k++) {
      offset += lines[k].length + 1
    }
    return offset
  }

  function getPrefixLength(lineIdx, itemType) {
    var lines = currentText.split("\n")
    if (lineIdx < 0 || lineIdx >= lines.length) return 0
    var line = lines[lineIdx]
    if (itemType === "task") {
      var m = line.match(/^(\s*[-*]\s*\[[ xX]\]\s*)/)
      return m ? m[1].length : 0
    }
    if (itemType === "header") {
      var m = line.match(/^(#{1,6}\s*)/)
      return m ? m[1].length : 0
    }
    if (itemType === "bullet") {
      var m = line.match(/^(\s*[-*]\s+)/)
      return m ? m[1].length : 0
    }
    if (itemType === "numbered") {
      var m = line.match(/^(\s*\d+\.\s+)/)
      return m ? m[1].length : 0
    }
    if (itemType === "quote") {
      var m = line.match(/^(>\s*)/)
      return m ? m[1].length : 0
    }
    return 0
  }

  function setPendingCursorOnLine(lineIdx, itemType, charOffsetInText) {
    pendingAfterLast = false
    pendingLineIndex = lineIdx
    pendingCharOffset = charOffsetInText
    var start = getLineStartOffset(lineIdx)
    var pfx = getPrefixLength(lineIdx, itemType)
    pendingCursorPos = start + pfx + charOffsetInText
    if (panel.loadedContent) {
      panel.loadedContent.forceActiveFocus()
    }
  }

  function setPendingCursorAfterLast() {
    pendingAfterLast = true
    pendingLineIndex = -1
    pendingCharOffset = -1
    pendingCursorPos = -1
    if (panel.loadedContent) {
      panel.loadedContent.forceActiveFocus()
    }
  }

  function clearPendingCursor() {
    pendingAfterLast = false
    pendingLineIndex = -1
    pendingCharOffset = -1
    pendingCursorPos = -1
  }

  readonly property string statsString: strings.tn("scratchpad.words", wordCount).arg(Commons.I18n.formatNumber(wordCount)) + " • " + strings.tn("scratchpad.chars", charCount).arg(Commons.I18n.formatNumber(charCount))

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property bool opened: panel.open

  function open() {
    panel.open = true
    tasksFile.reload()
    scratchpadFile.reload()
    var targetTxt = (activeTab === "tasks") ? tasksText : scratchpadText
    syncActiveTabContent(targetTxt)
    Qt.callLater(function() {
      if (panel.loadedContent) {
        if (root.viewMode === "preview") {
          panel.loadedContent.forceActiveFocus()
        } else if (panel.loadedContent.editor) {
          panel.loadedContent.editor.forceActiveFocus()
        }
      }
    })
  }

  function cleanEmptyTaskLines() {
    var lines = tasksText.split("\n")
    var changed = false
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].match(/^\s*[-*]\s*\[ \]\s*$/)) {
        lines[i] = "- [ ] New task"
        changed = true
      }
    }
    if (changed) {
      var newText = lines.join("\n")
      tasksText = newText
      currentText = newText
      if (panel.loadedContent && panel.loadedContent.editor) {
        panel.loadedContent.editor.text = newText
      }
      refreshParsedItems()
    }
  }

  function close() {
    autoPreviewTimer.stop()
    cleanEmptyTaskLines()
    saveNow()
    clearPendingCursor()
    root.dragActive = false
    root.draggedItemIndex = -1
    root.draggedLineIndex = -1
    root.dropTargetIndex = -1
    root.dropTargetLineIndex = -1
    root.editingLineIndex = -1
    // Persist active tab and view modes
    Quickshell.execDetached(["sh", "-c", "echo -n '" + root.activeTab + "' > '" + storageDir + "/active_tab.txt'"])
    persistViewMode("tasks", tasksViewMode)
    persistViewMode("scratchpad", scratchpadViewMode)
    panel.open = false
  }

  function toggle() {
    if (opened) close(); else open()
  }

  function switchTab(tab) {
    if (activeTab === tab) return
    autoPreviewTimer.stop()
    cleanEmptyTaskLines()
    clearPendingCursor()

    // 1. Save pending outgoing tab edits first
    saveNow()

    // 2. Switch tab
    activeTab = tab

    // 3. Immediately update currentText from destination tab's in-memory text
    var targetText = (tab === "tasks") ? tasksText : scratchpadText
    currentText = targetText
    updateCounts(targetText)
    refreshParsedItems()
    statusMessage = strings.t("scratchpad.saved")

    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = targetText
    }

    // 4. Persist active tab to disk
    Quickshell.execDetached(["sh", "-c", "echo -n '" + tab + "' > '" + storageDir + "/active_tab.txt'"])

    // 5. Restore focus
    Qt.callLater(function() {
      if (panel.loadedContent) {
        if (root.viewMode === "preview") {
          panel.loadedContent.forceActiveFocus()
        } else if (panel.loadedContent.editor) {
          panel.loadedContent.editor.forceActiveFocus()
        }
      }
    })
  }

  function toggleViewMode(willing) {
    autoPreviewTimer.stop()
    clearPendingCursor()

    if (activeTab === "tasks") {
      if (tasksViewMode === "edit") {
        saveNow()
        refreshParsedItems()
        tasksViewMode = "preview"
        persistViewMode("tasks", "preview")
        Qt.callLater(function() {
          if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
        })
      } else {
        tasksViewMode = "edit"
        persistViewMode("tasks", "edit")
        Qt.callLater(function() {
          if (panel.loadedContent && panel.loadedContent.editor) {
            panel.loadedContent.editor.forceActiveFocus()
          }
        })
        autoPreviewTimer.restart()
      }
    } else {
      // Scratchpad tab: freely toggle between edit and preview, NO auto-shift timer!
      if (scratchpadViewMode === "edit") {
        saveNow()
        refreshParsedItems()
        scratchpadViewMode = "preview"
        persistViewMode("scratchpad", "preview")
        Qt.callLater(function() {
          if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
        })
      } else {
        scratchpadViewMode = "edit"
        persistViewMode("scratchpad", "edit")
        Qt.callLater(function() {
          if (panel.loadedContent && panel.loadedContent.editor) {
            panel.loadedContent.editor.forceActiveFocus()
          }
        })
      }
    }
  }

  function shiftToEditAndType(key, text) {
    autoPreviewTimer.stop()
    var wasAfterLast = pendingAfterLast
    var targetCursor = pendingCursorPos
    clearPendingCursor()

    if (activeTab === "tasks") {
      tasksViewMode = "edit"
      persistViewMode("tasks", "edit")
    } else {
      scratchpadViewMode = "edit"
      persistViewMode("scratchpad", "edit")
    }

    Qt.callLater(function() {
      if (panel.loadedContent && panel.loadedContent.editor) {
        var ed = panel.loadedContent.editor
        ed.forceActiveFocus()

        if (wasAfterLast || targetCursor < 0) {
          var len = ed.text.length
          ed.cursorPosition = len

          if (root.activeTab === "tasks") {
            var prefix = ""
            if (len > 0 && !ed.text.endsWith("\n")) {
              prefix = "\n- [ ] "
            } else if (!ed.text.endsWith("- [ ] ")) {
              prefix = "- [ ] "
            }
            if (prefix.length > 0) {
              ed.insert(len, prefix)
            }
          } else {
            if (len > 0 && !ed.text.endsWith("\n")) {
              ed.insert(len, "\n")
            }
          }
          ed.cursorPosition = ed.text.length

          if (text && text.length > 0 && key !== Qt.Key_Return && key !== Qt.Key_Enter && key !== Qt.Key_Backspace) {
            ed.insert(ed.cursorPosition, text)
            ed.cursorPosition = ed.text.length
          }
        } else {
          var pos = Math.min(ed.text.length, Math.max(0, targetCursor))
          ed.cursorPosition = pos

          if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            root.handleReturn(ed, { accepted: false })
          } else if (key === Qt.Key_Backspace) {
            if (pos > 0) {
              ed.remove(pos - 1, pos)
              ed.cursorPosition = pos - 1
            }
          } else if (text && text.length > 0) {
            ed.insert(pos, text)
            ed.cursorPosition = Math.min(ed.text.length, pos + text.length)
          }
        }

        if (root.autoShiftEnabled) {
          autoPreviewTimer.restart()
        }
      }
    })
  }

  function syncActiveTabContent(txt) {
    if (panel.loadedContent && panel.loadedContent.editor && panel.loadedContent.editor.activeFocus) {
      return
    }
    currentText = txt
    updateCounts(txt)
    refreshParsedItems()
    statusMessage = strings.t("scratchpad.saved")
    if (panel.loadedContent && panel.loadedContent.editor) {
      if (panel.loadedContent.editor.text !== txt) {
        panel.loadedContent.editor.text = txt
      }
    }
  }

  function onTextEdited(newText) {
    currentText = newText
    if (activeTab === "tasks") {
      tasksText = newText
    } else {
      scratchpadText = newText
    }
    updateCounts(newText)
    statusMessage = "..."
    saveDebounceTimer.restart()
    if (autoShiftEnabled) {
      autoPreviewTimer.restart()
    }
  }

  function updateCounts(txt) {
    charCount = txt.length
    var words = txt.trim().split(/\s+/)
    wordCount = (txt.trim().length === 0) ? 0 : words.length
  }

  function saveNow() {
    saveDebounceTimer.stop()
    var scriptPath = Qt.resolvedUrl("save.py").toString().replace("file://", "")

    if (activeTab === "tasks") {
      if (currentText === lastSavedTasksText) return
      tasksText = currentText
      lastSavedTasksText = currentText
      Quickshell.execDetached([scriptPath, "tasks", currentText])
    } else {
      if (currentText === lastSavedScratchpadText) return
      scratchpadText = currentText
      lastSavedScratchpadText = currentText
      Quickshell.execDetached([scriptPath, "scratchpad", currentText])
    }
    statusMessage = strings.t("scratchpad.saved")
  }

  function copyAll() {
    saveNow()
    Quickshell.execDetached(["wl-copy", currentText])
    Quickshell.execDetached(["omarchy-notification-send", strings.t("scratchpad.title"), strings.t("scratchpad.copied")])
    statusMessage = strings.t("scratchpad.copied")
  }

  function clearNote() {
    clearPendingCursor()
    currentText = ""
    if (activeTab === "tasks") {
      tasksText = ""
    } else {
      scratchpadText = ""
    }
    updateCounts("")
    refreshParsedItems()
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = ""
    }
    saveNow()
  }

  function openInEditor() {
    saveNow()
    close()
    Quickshell.execDetached(["omarchy-launch-editor", root.currentFilePath])
  }

  // --- Typora Return Key Logic (Zero Unexpected Checkboxes) ---
  function handleReturn(editor, event) {
    var pos = editor.cursorPosition
    var txt = editor.text
    var lineStart = txt.lastIndexOf("\n", pos - 1) + 1
    var lineEnd = txt.indexOf("\n", pos)
    if (lineEnd === -1) lineEnd = txt.length
    var line = txt.substring(lineStart, lineEnd)
    var isAtEnd = (pos === lineEnd)

    // 1. Empty checkbox item (- [ ] or - [x]) -> clear prefix to exit list cleanly
    var emptyTask = line.match(/^(\s*[-*]\s*\[[ xX]\]\s*)$/)
    if (emptyTask) {
      event.accepted = true
      editor.text = txt.substring(0, lineStart) + txt.substring(lineEnd)
      editor.cursorPosition = lineStart
      return
    }

    // 2. Empty bullet item (- or *) -> clear prefix to exit list cleanly
    var emptyBullet = line.match(/^(\s*[-*]\s*)$/)
    if (emptyBullet) {
      event.accepted = true
      editor.text = txt.substring(0, lineStart) + txt.substring(lineEnd)
      editor.cursorPosition = lineStart
      return
    }

    // 3. Task continuation (- [ ] or - [x]) -> only continue new task if at end of line with text
    var taskMatch = line.match(/^(\s*[-*]\s*)\[[ xX]\]\s+(.+)$/)
    if (taskMatch && isAtEnd) {
      event.accepted = true
      var indent = taskMatch[1].match(/^\s*/)[0]
      editor.insert(pos, "\n" + indent + "- [ ] ")
      return
    }

    // 4. Bullet continuation (- item or * item) -> only continue if at end of line with text
    var bulletMatch = line.match(/^(\s*[-*]\s+)(.+)$/)
    if (bulletMatch && isAtEnd) {
      event.accepted = true
      editor.insert(pos, "\n" + bulletMatch[1])
      return
    }

    // Default: Native plain newline (never intercepts regular text typing)
  }

  // --- Checkbox Toggle (Ctrl+Enter or Toolbar Icon) ---
  function toggleCheckboxAtCursor(editor) {
    var pos = editor.cursorPosition
    var txt = editor.text
    var lineStart = txt.lastIndexOf("\n", pos - 1) + 1
    var lineEnd = txt.indexOf("\n", pos)
    if (lineEnd === -1) lineEnd = txt.length
    var line = txt.substring(lineStart, lineEnd)

    var newLine = ""
    var delta = 0
    if (line.match(/^(\s*[-*]\s*)\[ \]\s*(.*)$/)) {
      newLine = line.replace(/^(\s*[-*]\s*)\[ \]\s*(.*)$/, "$1[x] $2")
    } else if (line.match(/^(\s*[-*]\s*)\[[xX]\]\s*(.*)$/)) {
      newLine = line.replace(/^(\s*[-*]\s*)\[[xX]\]\s*(.*)$/, "$1$2")
    } else if (line.match(/^(\s*)[-*]\s+(.*)$/)) {
      newLine = line.replace(/^(\s*)[-*]\s+(.*)$/, "$1- [ ] $2")
      delta = 4
    } else {
      var leading = line.match(/^\s*/)[0]
      newLine = leading + "- [ ] " + line.substring(leading.length)
      delta = 6
    }

    editor.text = txt.substring(0, lineStart) + newLine + txt.substring(lineEnd)
    editor.cursorPosition = Math.min(pos + delta, lineStart + newLine.length)
  }

  // --- Typora Indentation (Tab / Shift+Tab) ---
  function handleTab(editor, shift) {
    var pos = editor.cursorPosition
    var txt = editor.text
    var lineStart = txt.lastIndexOf("\n", pos - 1) + 1
    var lineEnd = txt.indexOf("\n", pos)
    if (lineEnd === -1) lineEnd = txt.length
    var line = txt.substring(lineStart, lineEnd)

    if (shift) {
      if (line.startsWith("  ")) {
        editor.text = txt.substring(0, lineStart) + line.substring(2) + txt.substring(lineEnd)
        editor.cursorPosition = Math.max(lineStart, pos - 2)
      }
    } else {
      editor.text = txt.substring(0, lineStart) + "  " + line + txt.substring(lineEnd)
      editor.cursorPosition = pos + 2
    }
  }

  // --- Typora Preview Renderer Parser ---
  function refreshParsedItems() {
    var lines = currentText.split("\n")
    var res = []
    var inCodeBlock = false
    var codeLines = []
    var codeStartIdx = -1

    for (var i = 0; i < lines.length; i++) {
      var raw = lines[i]

      // Code blocks
      if (raw.trim().startsWith("```")) {
        if (inCodeBlock) {
          codeLines.push(raw)
          res.push({
            lineIndex: codeStartIdx,
            itemType: "code",
            content: codeLines.join("\n"),
            indent: 0
          })
          codeLines = []
          inCodeBlock = false
        } else {
          inCodeBlock = true
          codeStartIdx = i
          codeLines = [raw]
        }
        continue
      }

      if (inCodeBlock) {
        codeLines.push(raw)
        continue
      }

      // Tasks: - [ ] or - [x]
      var taskMatch = raw.match(/^(\s*[-*]\s*)\[([ xX])\]\s*(.*)$/)
      if (taskMatch) {
        var indentSpaces = taskMatch[1].match(/^\s*/)[0].length
        var content = taskMatch[3]
        var tsMatch = content.match(/\[(?:20)?(\d{2})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})\]/)
        var dueDate = tsMatch ? tsMatch[0] : ""
        var cleanContent = tsMatch ? content.replace(tsMatch[0], "").trim() : content
        res.push({
          lineIndex: i,
          itemType: "task",
          checked: taskMatch[2].toLowerCase() === "x",
          content: content,
          cleanContent: cleanContent,
          dueDate: dueDate,
          indent: Math.floor(indentSpaces / 2)
        })
        continue
      }

      // Headers: # through ######
      var headerMatch = raw.match(/^(#{1,6})\s+(.*)$/)
      if (headerMatch) {
        res.push({
          lineIndex: i,
          itemType: "header",
          level: headerMatch[1].length,
          content: headerMatch[2],
          indent: 0
        })
        continue
      }

      // Bullets: - item or * item
      var bulletMatch = raw.match(/^(\s*[-*]\s+)(.*)$/)
      if (bulletMatch) {
        var indentSpaces = bulletMatch[1].match(/^\s*/)[0].length
        res.push({
          lineIndex: i,
          itemType: "bullet",
          content: bulletMatch[2],
          indent: Math.floor(indentSpaces / 2)
        })
        continue
      }

      // Numbered list: 1. item
      var numMatch = raw.match(/^(\s*)(\d+)\.\s+(.*)$/)
      if (numMatch) {
        res.push({
          lineIndex: i,
          itemType: "numbered",
          num: numMatch[2],
          content: numMatch[3],
          indent: Math.floor(numMatch[1].length / 2)
        })
        continue
      }

      // Blockquotes: > quote
      var quoteMatch = raw.match(/^>\s*(.*)$/)
      if (quoteMatch) {
        res.push({
          lineIndex: i,
          itemType: "quote",
          content: quoteMatch[1],
          indent: 0
        })
        continue
      }

      // Dividers: --- or ***
      if (raw.trim() === "---" || raw.trim() === "***") {
        res.push({ lineIndex: i, itemType: "divider", content: "", indent: 0 })
        continue
      }

      // Regular text (only if not completely blank line)
      if (raw.trim().length > 0) {
        res.push({
          lineIndex: i,
          itemType: "text",
          content: raw,
          indent: 0
        })
      }
    }

    if (inCodeBlock && codeLines.length > 0) {
      res.push({
        lineIndex: codeStartIdx,
        itemType: "code",
        content: codeLines.join("\n"),
        indent: 0
      })
    }

    parsedItems = res
  }

  // Interactive checkbox toggle in preview mode with auto-move
  function toggleTaskAtLine(lineIdx) {
    clearPendingCursor()
    var lines = currentText.split("\n")
    if (lineIdx < 0 || lineIdx >= lines.length) return
    var raw = lines[lineIdx]

    if (raw.match(/^(\s*[-*]\s*)\[ \]/)) {
      // 1. Completing an active task -> move to ### Completed
      var body = raw.replace(/^(\s*[-*]\s*)\[ \]\s*/, "").trim()
      if (body.length === 0) {
        body = "New task"
      }
      var completedLine = "- [x] " + body
      lines.splice(lineIdx, 1)

      var compHeaderIdx = -1
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim().match(/^#{1,6}\s+Completed$/i)) {
          compHeaderIdx = i
          break
        }
      }

      if (compHeaderIdx !== -1) {
        lines.splice(compHeaderIdx + 1, 0, completedLine)
      } else {
        while (lines.length > 0 && lines[lines.length - 1].trim() === "") {
          lines.pop()
        }
        lines.push("")
        lines.push("### Completed")
        lines.push(completedLine)
      }
    } else if (raw.match(/^(\s*[-*]\s*)\[[xX]\]/)) {
      // 2. Uncompleting a task -> move back up to active tasks
      var body = raw.replace(/^(\s*[-*]\s*)\[[xX]\]\s*/, "").trim()
      if (body.length === 0) {
        body = "New task"
      }
      var activeLine = "- [ ] " + body
      lines.splice(lineIdx, 1)

      var compHeaderIdx = -1
      for (var j = 0; j < lines.length; j++) {
        if (lines[j].trim().match(/^#{1,6}\s+Completed$/i)) {
          compHeaderIdx = j
          break
        }
      }

      if (compHeaderIdx !== -1) {
        var insertAt = compHeaderIdx
        while (insertAt > 0 && lines[insertAt - 1].trim() === "") {
          insertAt--
        }
        lines.splice(insertAt, 0, activeLine)
      } else {
        lines.push(activeLine)
      }
    }

    currentText = lines.join("\n")
    if (activeTab === "tasks") {
      tasksText = currentText
    } else {
      scratchpadText = currentText
    }
    if (panel.loadedContent && panel.loadedContent.editor) {
      panel.loadedContent.editor.text = currentText
    }
    refreshParsedItems()
    saveNow()
    if (panel.loadedContent) {
      panel.loadedContent.forceActiveFocus()
    }
  }

  Timer {
    id: saveDebounceTimer
    interval: 350
    repeat: false
    onTriggered: root.saveNow()
  }

  // Auto-shift back to preview mode after user pauses typing in edit mode (Tasks & Scratchpad)
  Timer {
    id: autoPreviewTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (root.viewMode === "edit" && root.opened) {
        root.saveNow()
        root.refreshParsedItems()
        if (root.activeTab === "tasks") {
          root.tasksViewMode = "preview"
          root.persistViewMode("tasks", "preview")
        } else {
          root.scratchpadViewMode = "preview"
          root.persistViewMode("scratchpad", "preview")
        }
        Qt.callLater(function() {
          if (panel.loadedContent) {
            panel.loadedContent.forceActiveFocus()
          }
        })
      }
    }
  }

  FileView {
    id: tasksFile
    path: root.storageDir + "/tasks.md"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var t = text()
      root.tasksText = t
      root.lastSavedTasksText = t
      if (root.activeTab === "tasks") {
        root.syncActiveTabContent(t)
      }
      root.checkTaskReminders()
    }
  }

  FileView {
    id: notifiedRemindersFile
    path: root.storageDir + "/notified_reminders.json"
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed === "object") {
          root.notifiedReminders = parsed
        }
      } catch(e) {
        root.notifiedReminders = ({})
      }
    }
  }

  Timer {
    id: reminderCheckTimer
    interval: 20000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      tasksFile.reload()
      root.checkTaskReminders()
    }
  }

  FileView {
    id: scratchpadFile
    path: root.storageDir + "/scratchpad.md"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var t = text()
      root.scratchpadText = t
      root.lastSavedScratchpadText = t
      if (root.activeTab === "scratchpad") {
        root.syncActiveTabContent(t)
      }
    }
  }

  FileView {
    id: activeTabFile
    path: root.storageDir + "/active_tab.txt"
    printErrors: false
    onLoaded: {
      var t = text().trim()
      if (t === "tasks" || t === "scratchpad") {
        root.activeTab = t
        var targetText = (t === "tasks") ? root.tasksText : root.scratchpadText
        if (targetText) {
          root.syncActiveTabContent(targetText)
        }
      }
    }
  }

  FileView {
    id: tasksViewFile
    path: root.storageDir + "/tasks_view.txt"
    printErrors: false
    onLoaded: {
      var v = text().trim()
      if (v === "preview" || v === "edit") {
        root.tasksViewMode = v
      }
    }
  }

  FileView {
    id: scratchpadViewFile
    path: root.storageDir + "/scratchpad_view.txt"
    printErrors: false
    onLoaded: {
      var v = text().trim()
      if (v === "preview" || v === "edit") {
        root.scratchpadViewMode = v
      }
    }
  }

  Component.onDestruction: {
    root.saveNow()
  }

  onOpenedChanged: {
    if (!opened) {
      root.saveNow()
    }
  }

  ShellIpc {
    target: "arun.scratchpad"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function toggleView(): void { root.toggleViewMode() }
    function clear(): void { root.clearNote() }
    function copy(): void { root.copyAll() }
    function save(): void { root.saveNow() }
    function sweep(): void { root.sweepCompletedTasks() }
    function addTask(): void { root.addNewTaskAtEnd() }
    function switchTab(tab: string): void { root.switchTab(tab) }
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: strings.t("scratchpad.tooltip") + (root.pendingTaskCount > 0 ? (" (" + root.pendingTaskCount + " pending)") : "")
    active: root.opened
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.pendingTaskCount > 0 ? Style.space(38) : Style.bar.iconSlot

    Row {
      anchors.centerIn: parent
      spacing: Style.space(4)
      scale: button.pressScale

      Text {
        text: "󰏪"
        font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
        font.pixelSize: Style.bar.iconFont
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
      }

      Text {
        visible: root.pendingTaskCount > 0
        text: String(root.pendingTaskCount)
        font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.openInEditor()
      } else if (b === Qt.MiddleButton) {
        root.copyAll()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: false
    centerOnBar: true
    // Squarish minimal footprint (~420 x 460) with zero nested borders
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(500))
    focusTarget: panel.loadedContent ? (root.viewMode === "preview" ? panel.loadedContent : panel.loadedContent.editor) : null

    content: Component {
      Item {
        id: cardContent
        anchors.fill: parent
        implicitWidth: Style.space(420)
        implicitHeight: Style.space(460)
        clip: true
        focus: true
        Keys.priority: Keys.BeforeItem
        property alias editor: scratchEdit

        Keys.onPressed: function(event) {
          if (root.editingLineIndex >= 0) {
            // Task inline editing is active; let the focused editor handle input directly
            if (event.key === Qt.Key_Escape) {
              event.accepted = true
              root.commitTaskEdit(root.editingLineIndex, "", false)
              return
            }
            // If cardContent receives a key event while editing is active,
            // immediately redirect focus to the active inline editor:
            root.requestTaskFocus(root.editingLineIndex)
            return
          }
          if (root.viewMode === "preview") {
            if (event.key === Qt.Key_Escape) {
              event.accepted = true
              root.close()
              return
            }
            if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_K) {
              event.accepted = true
              root.sweepCompletedTasks()
              return
            }
            if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
              event.accepted = true
              if (root.pendingLineIndex >= 0) {
                var dir = (event.key === Qt.Key_Up) ? -1 : 1
                if (root.moveTaskLine(root.pendingLineIndex, dir)) {
                  root.pendingLineIndex += dir
                }
              }
              return
            }
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
              event.accepted = true
              root.toggleViewMode(true)
              return
            }
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
              event.accepted = true
              root.shiftToEditAndType(Qt.Key_Return, "")
              return
            }
            if (event.modifiers & Qt.ControlModifier) {
              if (event.key === Qt.Key_1) { event.accepted = true; root.switchTab("tasks"); return }
              if (event.key === Qt.Key_2) { event.accepted = true; root.switchTab("scratchpad"); return }
              return
            }

            // Printable character key, Enter, or Backspace:
            if (root.activeTab === "tasks") {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true
                root.addNewTaskAtEnd()
                return
              }
              if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                event.accepted = true
                root.addNewTaskAtEnd(event.text)
                return
              }
            } else {
              if ((root.autoShiftEnabled || root.pendingCursorPos >= 0 || root.pendingAfterLast) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Backspace || (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32))) {
                event.accepted = true
                root.shiftToEditAndType(event.key, event.text)
                return
              }
            }
          }
        }

        // 1. Header (Clean single bar without redundant title)
        Item {
          id: headerRow
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(28)

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(4)

            // Tabs: Tasks | Scratchpad | Notes
            RowLayout {
              spacing: Style.space(3)

              Repeater {
                model: root.tabNames

                delegate: Rectangle {
                  required property string modelData
                  readonly property bool active: root.activeTab === modelData
                  height: Style.space(24)
                  width: tabLabel.implicitWidth + Style.space(16)
                  radius: Style.space(4)
                  color: active
                    ? Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
                    : (tabHover.containsMouse ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08) : "transparent")

                  Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                    font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: parent.active
                    color: parent.active ? Commons.Color.foreground : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
                    textFormat: Text.PlainText
                  }

                  MouseArea {
                    id: tabHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.switchTab(modelData)
                  }
                }
              }
            }

            Item { Layout.fillWidth: true }

            // Action Buttons
            RowLayout {
              spacing: Style.space(2)

              // Delete Completed Tasks (Ctrl+Shift+K) - Tasks tab only
              PanelActionButton {
                visible: root.activeTab === "tasks"
                iconText: "\uf2ed"
                hoverColor: Commons.Color.urgent
                tooltipText: "Delete Completed Tasks (Ctrl+Shift+K)"
                onClicked: root.sweepCompletedTasks()
              }

              // Copy Note
              PanelActionButton {
                iconText: "\uf0c5"
                tooltipText: strings.t("scratchpad.copy")
                onClicked: root.copyAll()
              }

              // Open in external editor
              PanelActionButton {
                iconText: "\uf08e"
                tooltipText: strings.t("scratchpad.openEditor")
                onClicked: root.openInEditor()
              }
            }
          }
        }

        // Divider below Header
        Rectangle {
          id: headerDivider
          anchors.top: headerRow.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(6)
          height: 1
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)
        }

        // 2. Footer (Guaranteed zero-overlap layout)
        Item {
          id: footerRow
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(24)

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)
          }

          // Left: Word and character counts
          Text {
            id: statsText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.statsString
            font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
            font.pixelSize: Style.font.caption - 1
            color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
            textFormat: Text.PlainText
          }

          // Right: Status indicator (Saved) - anchored right
          Text {
            id: statusText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusMessage
            font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
            font.pixelSize: Style.font.caption - 1
            font.bold: true
            color: Commons.Color.accent
            textFormat: Text.PlainText
          }
        }

        // 3. Body Area (Clean canvas between header and footer)
        Item {
          id: bodyArea
          anchors.top: headerDivider.bottom
          anchors.bottom: footerRow.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(6)
          anchors.bottomMargin: Style.space(4)
          clip: true

          // Mode 1: Clean Typora Editor (Default)
          Flickable {
            id: editFlickable
            anchors.fill: parent
            visible: root.viewMode === "edit"
            contentWidth: width
            contentHeight: Math.max(height, scratchEdit.paintedHeight + Style.space(48))
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: true

            function ensureVisible(r) {
              if (contentY >= r.y)
                contentY = Math.max(0, r.y - Style.space(20))
              else if (contentY + height <= r.y + r.height + Style.space(20))
                contentY = Math.min(contentHeight - height, r.y + r.height + Style.space(20) - height)
            }

            ScrollBar.vertical: ScrollBar {
              id: editScrollBar
              policy: editFlickable.contentHeight > editFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            WheelHandler {
              target: null
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var d = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y / 120 * Style.space(40))
                var maxContentY = Math.max(0, editFlickable.contentHeight - editFlickable.height)
                editFlickable.contentY = Math.max(0, Math.min(maxContentY, editFlickable.contentY - d))
                event.accepted = true
              }
            }

            TextEdit {
              id: scratchEdit
              width: editFlickable.width - Style.space(8)
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              color: Commons.Color.foreground
              selectionColor: Style.selectionFillFor(Commons.Color.foreground, Commons.Color.accent)
              selectedTextColor: Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
              font.pixelSize: Style.font.body
              focus: root.viewMode === "edit"
              text: root.currentText
              onCursorRectangleChanged: editFlickable.ensureVisible(cursorRectangle)

              Text {
                anchors.fill: parent
                visible: !scratchEdit.text && !scratchEdit.inputMethodComposing
                text: strings.t("scratchpad.placeholder")
                color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
                font: scratchEdit.font
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
              }

              onTextChanged: {
                if (text !== root.currentText) {
                  root.onTextEdited(text)
                }
              }

              Keys.onReturnPressed: function(event) {
                root.handleReturn(scratchEdit, event)
              }

              Keys.onTabPressed: function(event) {
                event.accepted = true
                root.handleTab(scratchEdit, false)
              }

              Keys.onBacktabPressed: function(event) {
                event.accepted = true
                root.handleTab(scratchEdit, true)
              }

              Keys.onPressed: function(event) {
                if (root.autoShiftEnabled) {
                  autoPreviewTimer.restart()
                }
                if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_K) {
                  event.accepted = true
                  root.sweepCompletedTasks()
                  return
                }
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_D) {
                  event.accepted = true
                  var ts = root.formatCurrentTimestamp()
                  var p = scratchEdit.cursorPosition
                  var needsSpace = p > 0 && scratchEdit.text.charAt(p - 1) !== " " && scratchEdit.text.charAt(p - 1) !== "\n"
                  var insertStr = (needsSpace ? " " : "") + ts + " "
                  scratchEdit.insert(p, insertStr)
                  scratchEdit.cursorPosition = p + insertStr.length
                  return
                }
                if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                  event.accepted = true
                  root.moveCurrentLine(scratchEdit, (event.key === Qt.Key_Up) ? -1 : 1)
                  return
                }
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                  event.accepted = true
                  root.toggleViewMode(true)
                  return
                }
                if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  event.accepted = true
                  root.toggleCheckboxAtCursor(scratchEdit)
                  return
                }
                if (event.modifiers & Qt.ControlModifier) {
                  if (event.key === Qt.Key_1) { event.accepted = true; root.switchTab("tasks"); return }
                  if (event.key === Qt.Key_2) { event.accepted = true; root.switchTab("scratchpad"); return }
                }
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  root.close()
                  return
                }
              }
            }
          }

          // Mode 2: Typora / Obsidian Rendered Reading View (Clickable Checkboxes & Tap Cursor)
          Flickable {
            id: previewFlickable
            anchors.fill: parent
            visible: root.viewMode === "preview"
            contentWidth: width
            contentHeight: Math.max(height, previewColumnContainer.implicitHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: !root.dragActive

            ScrollBar.vertical: ScrollBar {
              id: previewScrollBar
              policy: previewFlickable.contentHeight > previewFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            WheelHandler {
              target: null
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var d = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y / 120 * Style.space(40))
                var maxContentY = Math.max(0, previewFlickable.contentHeight - previewFlickable.height)
                previewFlickable.contentY = Math.max(0, Math.min(maxContentY, previewFlickable.contentY - d))
                event.accepted = true
              }
            }

            Item {
              id: previewColumnContainer
              width: previewFlickable.width - Style.space(8)
              implicitHeight: previewColumn.implicitHeight + (root.pendingAfterLast && root.activeTab === "tasks" ? Style.space(32) : 0) + Style.space(80)

              function findDropTarget(containerY) {
                if (!previewRepeater || previewRepeater.count === 0) return null
                var count = previewRepeater.count

                var firstChild = previewRepeater.itemAt(0)
                if (firstChild && containerY <= firstChild.y + firstChild.height / 2) {
                  var firstData = root.parsedItems[0]
                  return {
                    index: 0,
                    lineIndex: firstData ? firstData.lineIndex : 0,
                    dropBefore: true
                  }
                }

                for (var i = 0; i < count; i++) {
                  var child = previewRepeater.itemAt(i)
                  if (child) {
                    var topY = child.y
                    var bottomY = child.y + child.height
                    var midY = child.y + child.height / 2

                    if (containerY >= topY && containerY <= bottomY) {
                      var itmData = root.parsedItems[i]
                      return {
                        index: i,
                        lineIndex: itmData ? itmData.lineIndex : -1,
                        dropBefore: containerY < midY
                      }
                    }
                  }
                }

                var lastIdx = count - 1
                var lastData = root.parsedItems[lastIdx]
                return {
                  index: lastIdx,
                  lineIndex: lastData ? lastData.lineIndex : -1,
                  dropBefore: false
                }
              }

              Column {
                id: previewColumn
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  id: previewRepeater
                  model: root.parsedItems

                  delegate: Item {
                    id: delegateItem
                    required property int index
                    required property var modelData
                    width: previewColumn.width
                    implicitHeight: loader.implicitHeight
                    opacity: root.dragActive && root.draggedItemIndex === index ? 0.25 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    // Drop indicator line (Top)
                    Rectangle {
                      anchors.top: parent.top
                      anchors.topMargin: -Style.space(3)
                      anchors.left: parent.left
                      anchors.right: parent.right
                      height: 2
                      radius: 1
                      color: Commons.Color.accent
                      visible: root.dragActive && root.dropTargetIndex === index && root.dropBefore && root.draggedItemIndex !== index
                      z: 100

                      Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(6)
                        height: Style.space(6)
                        radius: Style.space(3)
                        color: Commons.Color.accent
                      }
                    }

                    // Drop indicator line (Bottom)
                    Rectangle {
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: -Style.space(3)
                      anchors.left: parent.left
                      anchors.right: parent.right
                      height: 2
                      radius: 1
                      color: Commons.Color.accent
                      visible: root.dragActive && root.dropTargetIndex === index && !root.dropBefore && root.draggedItemIndex !== index
                      z: 100

                      Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(6)
                        height: Style.space(6)
                        radius: Style.space(3)
                        color: Commons.Color.accent
                      }
                    }

                    Loader {
                      id: loader
                      width: parent.width
                      focus: true

                      sourceComponent: {
                        if (modelData.itemType === "task") return taskPreviewDelegate
                        if (modelData.itemType === "header") return headerPreviewDelegate
                        if (modelData.itemType === "bullet") return bulletPreviewDelegate
                        if (modelData.itemType === "numbered") return numberedPreviewDelegate
                        if (modelData.itemType === "quote") return quotePreviewDelegate
                        if (modelData.itemType === "code") return codePreviewDelegate
                        if (modelData.itemType === "divider") return dividerPreviewDelegate
                        return textPreviewDelegate
                      }
                    }

                    // 1. Interactive Checkbox Task (Todoist-style 6-dot drag handle, checkbox, inline editable text & timestamp)
                    Component {
                      id: taskPreviewDelegate

                      RowLayout {
                        id: taskRowLayout
                        width: previewColumn.width
                        spacing: Style.space(6)

                        readonly property bool isEditingThisTask: root.editingLineIndex === modelData.lineIndex

                        HoverHandler {
                          id: rowHover
                        }

                        Item {
                          width: modelData.indent * Style.space(12)
                          height: 1
                          visible: modelData.indent > 0
                        }

                        // Todoist-style 6-dot vertical grab handle
                        Item {
                          id: dragHandle
                          Layout.alignment: Qt.AlignTop
                          Layout.topMargin: Style.space(2)
                          width: Style.space(12)
                          height: Style.space(16)
                          opacity: taskRowLayout.isEditingThisTask ? 0.2 : (rowHover.hovered || dragMouseArea.pressed ? 0.9 : 0.2)
                          Behavior on opacity { NumberAnimation { duration: 150 } }

                          Grid {
                            anchors.centerIn: parent
                            columns: 2
                            rowSpacing: Style.space(2)
                            columnSpacing: Style.space(2)

                            Repeater {
                              model: 6
                              Rectangle {
                                width: Style.space(2)
                                height: Style.space(2)
                                radius: Style.space(1)
                                color: dragMouseArea.pressed ? Commons.Color.accent : Commons.Color.foreground
                              }
                            }
                          }

                          MouseArea {
                            id: dragMouseArea
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            hoverEnabled: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            preventStealing: true

                            property real startPressY: 0
                            property bool isDragging: false

                            onPressed: function(mouse) {
                              startPressY = mouse.y
                              isDragging = false
                              root.draggedLineIndex = modelData.lineIndex
                              root.draggedItemIndex = index
                              root.draggedContent = (modelData.cleanContent !== undefined && modelData.cleanContent.length > 0) ? modelData.cleanContent : modelData.content
                              root.draggedChecked = modelData.checked
                              root.draggedDueDate = modelData.dueDate || ""
                              root.dropTargetIndex = index
                              root.dropTargetLineIndex = modelData.lineIndex
                              root.dropBefore = true

                              var ptInCard = dragHandle.mapToItem(cardContent, mouse.x, mouse.y)
                              root.dragGhostY = ptInCard.y - Style.space(17)
                            }

                            onPositionChanged: function(mouse) {
                              if (!pressed) return

                              if (!isDragging) {
                                if (Math.abs(mouse.y - startPressY) >= Style.space(3) || Math.abs(mouse.x) >= Style.space(3)) {
                                  isDragging = true
                                  root.dragActive = true
                                  previewFlickable.interactive = false
                                } else {
                                  return
                                }
                              }

                              var ptInCard = dragHandle.mapToItem(cardContent, mouse.x, mouse.y)
                              root.dragGhostY = ptInCard.y - Style.space(17)

                              // Auto-scroll Flickable
                              var ptInFlickable = dragHandle.mapToItem(previewFlickable, mouse.x, mouse.y)
                              var scrollZone = Style.space(40)
                              if (ptInFlickable.y < scrollZone) {
                                previewFlickable.contentY = Math.max(0, previewFlickable.contentY - Style.space(12))
                              } else if (ptInFlickable.y > previewFlickable.height - scrollZone) {
                                var maxScroll = Math.max(0, previewFlickable.contentHeight - previewFlickable.height)
                                previewFlickable.contentY = Math.min(maxScroll, previewFlickable.contentY + Style.space(12))
                              }

                              // Calculate drop slot
                              var ptInContainer = dragHandle.mapToItem(previewColumnContainer, mouse.x, mouse.y)
                              var targetInfo = previewColumnContainer.findDropTarget(ptInContainer.y)
                              if (targetInfo) {
                                root.dropTargetIndex = targetInfo.index
                                root.dropTargetLineIndex = targetInfo.lineIndex
                                root.dropBefore = targetInfo.dropBefore
                              }
                            }

                            onReleased: function(mouse) {
                              var wasDragging = isDragging && root.dragActive
                              var fromLine = root.draggedLineIndex
                              var targetLine = root.dropTargetLineIndex
                              var dropBefore = root.dropBefore

                              // 1. Immediately dismiss all drag state on root before model mutation
                              isDragging = false
                              root.dragActive = false
                              previewFlickable.interactive = true
                              root.draggedItemIndex = -1
                              root.draggedLineIndex = -1
                              root.dropTargetIndex = -1
                              root.dropTargetLineIndex = -1

                              // 2. Commit drop asynchronously so delegate destruction cannot interrupt state cleanup
                              if (wasDragging && fromLine >= 0 && targetLine >= 0) {
                                Qt.callLater(function() {
                                  root.applyTaskDrop(fromLine, targetLine, dropBefore)
                                })
                              }
                            }

                            onCanceled: {
                              isDragging = false
                              root.dragActive = false
                              previewFlickable.interactive = true
                              root.draggedItemIndex = -1
                              root.draggedLineIndex = -1
                              root.dropTargetIndex = -1
                              root.dropTargetLineIndex = -1
                            }
                          }
                        }

                        // Checkbox
                        Rectangle {
                          id: taskCheckbox
                          Layout.alignment: Qt.AlignTop
                          Layout.topMargin: Style.space(2)
                          width: Style.space(16)
                          height: Style.space(16)
                          radius: Style.space(3)
                          color: modelData.checked
                            ? Commons.Color.accent
                            : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)
                          border.color: modelData.checked ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)
                          border.width: 1

                          Text {
                            anchors.centerIn: parent
                            text: "✓"
                            visible: modelData.checked
                            font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                            font.pixelSize: Style.font.caption - 1
                            font.bold: true
                            color: Commons.Color.background
                            textFormat: Text.PlainText
                          }

                          MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleTaskAtLine(modelData.lineIndex)
                          }
                        }

                        // Task Text Column: Toggle between interactive display and inline editing
                        ColumnLayout {
                          Layout.fillWidth: true
                          Layout.alignment: Qt.AlignTop
                          Layout.topMargin: Style.space(2)
                          spacing: Style.space(2)

                          Item {
                            id: editorItem
                            Layout.fillWidth: true
                            implicitHeight: Math.max(Style.space(16), taskRowLayout.isEditingThisTask ? inlineInput.paintedHeight : staticText.paintedHeight)

                            // 1. Inline edit field (active when clicked or new task added)
                            TextEdit {
                              id: inlineInput
                              anchors.fill: parent
                              visible: taskRowLayout.isEditingThisTask
                              focus: taskRowLayout.isEditingThisTask
                              text: modelData.content || ""
                              font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                              font.pixelSize: Style.font.body
                              color: Commons.Color.foreground
                              wrapMode: TextEdit.Wrap
                              textFormat: TextEdit.PlainText
                              selectByMouse: true
                              selectionColor: Style.selectionFillFor(Commons.Color.foreground, Commons.Color.accent)
                              selectedTextColor: Commons.Color.foreground
                              cursorVisible: activeFocus

                              Text {
                                anchors.fill: parent
                                visible: !inlineInput.text && !inlineInput.inputMethodComposing
                                text: "New task..."
                                color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
                                font: inlineInput.font
                                wrapMode: Text.Wrap
                              }

                              Component.onCompleted: {
                                if (taskRowLayout.isEditingThisTask) {
                                  Qt.callLater(function() {
                                    inlineInput.forceActiveFocus()
                                    var pos = (root.pendingCharOffset >= 0) ? root.pendingCharOffset : inlineInput.text.length
                                    inlineInput.cursorPosition = Math.min(inlineInput.text.length, Math.max(0, pos))
                                  })
                                }
                              }

                              onVisibleChanged: {
                                if (visible) {
                                  Qt.callLater(function() {
                                    inlineInput.forceActiveFocus()
                                    var pos = (root.pendingCharOffset >= 0) ? root.pendingCharOffset : inlineInput.text.length
                                    inlineInput.cursorPosition = Math.min(inlineInput.text.length, Math.max(0, pos))
                                  })
                                }
                              }

                              Keys.onReturnPressed: function(event) {
                                event.accepted = true
                                root.commitTaskEdit(modelData.lineIndex, inlineInput.text, true)
                              }

                              Keys.onEnterPressed: function(event) {
                                event.accepted = true
                                root.commitTaskEdit(modelData.lineIndex, inlineInput.text, true)
                              }

                              Keys.onEscapePressed: function(event) {
                                event.accepted = true
                                if (inlineInput.text.trim().length === 0) {
                                  root.deleteTaskAtLine(modelData.lineIndex)
                                } else {
                                  root.commitTaskEdit(modelData.lineIndex, inlineInput.text, false)
                                }
                              }

                              Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Backspace && inlineInput.text.length === 0) {
                                  event.accepted = true
                                  root.deleteTaskAtLine(modelData.lineIndex)
                                  return
                                }
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_D) {
                                  event.accepted = true
                                  var ts = root.formatCurrentTimestamp()
                                  var p = cursorPosition
                                  var needsSpace = p > 0 && text.charAt(p - 1) !== " "
                                  var ins = (needsSpace ? " " : "") + ts + " "
                                  insert(p, ins)
                                  cursorPosition = p + ins.length
                                  return
                                }
                              }

                              onActiveFocusChanged: {
                                if (!activeFocus && taskRowLayout.isEditingThisTask) {
                                  root.commitTaskEdit(modelData.lineIndex, inlineInput.text, false)
                                }
                              }
                            }

                            // 2. Static text view (single-click to edit)
                            Text {
                              id: staticText
                              anchors.fill: parent
                              visible: !taskRowLayout.isEditingThisTask
                              text: (modelData.cleanContent !== undefined && modelData.cleanContent.length > 0) ? modelData.cleanContent : (modelData.content || "New task")
                              font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                              font.pixelSize: Style.font.body
                              font.strikeout: modelData.checked
                              color: (modelData.content && modelData.content.length > 0)
                                ? (modelData.checked ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45) : Commons.Color.foreground)
                                : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
                              wrapMode: Text.Wrap

                              MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: function(mouse) {
                                  root.pendingCharOffset = staticText.text.length
                                  root.editingLineIndex = modelData.lineIndex
                                  Qt.callLater(function() {
                                    root.requestTaskFocus(modelData.lineIndex)
                                  })
                                }
                                onDoubleClicked: root.toggleViewMode(true)
                              }
                            }
                          }

                          Connections {
                            target: root
                            function onRequestTaskFocus(targetLine) {
                              if (modelData.lineIndex === targetLine) {
                                inlineInput.forceActiveFocus()
                                var pos = (root.pendingCharOffset >= 0) ? root.pendingCharOffset : inlineInput.text.length
                                inlineInput.cursorPosition = Math.min(inlineInput.text.length, Math.max(0, pos))
                              }
                            }
                            function onEditingLineIndexChanged() {
                              if (root.editingLineIndex === modelData.lineIndex) {
                                Qt.callLater(function() {
                                  if (inlineInput) {
                                    inlineInput.forceActiveFocus()
                                    var pos = (root.pendingCharOffset >= 0) ? root.pendingCharOffset : inlineInput.text.length
                                    inlineInput.cursorPosition = Math.min(inlineInput.text.length, Math.max(0, pos))
                                  }
                                })
                              }
                            }
                          }

                          // Todoist-style Due Date Badge
                          Item {
                            id: dueDateItem
                            visible: !taskRowLayout.isEditingThisTask && modelData.dueDate !== undefined && modelData.dueDate.length > 0
                            implicitWidth: dueDateLayout.implicitWidth
                            implicitHeight: dueDateLayout.implicitHeight

                            readonly property bool isOverdue: {
                              if (!modelData.dueDate) return false
                              var m = modelData.dueDate.match(/\[(?:20)?(\d{2})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})\]/)
                              if (!m) return false
                              var d = new Date(2000 + parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), parseInt(m[4], 10), parseInt(m[5], 10))
                              return d.getTime() < Date.now()
                            }

                            RowLayout {
                              id: dueDateLayout
                              anchors.fill: parent
                              spacing: Style.space(4)

                              Text {
                                text: "\uf073"
                                font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                                font.pixelSize: Style.font.caption - 2
                                color: modelData.checked
                                  ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.4)
                                  : (dueDateItem.isOverdue ? Commons.Color.urgent : Commons.Color.accent)
                                textFormat: Text.PlainText
                              }

                              Text {
                                text: modelData.dueDate ? modelData.dueDate.slice(1, -1) : ""
                                font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                                font.pixelSize: Style.font.caption - 2
                                font.bold: dueDateItem.isOverdue && !modelData.checked
                                color: modelData.checked
                                  ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.4)
                                  : (dueDateItem.isOverdue ? Commons.Color.urgent : Commons.Color.accent)
                                textFormat: Text.PlainText
                              }
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                var tsPos = modelData.content.indexOf(modelData.dueDate)
                                root.pendingCharOffset = (tsPos >= 0) ? (tsPos + 1) : 0
                                root.editingLineIndex = modelData.lineIndex
                                Qt.callLater(function() {
                                  root.requestTaskFocus(modelData.lineIndex)
                                })
                              }
                            }
                          }
                        }
                      }
                    }

                    // 2. Header
                    Component {
                      id: headerPreviewDelegate

                      Item {
                        width: previewColumn.width
                        implicitHeight: headerEdit.paintedHeight + Style.space(6)

                        TextEdit {
                          id: headerEdit
                          anchors.fill: parent
                          anchors.topMargin: Style.space(4)
                          anchors.bottomMargin: Style.space(2)
                          text: modelData.content
                          font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                          font.pixelSize: modelData.level === 1 ? Style.font.title + Style.space(2) : (modelData.level === 2 ? Style.font.title : Style.font.body + Style.space(2))
                          font.bold: true
                          color: modelData.level === 1 ? Commons.Color.accent : Commons.Color.foreground
                          wrapMode: TextEdit.Wrap
                          textFormat: TextEdit.PlainText
                          readOnly: true
                          selectByMouse: false
                          activeFocusOnTab: false
                          cursorVisible: false
                        }

                        Rectangle {
                          id: headerCursor
                          visible: root.viewMode === "preview" && root.pendingLineIndex === modelData.lineIndex && root.pendingCharOffset >= 0
                          property var curRect: headerEdit.positionToRectangle(Math.min(headerEdit.text.length, Math.max(0, root.pendingCharOffset)))
                          x: curRect ? curRect.x : 0
                          y: curRect ? (curRect.y + Style.space(4)) : Style.space(4)
                          width: 2
                          height: curRect ? Math.max(Style.space(16), curRect.height) : Style.space(16)
                          color: Commons.Color.accent

                          SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: headerCursor.visible
                            PropertyAnimation { to: 0.1; duration: 500 }
                            PropertyAnimation { to: 1.0; duration: 500 }
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.IBeamCursor
                          onClicked: function(mouse) {
                            var pos = headerEdit.positionAt(mouse.x, mouse.y)
                            root.setPendingCursorOnLine(modelData.lineIndex, modelData.itemType, pos)
                          }
                          onDoubleClicked: root.toggleViewMode(true)
                        }
                      }
                    }

                    // 3. Bullet
                    Component {
                      id: bulletPreviewDelegate

                      RowLayout {
                        width: previewColumn.width
                        spacing: Style.space(8)

                        Item {
                          width: modelData.indent * Style.space(12)
                          height: 1
                          visible: modelData.indent > 0
                        }

                        Text {
                          Layout.alignment: Qt.AlignTop
                          Layout.topMargin: Style.space(1)
                          text: "•"
                          font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                          font.pixelSize: Style.font.body
                          color: Commons.Color.accent
                          textFormat: Text.PlainText
                        }

                        Item {
                          Layout.fillWidth: true
                          implicitHeight: bulletEdit.paintedHeight

                          TextEdit {
                            id: bulletEdit
                            anchors.fill: parent
                            text: modelData.content
                            font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                            font.pixelSize: Style.font.body
                            color: Commons.Color.foreground
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: false
                            activeFocusOnTab: false
                            cursorVisible: false
                          }

                          Rectangle {
                            id: bulletCursor
                            visible: root.viewMode === "preview" && root.pendingLineIndex === modelData.lineIndex && root.pendingCharOffset >= 0
                            property var curRect: bulletEdit.positionToRectangle(Math.min(bulletEdit.text.length, Math.max(0, root.pendingCharOffset)))
                            x: curRect ? curRect.x : 0
                            y: curRect ? curRect.y : 0
                            width: 2
                            height: curRect ? Math.max(Style.space(14), curRect.height) : Style.space(14)
                            color: Commons.Color.accent

                            SequentialAnimation on opacity {
                              loops: Animation.Infinite
                              running: bulletCursor.visible
                              PropertyAnimation { to: 0.1; duration: 500 }
                              PropertyAnimation { to: 1.0; duration: 500 }
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: function(mouse) {
                              var pos = bulletEdit.positionAt(mouse.x, mouse.y)
                              root.setPendingCursorOnLine(modelData.lineIndex, modelData.itemType, pos)
                            }
                            onDoubleClicked: root.toggleViewMode(true)
                          }
                        }
                      }
                    }

                    // 4. Numbered List
                    Component {
                      id: numberedPreviewDelegate

                      RowLayout {
                        width: previewColumn.width
                        spacing: Style.space(8)

                        Item {
                          width: modelData.indent * Style.space(12)
                          height: 1
                          visible: modelData.indent > 0
                        }

                        Text {
                          Layout.alignment: Qt.AlignTop
                          Layout.topMargin: Style.space(1)
                          text: modelData.num + "."
                          font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                          font.pixelSize: Style.font.body
                          color: Commons.Color.accent
                          textFormat: Text.PlainText
                        }

                        Item {
                          Layout.fillWidth: true
                          implicitHeight: numEdit.paintedHeight

                          TextEdit {
                            id: numEdit
                            anchors.fill: parent
                            text: modelData.content
                            font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                            font.pixelSize: Style.font.body
                            color: Commons.Color.foreground
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: false
                            activeFocusOnTab: false
                            cursorVisible: false
                          }

                          Rectangle {
                            id: numCursor
                            visible: root.viewMode === "preview" && root.pendingLineIndex === modelData.lineIndex && root.pendingCharOffset >= 0
                            property var curRect: numEdit.positionToRectangle(Math.min(numEdit.text.length, Math.max(0, root.pendingCharOffset)))
                            x: curRect ? curRect.x : 0
                            y: curRect ? curRect.y : 0
                            width: 2
                            height: curRect ? Math.max(Style.space(14), curRect.height) : Style.space(14)
                            color: Commons.Color.accent

                            SequentialAnimation on opacity {
                              loops: Animation.Infinite
                              running: numCursor.visible
                              PropertyAnimation { to: 0.1; duration: 500 }
                              PropertyAnimation { to: 1.0; duration: 500 }
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: function(mouse) {
                              var pos = numEdit.positionAt(mouse.x, mouse.y)
                              root.setPendingCursorOnLine(modelData.lineIndex, modelData.itemType, pos)
                            }
                            onDoubleClicked: root.toggleViewMode(true)
                          }
                        }
                      }
                    }

                    // 5. Blockquote
                    Component {
                      id: quotePreviewDelegate

                      RowLayout {
                        width: previewColumn.width
                        spacing: Style.space(8)

                        Rectangle {
                          Layout.fillHeight: true
                          Layout.preferredWidth: Style.space(3)
                          radius: Style.space(1)
                          color: Commons.Color.accent
                        }

                        Item {
                          Layout.fillWidth: true
                          implicitHeight: quoteEdit.paintedHeight

                          TextEdit {
                            id: quoteEdit
                            anchors.fill: parent
                            text: modelData.content
                            font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                            font.pixelSize: Style.font.body
                            font.italic: true
                            color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.75)
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: false
                            activeFocusOnTab: false
                            cursorVisible: false
                          }

                          Rectangle {
                            id: quoteCursor
                            visible: root.viewMode === "preview" && root.pendingLineIndex === modelData.lineIndex && root.pendingCharOffset >= 0
                            property var curRect: quoteEdit.positionToRectangle(Math.min(quoteEdit.text.length, Math.max(0, root.pendingCharOffset)))
                            x: curRect ? curRect.x : 0
                            y: curRect ? curRect.y : 0
                            width: 2
                            height: curRect ? Math.max(Style.space(14), curRect.height) : Style.space(14)
                            color: Commons.Color.accent

                            SequentialAnimation on opacity {
                              loops: Animation.Infinite
                              running: quoteCursor.visible
                              PropertyAnimation { to: 0.1; duration: 500 }
                              PropertyAnimation { to: 1.0; duration: 500 }
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: function(mouse) {
                              var pos = quoteEdit.positionAt(mouse.x, mouse.y)
                              root.setPendingCursorOnLine(modelData.lineIndex, modelData.itemType, pos)
                            }
                            onDoubleClicked: root.toggleViewMode(true)
                          }
                        }
                      }
                    }

                    // 6. Code Block
                    Component {
                      id: codePreviewDelegate

                      Rectangle {
                        width: previewColumn.width
                        implicitHeight: codeText.implicitHeight + Style.space(12)
                        radius: Style.cornerRadius
                        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.05)

                        Text {
                          id: codeText
                          anchors.fill: parent
                          anchors.margins: Style.space(6)
                          text: modelData.content
                          font.family: Style.font.monospace
                          font.pixelSize: Style.font.caption
                          color: Commons.Color.foreground
                          wrapMode: Text.Wrap
                          textFormat: Text.PlainText
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.IBeamCursor
                          onClicked: root.setPendingCursorOnLine(modelData.lineIndex, modelData.itemType, 0)
                          onDoubleClicked: root.toggleViewMode(true)
                        }
                      }
                    }

                    // 7. Divider
                    Component {
                      id: dividerPreviewDelegate

                      Rectangle {
                        width: previewColumn.width
                        height: 1
                        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)
                      }
                    }

                    // 8. Plain Text
                    Component {
                      id: textPreviewDelegate

                      Item {
                        width: previewColumn.width
                        implicitHeight: textEdit.paintedHeight

                        TextEdit {
                          id: textEdit
                          anchors.fill: parent
                          text: modelData.content
                          font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                          font.pixelSize: Style.font.body
                          color: Commons.Color.foreground
                          wrapMode: TextEdit.Wrap
                          textFormat: TextEdit.PlainText
                          readOnly: true
                          selectByMouse: false
                          activeFocusOnTab: false
                          cursorVisible: false
                        }

                        Rectangle {
                          id: textCursor
                          visible: root.viewMode === "preview" && root.pendingLineIndex === modelData.lineIndex && root.pendingCharOffset >= 0
                          property var curRect: textEdit.positionToRectangle(Math.min(textEdit.text.length, Math.max(0, root.pendingCharOffset)))
                          x: curRect ? curRect.x : 0
                          y: curRect ? curRect.y : 0
                          width: 2
                          height: curRect ? Math.max(Style.space(14), curRect.height) : Style.space(14)
                          color: Commons.Color.accent

                          SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: textCursor.visible
                            PropertyAnimation { to: 0.1; duration: 500 }
                            PropertyAnimation { to: 1.0; duration: 500 }
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.IBeamCursor
                          onClicked: function(mouse) {
                            var pos = textEdit.positionAt(mouse.x, mouse.y)
                            root.setPendingCursorOnLine(modelData.lineIndex, modelData.itemType, pos)
                          }
                          onDoubleClicked: root.toggleViewMode(true)
                        }
                      }
                    }
                  }
                }
              }

              // "+ Add task" button row (Todoist style)
              Item {
                anchors.top: previewColumn.bottom
                anchors.topMargin: Style.space(8)
                anchors.left: parent.left
                width: parent.width
                height: Style.space(26)
                visible: root.viewMode === "preview" && root.activeTab === "tasks"

                RowLayout {
                  anchors.fill: parent
                  spacing: Style.space(6)

                  // Spacer matching dragHandle (width 12)
                  Item {
                    width: Style.space(12)
                    height: 1
                  }

                  // 16x16 container matching Checkbox column with centered "+"
                  Item {
                    Layout.alignment: Qt.AlignVCenter
                    width: Style.space(16)
                    height: Style.space(16)

                    Text {
                      anchors.centerIn: parent
                      text: "+"
                      font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      color: addMouse.containsMouse ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
                    }
                  }

                  Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: "Add task"
                    font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                    font.pixelSize: Style.font.body
                    color: addMouse.containsMouse ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
                  }

                  Item { Layout.fillWidth: true }
                }

                MouseArea {
                  id: addMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.addNewTaskAtEnd()
                }
              }

              // MouseArea covering the blank space below all items to add or start typing
              MouseArea {
                anchors.top: previewColumn.bottom
                anchors.topMargin: Style.space(38)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                cursorShape: Qt.IBeamCursor
                onClicked: {
                  if (root.activeTab === "tasks") {
                    root.addNewTaskAtEnd()
                  } else {
                    root.setPendingCursorAfterLast()
                  }
                }
                onDoubleClicked: root.toggleViewMode(true)
              }
            }
          }
        }

        // Floating Drag Proxy Card (Detached from flickable, elevated across entire panel at z: 99999)
        Rectangle {
          id: floatingDragProxy
          visible: root.dragActive
          x: Style.space(12)
          y: Math.max(headerRow.height + Style.space(4), Math.min(cardContent.height - footerRow.height - Style.space(38), root.dragGhostY))
          width: cardContent.width - Style.space(24)
          height: Style.space(34)
          z: 99999
          radius: Style.cornerRadius
          color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.95)
          border.color: Commons.Color.accent
          border.width: 1.5
          scale: 1.02

          Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: Style.cornerRadius + 1
            color: "transparent"
            border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.3)
            border.width: 1
            z: -1
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(6)

            Grid {
              Layout.alignment: Qt.AlignVCenter
              columns: 2
              rowSpacing: Style.space(2)
              columnSpacing: Style.space(2)
              Repeater {
                model: 6
                Rectangle {
                  width: Style.space(2)
                  height: Style.space(2)
                  radius: Style.space(1)
                  color: Commons.Color.accent
                }
              }
            }

            Rectangle {
              Layout.alignment: Qt.AlignVCenter
              width: Style.space(16)
              height: Style.space(16)
              radius: Style.space(3)
              color: root.draggedChecked ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)
              border.color: Commons.Color.accent
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "✓"
                visible: root.draggedChecked
                font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.caption - 1
                font.bold: true
                color: Commons.Color.background
                textFormat: Text.PlainText
              }
            }

            Text {
              text: root.draggedContent
              font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
              font.pixelSize: Style.font.body
              font.strikeout: root.draggedChecked
              color: root.draggedChecked
                ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
                : Commons.Color.foreground
              elide: Text.ElideRight
              Layout.fillWidth: true
              textFormat: Text.PlainText
            }

            RowLayout {
              visible: root.draggedDueDate.length > 0
              spacing: Style.space(4)

              Text {
                text: "\uf073"
                font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.caption - 2
                color: Commons.Color.accent
                textFormat: Text.PlainText
              }

              Text {
                text: root.draggedDueDate.length > 2 ? root.draggedDueDate.slice(1, -1) : ""
                font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.caption - 2
                color: Commons.Color.accent
                textFormat: Text.PlainText
              }
            }
          }
        }
      }
    }
  }
}
