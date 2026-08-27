import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "TasksModel.js" as TasksModel

Item {
  id: root

  property bool opened: false
  property bool clearConfirmOpen: false
  property var tasks: []
  property string composeText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  property string tasksPath: Quickshell.env("HOME") + "/.local/state/omarchy/tasks.json"
  // Reading tasksPath goes through read-tasks.py rather than letting
  // FileView touch it directly: that path is predictable, and a symlink or
  // FIFO planted there could make the shared shell process follow an
  // arbitrary file, block on open(), or read an unbounded amount of data.
  // The script opens it with O_NOFOLLOW|O_NONBLOCK and checks the resulting
  // descriptor is a regular file before reading a capped number of bytes.
  // Qt.resolvedUrl percent-encodes anything outside plain ASCII (spaces,
  // accented characters), which a real path never is, so decode it back
  // before handing it to Process — otherwise an install path like
  // "/home/josé mota/..." breaks the read entirely.
  property string readScript: decodeURIComponent(String(Qt.resolvedUrl("read-tasks.py")).replace(/^file:\/\//, ""))

  // Background/text share the [menu] surface tokens (same as Clipboard);
  // the border uses [popups] instead, which defaults to the theme's accent
  // color — the same color Hyprland uses for active window borders — so
  // this card visually connects to the rest of the desktop instead of
  // sitting there with a plain foreground-colored edge.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.popups.border
  property var borderSpec: Border.surfaceSpec("popups", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int composeHeight: Math.max(Style.space(28), Style.font.body + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(40), Style.font.title + Style.spacing.rowPaddingX * 2)

  function open(payloadJson) {
    root.opened = true
    root.composeText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.clearConfirmOpen = false
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function loadTasks(raw) {
    root.tasks = TasksModel.parseTasks(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function saveTasks() {
    tasksFile.setText(TasksModel.serializeTasks(root.tasks))
  }

  function rebuildDisplay() {
    var rows = TasksModel.displayRows(root.tasks)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) displayModel.append(rows[i])

    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) taskList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setCompose(text) {
    root.composeText = text
  }

  function commitCompose() {
    var text = root.composeText.trim()
    if (!text) return
    root.tasks = TasksModel.addTask(root.tasks, text)
    root.saveTasks()
    root.composeText = ""
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    taskList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function toggleIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.tasks = TasksModel.toggleTaskAt(root.tasks, row.taskIndex)
    root.saveTasks()
    root.rebuildDisplay()
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.tasks = TasksModel.removeTaskAt(root.tasks, row.taskIndex)
    root.saveTasks()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function requestClearCompleted() {
    if (TasksModel.doneCount(root.tasks) === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearCompleted() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearCompleted() {
    root.tasks = TasksModel.clearCompleted(root.tasks)
    root.saveTasks()
    root.selectedIndex = 0
    root.cursorActive = false
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  // saveTasks() calls setText(), which writes through a temp file and
  // rename (atomicWrites), so a reader never sees a half-written file.
  // Actual reading never touches text()/reload() here (see readProc
  // below) — watchChanges only re-triggers the safe read below when the
  // file changes on disk, e.g. if the user edits or deletes it by hand
  // while the shell is running.
  FileView {
    id: tasksFile
    path: root.tasksPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: readProc.running = true
  }

  Process {
    id: readProc
    command: ["python3", root.readScript, root.tasksPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadTasks(text)
    }
    // Fires if read-tasks.py starts but exits non-zero. Not user-facing —
    // the task list just reads as empty in that case — but logging means
    // it shows up in `qs log`/journalctl instead of vanishing without a
    // trace. Quickshell's Process doesn't expose a QML signal for the
    // process failing to start at all (e.g. python3 missing from PATH
    // entirely), so that specific failure stays silent; it's the same gap
    // Omarchy's own first-party plugins leave open for their Process
    // components.
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) console.warn("Simple Task: read-tasks.py exited with code " + exitCode)
    }
  }

  Component.onCompleted: readProc.running = true

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-tasks"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.composeText) root.setCompose("")
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.composeText)) {
            root.setCompose(Util.editedFilter(event, root.composeText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) root.requestClearCompleted()
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.composeText.trim().length > 0) root.commitCompose()
            else if (root.cursorActive) root.toggleIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setCompose(root.composeText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm

          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Clear completed tasks?"
          confirmText: "Clear"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearCompleted()
          onConfirmed: root.confirmClearCompleted()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Row {
          width: parent.width
          height: root.headerHeight

          Text {
            width: parent.width - countText.width
            anchors.verticalCenter: parent.verticalCenter
            text: "Tasks"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: countText
            anchors.verticalCenter: parent.verticalCenter
            text: TasksModel.pendingCount(root.tasks) + " pending"
            color: root.foreground
            opacity: 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          width: parent.width
          height: root.composeHeight
          radius: root.cornerRadius
          color: Util.alpha(root.foreground, 0.06)
          border.color: Util.alpha(root.foreground, 0.18)
          border.width: Style.normalBorderWidth

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            text: root.composeText.length > 0 ? root.composeText + "▏" : "Type a task and press Enter…"
            color: root.foreground
            opacity: root.composeText.length > 0 ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.composeHeight - root.contentSpacing * 2
          clip: true

          ListView {
            id: taskList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property int index
              required property int taskIndex
              required property string text
              required property bool done

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Rectangle {
                  id: checkbox
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: Style.space(4)
                  color: row.done ? Color.accent : "transparent"
                  border.color: row.done ? Color.accent : Util.alpha(row.hasCursor ? root.selectedText : root.foreground, 0.5)
                  border.width: Style.normalBorderWidth

                  Text {
                    anchors.centerIn: parent
                    visible: row.done
                    text: "✓"
                    color: root.background
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Text {
                  width: parent.width - checkbox.width - deleteGlyph.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.text
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.done ? 0.5 : 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.strikeout: row.done
                  elide: Text.ElideRight
                }

                Text {
                  id: deleteGlyph
                  anchors.verticalCenter: parent.verticalCenter
                  visible: rowMouse.containsMouse || row.hasCursor
                  text: "✕"
                  color: Util.alpha(row.hasCursor ? root.selectedText : root.foreground, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption

                  MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removeDisplayIndex(row.index)
                  }
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: function(mouse) {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.toggleIndex(row.index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              width: parent.width
              text: "✓"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              width: parent.width
              text: "No tasks yet — type to add one"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }
}
