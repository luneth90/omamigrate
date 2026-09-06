import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // Mode: "export" | "restore"
  property string currentMode: "export"

  // Steps:
  // Export: 1 = Ready, 2 = Exported (show Send), 3 = Sent (show Done)
  property int exportStep: 1
  // Restore: 1 = Ready, 2 = Restored (show Success)
  property int restoreStep: 1

  property bool isProcessing: false
  property string statusText: "Ready"
  property bool archiveDetected: false
  property bool includeAiHistory: false
  property bool lockWarningActive: false

  onIsProcessingChanged: {
    if (root.isProcessing) {
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    id: lockWarningTimer
    interval: 2000
    repeat: false
    onTriggered: root.lockWarningActive = false
  }

  function notifyLocked() {
    root.lockWarningActive = true
    lockWarningTimer.restart()
  }

  // In-interface password prompt state
  property bool showPasswordPrompt: false
  property string inputPassword: ""
  property string savedPassword: ""
  property string authError: ""
  property bool authValidating: false
  property string pendingAction: "export" // "export" | "restore"

  readonly property string cliPath: String(Qt.resolvedUrl("bin/omamigrate")).replace("file://", "")

  function open(payloadJson) {
    root.opened = true
    root.checkArchive()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (root.isProcessing) {
      root.notifyLocked()
      return
    }
    root.opened = false
    root.showPasswordPrompt = false
    root.inputPassword = ""
    root.savedPassword = ""
    root.authError = ""
  }

  function dismiss() {
    if (root.isProcessing) {
      root.notifyLocked()
      return
    }
    root.opened = false
    root.showPasswordPrompt = false
    root.inputPassword = ""
    root.savedPassword = ""
    root.authError = ""
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide("luneth90.omamigrate")
    }
  }

  function checkArchive() {
    checkArchiveProcess.running = true
  }

  function resetFlow() {
    root.exportStep = 1
    root.restoreStep = 1
    root.isProcessing = false
    root.showPasswordPrompt = false
    root.inputPassword = ""
    root.savedPassword = ""
    root.authError = ""
    root.statusText = "Ready"
    root.checkArchive()
  }

  function startExport() {
    root.showPasswordPrompt = false
    root.isProcessing = true
    root.statusText = "Packaging system..."
    var pass = root.savedPassword || root.inputPassword
    root.savedPassword = ""
    root.inputPassword = ""
    exportProcess.command = [
      "bash", "-c",
      "PASS=\"$0\"\n" +
      "if [ -n \"$PASS\" ]; then echo \"$PASS\" | sudo -S -p \"\" -v 2>/dev/null || true; fi\n" +
      "OMAMIGRATE_FULL_AI=" + (root.includeAiHistory ? "1" : "0") + " OMAMIGRATE_SUDO_PASS=\"$PASS\" \"" + root.cliPath + "\" export\n",
      pass
    ]
    exportProcess.running = true
  }

  function startRestore() {
    root.showPasswordPrompt = false
    root.isProcessing = true
    root.statusText = "Restoring system..."
    var pass = root.savedPassword || root.inputPassword
    root.savedPassword = ""
    root.inputPassword = ""
    restoreProcess.command = [
      "bash", "-c",
      "PASS=\"$0\"\n" +
      "if [ -n \"$PASS\" ]; then echo \"$PASS\" | sudo -S -p \"\" -v 2>/dev/null || true; fi\n" +
      "ARCHIVE=\"\"\n" +
      "for p in \"$HOME/Downloads/omarchy-migration.tar.gz\" \"$HOME/Downloads/LocalSend/omarchy-migration.tar.gz\" \"$HOME/omarchy-migration.tar.gz\"; do\n" +
      "  if [ -f \"$p\" ]; then ARCHIVE=\"$p\"; break; fi\n" +
      "done\n" +
      "if [ -z \"$ARCHIVE\" ]; then\n" +
      "  ARCHIVE=$(find \"$HOME/Downloads\" \"$HOME\" -maxdepth 2 -type f -name \"*migration*.tar.gz\" 2>/dev/null | head -n 1)\n" +
      "fi\n" +
      "if [ -z \"$ARCHIVE\" ]; then\n" +
      "  echo \"Error: Migration archive not found in ~/Downloads or ~\" >&2\n" +
      "  exit 1\n" +
      "fi\n" +
      "OMAMIGRATE_GUI=1 OMAMIGRATE_SUDO_PASS=\"$PASS\" \"" + root.cliPath + "\" restore \"$ARCHIVE\"\n",
      pass
    ]
    restoreProcess.running = true
  }

  function handleExportClick() {
    if (root.isProcessing) return
    root.pendingAction = "export"
    checkExportAuthProcess.running = true
  }

  function handleRestoreClick() {
    if (root.isProcessing) return
    root.pendingAction = "restore"
    checkRestoreAuthProcess.running = true
  }

  function submitPassword() {
    if (root.authValidating) return
    if (root.inputPassword.length === 0) {
      root.authError = "Password cannot be empty."
      return
    }
    root.authValidating = true
    root.authError = ""
    authProcess.command = ["bash", "-c", "echo \"$0\" | sudo -S -p \"\" -v", root.inputPassword]
    authProcess.running = true
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "luneth90.omamigrate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Background scrim
    Rectangle {
      anchors.fill: parent
      color: "#90000000"

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (root.isProcessing) {
            root.notifyLocked()
          } else {
            root.dismiss()
          }
        }
      }
    }

    // Lock Warning Toast
    Rectangle {
      visible: root.lockWarningActive
      anchors.horizontalCenter: card.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: 12
      height: 32
      width: lockWarningRow.implicitWidth + 24
      radius: 8
      color: "#181825"
      border.color: "#f38ba8"
      border.width: 1
      z: 10

      RowLayout {
        id: lockWarningRow
        anchors.centerIn: parent
        spacing: 8
        Text {
          text: "🔒"
          font.pixelSize: 12
        }
        Text {
          text: "Task in progress: window is locked to ensure system safety"
          font.pixelSize: 11
          font.bold: true
          color: "#f38ba8"
        }
      }
    }

    // Modal Card
    Rectangle {
      id: card
      width: 480
      height: 360
      radius: 14
      color: "#1e1e2e"
      border.color: root.lockWarningActive ? "#f38ba8" : (root.isProcessing ? (root.currentMode === "export" ? "#89b4fa" : "#cba6f7") : "#313244")
      border.width: root.lockWarningActive ? 2 : 1
      anchors.centerIn: parent

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      // Card Shield during Processing (locks all mouse interactions)
      MouseArea {
        id: processingShield
        anchors.fill: parent
        z: 999
        visible: root.isProcessing
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.BusyCursor
        onClicked: root.notifyLocked()
        onPressed: root.notifyLocked()
        onDoubleClicked: root.notifyLocked()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.isProcessing) {
            root.notifyLocked()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.showPasswordPrompt) {
              root.showPasswordPrompt = false
              root.isProcessing = false
            } else {
              root.dismiss()
            }
            event.accepted = true
          }
        }
        Keys.onReleased: function(event) {
          if (root.isProcessing) {
            event.accepted = true
            return
          }
        }
        Keys.onShortcutOverride: function(event) {
          if (root.isProcessing) {
            root.notifyLocked()
            event.accepted = true
            return
          }
        }
        onActiveFocusChanged: {
          if (root.isProcessing && !activeFocus) {
            keyCatcher.forceActiveFocus()
          }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        // Top Row: Title + Close Button
        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: "⚡ OmaMigrate"
            font.pixelSize: 18
            font.bold: true
            color: "#cdd6f4"
          }

          Item { Layout.fillWidth: true }

          Rectangle {
            width: 26
            height: 26
            radius: 13
            color: root.isProcessing ? "transparent" : (closeMouse.containsMouse ? "#313244" : "transparent")

            Text {
              anchors.centerIn: parent
              text: root.isProcessing ? "🔒" : "✕"
              font.pixelSize: root.isProcessing ? 12 : 13
              color: root.isProcessing ? "#6c7086" : (closeMouse.containsMouse ? "#cdd6f4" : "#6c7086")
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: !root.isProcessing
              cursorShape: root.isProcessing ? Qt.ForbiddenCursor : Qt.PointingHandCursor
              onClicked: {
                if (root.isProcessing) {
                  root.notifyLocked()
                } else {
                  root.dismiss()
                }
              }
            }
          }
        }

        // Mode Switcher (Export / Restore)
        Rectangle {
          visible: !root.showPasswordPrompt
          Layout.fillWidth: true
          height: 34
          radius: 8
          color: "#181825"
          border.color: "#313244"
          border.width: 1
          opacity: root.isProcessing ? 0.45 : 1.0

          RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 4

            // Export Tab
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 6
              color: root.currentMode === "export" ? "#313244" : "transparent"

              Text {
                anchors.centerIn: parent
                text: "📦 Export"
                font.pixelSize: 12
                font.bold: root.currentMode === "export"
                color: root.currentMode === "export" ? "#cdd6f4" : "#6c7086"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: !root.isProcessing
                cursorShape: root.isProcessing ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                onClicked: {
                  if (root.isProcessing) {
                    root.notifyLocked()
                    return
                  }
                  root.currentMode = "export"
                  root.checkArchive()
                }
              }
            }

            // Restore Tab
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 6
              color: root.currentMode === "restore" ? "#313244" : "transparent"

              Text {
                anchors.centerIn: parent
                text: "⚡ Restore"
                font.pixelSize: 12
                font.bold: root.currentMode === "restore"
                color: root.currentMode === "restore" ? "#cdd6f4" : "#6c7086"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: !root.isProcessing
                cursorShape: root.isProcessing ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                onClicked: {
                  if (root.isProcessing) {
                    root.notifyLocked()
                    return
                  }
                  root.currentMode = "restore"
                  root.checkArchive()
                }
              }
            }
          }
        }

        // Divider
        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: "#27273a"
        }

        // ==========================================
        // PASSWORD PROMPT VIEW (In-Interface Dialog)
        // ==========================================
        ColumnLayout {
          visible: root.showPasswordPrompt
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 10

          RowLayout {
            Text {
              text: "🔒 AUTHENTICATION REQUIRED"
              font.pixelSize: 10
              font.bold: true
              color: "#fab387"
            }
            Item { Layout.fillWidth: true }
          }

          Text {
            text: "Administrator Password"
            font.pixelSize: 15
            font.bold: true
            color: "#cdd6f4"
          }

          Text {
            text: root.pendingAction === "export"
              ? "System password required to archive protected configs (/etc/sing-box)."
              : "System password required to install packages and configure system services."
            font.pixelSize: 12
            color: "#a6adc8"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Item { height: 2 }

          // Password Input Field
          Rectangle {
            Layout.fillWidth: true
            height: 40
            radius: 8
            color: "#181825"
            border.color: root.authError.length > 0 ? "#f38ba8" : (passwordInput.activeFocus ? "#89b4fa" : "#313244")
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 8

              Text {
                text: "🔑"
                font.pixelSize: 14
              }

              TextInput {
                id: passwordInput
                Layout.fillWidth: true
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: "#cdd6f4"
                font.pixelSize: 14
                clip: true
                focus: root.showPasswordPrompt
                text: root.inputPassword
                onTextChanged: {
                  root.inputPassword = text
                  root.authError = ""
                }
                Keys.onReturnPressed: root.submitPassword()
              }
            }
          }

          // Auth Error Message
          Text {
            visible: root.authError.length > 0
            text: root.authError
            font.pixelSize: 11
            color: "#f38ba8"
          }

          Item { Layout.fillHeight: true }

          // Action Buttons
          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              height: 38
              radius: 8
              color: root.authValidating ? "#313244" : (unlockMouse.pressed ? "#74c7ec" : unlockMouse.containsMouse ? "#b4befe" : "#89b4fa")

              Text {
                anchors.centerIn: parent
                text: root.authValidating ? "Verifying..." : "Unlock & Proceed"
                font.pixelSize: 13
                font.bold: true
                color: root.authValidating ? "#6c7086" : "#11111b"
              }

              MouseArea {
                id: unlockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.authValidating ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: root.submitPassword()
              }
            }

            Rectangle {
              width: root.pendingAction === "export" ? 140 : 80
              height: 38
              radius: 8
              color: "transparent"
              border.color: "#313244"
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: root.pendingAction === "export" ? "Skip System Files" : "Cancel"
                font.pixelSize: 12
                color: "#a6adc8"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.pendingAction === "export") {
                    root.showPasswordPrompt = false
                    root.startExport()
                  } else {
                    root.showPasswordPrompt = false
                    root.isProcessing = false
                  }
                }
              }
            }
          }
        }

        // ==========================================
        // EXPORT FLOW
        // ==========================================
        ColumnLayout {
          visible: !root.showPasswordPrompt && root.currentMode === "export"
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 10

          // Step 1: Export
          ColumnLayout {
            visible: root.exportStep === 1
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
              Text {
                text: "STEP 1 OF 2"
                font.pixelSize: 10
                font.bold: true
                color: "#89b4fa"
              }
              Item { Layout.fillWidth: true }
            }

            Text {
              text: "Package System Environment"
              font.pixelSize: 15
              font.bold: true
              color: "#cdd6f4"
            }

            Text {
              text: "Includes installed apps, daemons, configs, and AI developer credentials."
              font.pixelSize: 12
              color: "#a6adc8"
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item { height: 2 }

            // Prominent Packaging In Progress Line (shown when active)
            Rectangle {
              visible: root.isProcessing
              Layout.fillWidth: true
              height: 46
              radius: 8
              color: "#182238"
              border.color: "#89b4fa"
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                  width: 10
                  height: 10
                  radius: 5
                  color: "#89b4fa"

                  SequentialAnimation on opacity {
                    running: root.isProcessing
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 6

                  Text {
                    Layout.fillWidth: true
                    text: (root.statusText && root.statusText !== "Ready") ? root.statusText : "Packaging in progress..."
                    font.pixelSize: 13
                    font.bold: true
                    color: "#89b4fa"
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "🔒 Locked"
                    font.pixelSize: 10
                    font.bold: true
                    color: "#6c7086"
                  }
                }
              }
            }

            // AI Chat History Option Card
            Rectangle {
              visible: !root.isProcessing
              Layout.fillWidth: true
              height: 48
              radius: 8
              color: root.includeAiHistory ? "#1e1e2e" : "#181825"
              border.color: aiHistoryMouse.containsMouse ? "#89b4fa" : (root.includeAiHistory ? "#89b4fa" : "#313244")
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                // Custom Checkbox
                Rectangle {
                  width: 20
                  height: 20
                  radius: 5
                  color: root.includeAiHistory ? "#89b4fa" : "transparent"
                  border.color: root.includeAiHistory ? "#89b4fa" : "#585b70"
                  border.width: 1.5

                  Text {
                    anchors.centerIn: parent
                    visible: root.includeAiHistory
                    text: "✓"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#11111b"
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  RowLayout {
                    spacing: 6
                    Text {
                      text: "包含完整 AI 对话历史与插件"
                      font.pixelSize: 12
                      font.bold: true
                      color: root.includeAiHistory ? "#cdd6f4" : "#a6adc8"
                    }
                    Rectangle {
                      height: 16
                      width: root.includeAiHistory ? 54 : 46
                      radius: 4
                      color: root.includeAiHistory ? "#45475a" : "#313244"
                      Text {
                        anchors.centerIn: parent
                        text: root.includeAiHistory ? "~650 MB" : "~25 MB"
                        font.pixelSize: 9
                        font.bold: true
                        color: root.includeAiHistory ? "#fab387" : "#a6e3a1"
                      }
                    }
                  }

                  Text {
                    text: root.includeAiHistory ? "包含 Claude/Codex/Grok/Gemini 历史会话与编译二进制" : "默认极简模式：仅保留登录凭证与配置，传输快 20 倍"
                    font.pixelSize: 10
                    color: "#6c7086"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }
              }

              MouseArea {
                id: aiHistoryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.includeAiHistory = !root.includeAiHistory
              }
            }

            Item { height: 2; visible: !root.isProcessing }

            // Create Backup Button (shown when idle)
            Rectangle {
              visible: !root.isProcessing
              Layout.fillWidth: true
              height: 40
              radius: 8
              color: exportBtnMouse.pressed ? "#74c7ec" : exportBtnMouse.containsMouse ? "#b4befe" : "#89b4fa"

              Text {
                anchors.centerIn: parent
                text: "📦 Create Backup"
                font.pixelSize: 13
                font.bold: true
                color: "#11111b"
              }

              MouseArea {
                id: exportBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.handleExportClick()
              }
            }
          }

          // Step 2: Send (Shown ONLY after Export succeeds)
          ColumnLayout {
            visible: root.exportStep === 2
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
              Text {
                text: "STEP 2 OF 2"
                font.pixelSize: 10
                font.bold: true
                color: "#a6e3a1"
              }
              Item { Layout.fillWidth: true }
              Text {
                text: "Start Over"
                font.pixelSize: 11
                color: "#6c7086"
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.resetFlow()
                }
              }
            }

            Text {
              text: "✓ Backup Ready: ~/omarchy-migration.tar.gz"
              font.pixelSize: 13
              font.bold: true
              color: "#a6e3a1"
            }

            Text {
              text: "Beam the archive wirelessly to your target machine using LocalSend."
              font.pixelSize: 12
              color: "#a6adc8"
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item { height: 2 }

            // Target device reminder badge
            Rectangle {
              Layout.fillWidth: true
              height: 38
              radius: 6
              color: "#2a221d"
              border.color: "#4f3b2a"
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                  text: "💡"
                  font.pixelSize: 13
                }

                Text {
                  Layout.fillWidth: true
                  text: "Please open LocalSend on your target machine first so it can be discovered."
                  font.pixelSize: 11
                  color: "#fab387"
                  wrapMode: Text.WordWrap
                }
              }
            }

            Item { height: 2 }

            Rectangle {
              Layout.fillWidth: true
              height: 40
              radius: 8
              color: sendBtnMouse.pressed ? "#94e2d5" : sendBtnMouse.containsMouse ? "#b4befe" : "#a6e3a1"

              Text {
                anchors.centerIn: parent
                text: "📡 Send via LocalSend"
                font.pixelSize: 13
                font.bold: true
                color: "#11111b"
              }

              MouseArea {
                id: sendBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.statusText = "Launching LocalSend..."
                  sendProcess.running = true
                  root.dismiss()
                }
              }
            }
          }

          // Step 3: Success after Send
          ColumnLayout {
            visible: root.exportStep === 3
            Layout.fillWidth: true
            spacing: 10

            Text {
              text: "✓ LocalSend Launched"
              font.pixelSize: 15
              font.bold: true
              color: "#a6e3a1"
            }

            Text {
              text: "Once received on your new computer, open OmaMigrate there and click Restore."
              font.pixelSize: 12
              color: "#a6adc8"
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item { height: 4 }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 8
                color: doneMouse.pressed ? "#45475a" : doneMouse.containsMouse ? "#3b3d52" : "#313244"

                Text {
                  anchors.centerIn: parent
                  text: "Done"
                  font.pixelSize: 13
                  font.bold: true
                  color: "#cdd6f4"
                }

                MouseArea {
                  id: doneMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.dismiss()
                }
              }

              Rectangle {
                width: 90
                height: 38
                radius: 8
                color: "transparent"
                border.color: "#313244"
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: "Reset"
                  font.pixelSize: 12
                  color: "#a6adc8"
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.resetFlow()
                }
              }
            }
          }

          // Step 4: Export Error / Failure
          ColumnLayout {
            visible: root.exportStep === 4
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
              Text {
                text: "EXPORT ERROR"
                font.pixelSize: 10
                font.bold: true
                color: "#f38ba8"
              }
              Item { Layout.fillWidth: true }
            }

            Text {
              text: "✗ Packaging Interrupted or Failed"
              font.pixelSize: 15
              font.bold: true
              color: "#f38ba8"
            }

            Rectangle {
              Layout.fillWidth: true
              height: 48
              radius: 6
              color: "#2a1b26"
              border.color: "#f38ba8"
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Text {
                  Layout.fillWidth: true
                  text: root.statusText
                  font.pixelSize: 11
                  color: "#f38ba8"
                  wrapMode: Text.WordWrap
                }
              }
            }

            Item { height: 4 }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 8
                color: retryExportMouse.pressed ? "#74c7ec" : retryExportMouse.containsMouse ? "#b4befe" : "#89b4fa"

                Text {
                  anchors.centerIn: parent
                  text: "Retry Backup"
                  font.pixelSize: 13
                  font.bold: true
                  color: "#11111b"
                }

                MouseArea {
                  id: retryExportMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.exportStep = 1
                    root.handleExportClick()
                  }
                }
              }

              Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 8
                color: cancelExportMouse.pressed ? "#45475a" : cancelExportMouse.containsMouse ? "#3b3d52" : "#313244"

                Text {
                  anchors.centerIn: parent
                  text: "Back"
                  font.pixelSize: 13
                  font.bold: true
                  color: "#cdd6f4"
                }

                MouseArea {
                  id: cancelExportMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.resetFlow()
                  }
                }
              }
            }
          }

          Item { Layout.fillHeight: true }
        }

        // ==========================================
        // RESTORE FLOW
        // ==========================================
        ColumnLayout {
          visible: !root.showPasswordPrompt && root.currentMode === "restore"
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 10

          // Step 1: Restore
          ColumnLayout {
            visible: root.restoreStep === 1
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
              Text {
                text: "STEP 1 OF 1"
                font.pixelSize: 10
                font.bold: true
                color: "#cba6f7"
              }
              Item { Layout.fillWidth: true }
            }

            Text {
              text: "Restore System Environment"
              font.pixelSize: 15
              font.bold: true
              color: "#cdd6f4"
            }

            // Archive detection badge
            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 6
              color: root.archiveDetected ? "#1c2e26" : "#2a221d"
              border.color: root.archiveDetected ? "#2d4f3e" : "#4f3b2a"
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                  text: root.archiveDetected ? "✓ Archive detected in ~/Downloads" : "⚠ Waiting for archive in ~/Downloads"
                  font.pixelSize: 11
                  font.bold: true
                  color: root.archiveDetected ? "#a6e3a1" : "#fab387"
                }

                Item { Layout.fillWidth: true }
              }
            }

            Item { height: 2 }

            // Prominent Restoring In Progress Line (shown when active)
            Rectangle {
              visible: root.isProcessing
              Layout.fillWidth: true
              height: 46
              radius: 8
              color: "#281b33"
              border.color: "#cba6f7"
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                  width: 10
                  height: 10
                  radius: 5
                  color: "#cba6f7"

                  SequentialAnimation on opacity {
                    running: root.isProcessing
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 6

                  Text {
                    Layout.fillWidth: true
                    text: (root.statusText && root.statusText !== "Ready") ? root.statusText : "Restoring system..."
                    font.pixelSize: 13
                    font.bold: true
                    color: "#cba6f7"
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "🔒 Locked"
                    font.pixelSize: 10
                    font.bold: true
                    color: "#6c7086"
                  }
                }
              }
            }

            // Start Restore Button (shown when idle)
            Rectangle {
              visible: !root.isProcessing
              Layout.fillWidth: true
              height: 40
              radius: 8
              color: restoreBtnMouse.pressed ? "#b4befe" : restoreBtnMouse.containsMouse ? "#cba6f7" : "#cba6f7"

              Text {
                anchors.centerIn: parent
                text: "⚡ Start Restore"
                font.pixelSize: 13
                font.bold: true
                color: "#11111b"
              }

              MouseArea {
                id: restoreBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.handleRestoreClick()
              }
            }
          }

          // Step 2: Restore Complete
          ColumnLayout {
            visible: root.restoreStep === 2
            Layout.fillWidth: true
            spacing: 10

            Text {
              text: "✓ System Restored Successfully!"
              font.pixelSize: 15
              font.bold: true
              color: "#a6e3a1"
            }

            Text {
              text: "All applications, services, and credentials have been restored."
              font.pixelSize: 12
              color: "#a6adc8"
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item { height: 4 }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 8
                color: doneRestoreMouse.pressed ? "#74c7ec" : doneRestoreMouse.containsMouse ? "#b4befe" : "#89b4fa"

                Text {
                  anchors.centerIn: parent
                  text: "Done"
                  font.pixelSize: 13
                  font.bold: true
                  color: "#11111b"
                }

                MouseArea {
                  id: doneRestoreMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    reloadProcess.running = true
                    root.dismiss()
                  }
                }
              }
            }
          }

          // Step 3: Restore Error / Failure
          ColumnLayout {
            visible: root.restoreStep === 3
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
              Text {
                text: "RESTORE ERROR"
                font.pixelSize: 10
                font.bold: true
                color: "#f38ba8"
              }
              Item { Layout.fillWidth: true }
            }

            Text {
              text: "✗ Restoration Interrupted or Failed"
              font.pixelSize: 15
              font.bold: true
              color: "#f38ba8"
            }

            Rectangle {
              Layout.fillWidth: true
              height: 48
              radius: 6
              color: "#2a1b26"
              border.color: "#f38ba8"
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Text {
                  Layout.fillWidth: true
                  text: root.statusText
                  font.pixelSize: 11
                  color: "#f38ba8"
                  wrapMode: Text.WordWrap
                }
              }
            }

            Text {
              text: "Please verify that the archive file is valid and password was entered correctly."
              font.pixelSize: 11
              color: "#a6adc8"
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item { height: 4 }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 8
                color: retryRestoreMouse.pressed ? "#b4befe" : retryRestoreMouse.containsMouse ? "#cba6f7" : "#cba6f7"

                Text {
                  anchors.centerIn: parent
                  text: "Retry Restore"
                  font.pixelSize: 13
                  font.bold: true
                  color: "#11111b"
                }

                MouseArea {
                  id: retryRestoreMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.restoreStep = 1
                    root.handleRestoreClick()
                  }
                }
              }

              Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 8
                color: cancelRestoreMouse.pressed ? "#45475a" : cancelRestoreMouse.containsMouse ? "#3b3d52" : "#313244"

                Text {
                  anchors.centerIn: parent
                  text: "Back"
                  font.pixelSize: 13
                  font.bold: true
                  color: "#cdd6f4"
                }

                MouseArea {
                  id: cancelRestoreMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.resetFlow()
                  }
                }
              }
            }
          }

          Item { Layout.fillHeight: true }
        }
      }
    }
  }

  // --- Background Processes ---

  Process {
    id: checkArchiveProcess
    command: [
      "bash", "-c",
      "for p in \"$HOME/Downloads/omarchy-migration.tar.gz\" \"$HOME/Downloads/LocalSend/omarchy-migration.tar.gz\" \"$HOME/omarchy-migration.tar.gz\"; do\n" +
      "  [ -f \"$p\" ] && echo 'found' && exit 0\n" +
      "done\n" +
      "FOUND=$(find \"$HOME/Downloads\" \"$HOME\" -maxdepth 2 -type f -name \"*migration*.tar.gz\" 2>/dev/null | head -n 1)\n" +
      "[ -n \"$FOUND\" ] && echo 'found' || echo 'missing'\n"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        root.archiveDetected = (String(text).trim() === "found")
      }
    }
  }

  Process {
    id: checkExportAuthProcess
    command: [
      "bash", "-c",
      "if sudo -n true 2>/dev/null; then echo 'no'; elif find /etc/sing-box /etc/mihomo /etc/v2raya /etc/xray /etc/v2ray /etc/daed -maxdepth 2 ! -readable 2>/dev/null | grep -q .; then echo 'yes'; else echo 'no'; fi"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        if (String(text).trim() === "yes") {
          root.inputPassword = ""
          root.authError = ""
          root.showPasswordPrompt = true
          Qt.callLater(function() { passwordInput.forceActiveFocus() })
        } else {
          root.startExport()
        }
      }
    }
  }

  Process {
    id: checkRestoreAuthProcess
    command: [
      "bash", "-c",
      "if sudo -n true 2>/dev/null; then echo 'no'; else echo 'yes'; fi"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        if (String(text).trim() === "yes") {
          root.inputPassword = ""
          root.authError = ""
          root.showPasswordPrompt = true
          Qt.callLater(function() { passwordInput.forceActiveFocus() })
        } else {
          root.startRestore()
        }
      }
    }
  }

  Process {
    id: authProcess
    onExited: function(code) {
      root.authValidating = false
      if (code === 0) {
        root.savedPassword = root.inputPassword
        root.inputPassword = ""
        root.showPasswordPrompt = false
        root.authError = ""
        if (root.pendingAction === "export") {
          root.startExport()
        } else if (root.pendingAction === "restore") {
          root.startRestore()
        }
      } else {
        root.authError = "Incorrect password. Please try again."
        passwordInput.selectAll()
        passwordInput.forceActiveFocus()
      }
    }
  }

  Process {
    id: exportProcess
    stdout: SplitParser {
      onRead: function(line) {
        var clean = String(line).replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "").trim()
        if (clean.length > 0) {
          root.statusText = clean
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var clean = String(line).replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "").trim()
        if (clean.length > 0) {
          root.statusText = clean
        }
      }
    }
    onExited: function(code) {
      root.isProcessing = false
      if (code === 0) {
        root.exportStep = 2
        root.statusText = "Backup ready: ~/omarchy-migration.tar.gz"
        root.checkArchive()
      } else {
        root.exportStep = 4
        if (!root.statusText || root.statusText === "Packaging in progress..." || root.statusText === "Packaging system...") {
          root.statusText = "Export process failed or was interrupted (code " + code + ")."
        }
        root.checkArchive()
      }
    }
  }

  Process {
    id: sendProcess
    command: ["bash", "-c", "\"" + root.cliPath + "\" send \"$HOME/omarchy-migration.tar.gz\""]
    onExited: function() {
      root.exportStep = 3
      root.statusText = "LocalSend launched."
    }
  }

  Process {
    id: restoreProcess
    stdout: SplitParser {
      onRead: function(line) {
        var clean = String(line).replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "").trim()
        if (clean.length > 0) {
          root.statusText = clean
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var clean = String(line).replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "").trim()
        if (clean.length > 0) {
          root.statusText = clean
        }
      }
    }
    onExited: function(code) {
      root.isProcessing = false
      if (code === 0) {
        root.restoreStep = 2
        root.statusText = "Restoration completed successfully!"
      } else {
        root.restoreStep = 3
        if (!root.statusText || root.statusText === "Restoration in progress..." || root.statusText === "Restoring system...") {
          root.statusText = "Restore process exited with code " + code + "."
        }
      }
    }
  }

  Process {
    id: reloadProcess
    command: ["bash", "-c", "hyprctl reload && omarchy restart shell"]
  }
}
