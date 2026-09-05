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

  // In-interface password prompt state
  property bool showPasswordPrompt: false
  property string inputPassword: ""
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
    root.opened = false
    root.showPasswordPrompt = false
    root.inputPassword = ""
    root.authError = ""
  }

  function dismiss() {
    root.opened = false
    root.showPasswordPrompt = false
    root.inputPassword = ""
    root.authError = ""
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide("omamigrate")
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
    root.authError = ""
    root.statusText = "Ready"
    root.checkArchive()
  }

  function startExport() {
    root.showPasswordPrompt = false
    root.isProcessing = true
    root.statusText = "Packaging in progress..."
    exportProcess.running = true
  }

  function startRestore() {
    root.showPasswordPrompt = false
    root.isProcessing = true
    root.statusText = "Restoration in progress..."
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
    WlrLayershell.namespace: "omamigrate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Background scrim
    Rectangle {
      anchors.fill: parent
      color: "#90000000"

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    // Modal Card
    Rectangle {
      id: card
      width: 480
      height: 360
      radius: 14
      color: "#1e1e2e"
      border.color: "#313244"
      border.width: 1
      anchors.centerIn: parent

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
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
            color: closeMouse.containsMouse ? "#313244" : "transparent"

            Text {
              anchors.centerIn: parent
              text: "✕"
              font.pixelSize: 13
              color: closeMouse.containsMouse ? "#cdd6f4" : "#6c7086"
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dismiss()
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.isProcessing) return
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.isProcessing) return
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

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Packaging in progress..."
                    font.pixelSize: 13
                    font.bold: true
                    color: "#89b4fa"
                  }

                  Text {
                    Layout.fillWidth: true
                    text: root.statusText
                    font.pixelSize: 11
                    color: "#a6adc8"
                    elide: Text.ElideRight
                  }
                }
              }
            }

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

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Restoration in progress..."
                    font.pixelSize: 13
                    font.bold: true
                    color: "#cba6f7"
                  }

                  Text {
                    Layout.fillWidth: true
                    text: root.statusText
                    font.pixelSize: 11
                    color: "#a6adc8"
                    elide: Text.ElideRight
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
                color: reloadMouse.pressed ? "#74c7ec" : reloadMouse.containsMouse ? "#b4befe" : "#89b4fa"

                Text {
                  anchors.centerIn: parent
                  text: "🔄 Reload Desktop"
                  font.pixelSize: 13
                  font.bold: true
                  color: "#11111b"
                }

                MouseArea {
                  id: reloadMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    reloadProcess.running = true
                    root.dismiss()
                  }
                }
              }

              Rectangle {
                width: 90
                height: 38
                radius: 8
                color: "#313244"

                Text {
                  anchors.centerIn: parent
                  text: "Close"
                  font.pixelSize: 12
                  color: "#cdd6f4"
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.dismiss()
                }
              }
            }
          }

          Item { Layout.fillHeight: true }
        }

        // Live Status Pill (Real-time output streaming from process)
        Rectangle {
          visible: !root.showPasswordPrompt
          Layout.fillWidth: true
          height: 28
          radius: 6
          color: "#181825"
          border.color: root.isProcessing ? "#89b4fa" : "#313244"
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Rectangle {
              width: 6
              height: 6
              radius: 3
              color: root.isProcessing ? "#89b4fa" : (root.statusText.indexOf("✓") !== -1 ? "#a6e3a1" : "#6c7086")
            }

            Text {
              Layout.fillWidth: true
              text: root.statusText
              font.pixelSize: 11
              color: root.isProcessing ? "#cdd6f4" : "#a6adc8"
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  // --- Background Processes ---

  Process {
    id: checkArchiveProcess
    command: ["bash", "-c", "[ -f \"$HOME/Downloads/omarchy-migration.tar.gz\" ] || [ -f \"$HOME/omarchy-migration.tar.gz\" ] && echo 'found' || echo 'missing'"]
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
    command: ["bash", "-c", "\"" + root.cliPath + "\" export"]
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
        root.statusText = "Export finished or cancelled."
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
    command: [
      "bash", "-c",
      "ARCHIVE=\"$([ -f $HOME/Downloads/omarchy-migration.tar.gz ] && echo $HOME/Downloads/omarchy-migration.tar.gz || echo $HOME/omarchy-migration.tar.gz)\"; \"" + root.cliPath + "\" restore \"$ARCHIVE\""
    ]
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
        root.statusText = "Restore finished with issues."
      }
    }
  }

  Process {
    id: reloadProcess
    command: ["bash", "-c", "hyprctl reload && omarchy restart shell"]
  }
}
