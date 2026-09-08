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
  property bool includeAiHistory: false
  property bool lockWarningActive: false
  property string selectedArchive: ""
  property var archiveFiles: []
  property string archiveScanError: ""

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
  property string authError: ""
  property bool authValidating: false
  property string pendingAction: "export" // "export" | "restore"
  property string lastExportedArchive: ""
  property string pendingSecret: ""
  property string exportSecret: ""
  property string restoreSecret: ""

  readonly property string cliPath: String(Qt.resolvedUrl("bin/omamigrate")).replace("file://", "")
  readonly property string archiveScannerPath: String(Qt.resolvedUrl("lib/scan-archives.sh")).replace("file://", "")

  function open(payloadJson) {
    root.opened = true
    root.scanArchives()
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
    root.pendingSecret = ""
    root.exportSecret = ""
    root.restoreSecret = ""
    authProcess.secretBuffer = ""
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
    root.pendingSecret = ""
    root.exportSecret = ""
    root.restoreSecret = ""
    authProcess.secretBuffer = ""
    root.authError = ""
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide("luneth90.omamigrate")
    }
  }

  function scanArchives() {
    if (scanArchiveProcess.running) return
    root.archiveScanError = ""
    scanArchiveProcess.running = true
  }

  function resetFlow() {
    root.exportStep = 1
    root.restoreStep = 1
    root.isProcessing = false
    root.showPasswordPrompt = false
    root.inputPassword = ""
    root.pendingSecret = ""
    root.exportSecret = ""
    root.restoreSecret = ""
    authProcess.secretBuffer = ""
    root.authError = ""
    root.statusText = "Ready"
    root.selectedArchive = ""
    root.lastExportedArchive = ""
    root.scanArchives()
  }

  function startExport(secret) {
    root.showPasswordPrompt = false
    root.lastExportedArchive = ""
    root.isProcessing = true
    root.statusText = "Creating migration backup..."
    root.inputPassword = ""
    root.pendingSecret = ""
    authProcess.secretBuffer = ""
    root.exportSecret = (secret !== undefined && secret !== null) ? String(secret) : ""
    exportProcess.command = [
      "bash", "-c",
      "OMAMIGRATE_FULL_AI=" + (root.includeAiHistory ? "1" : "0") +
      " exec \"" + root.cliPath + "\" backup\n"
    ]
    exportProcess.running = true
  }

  function startRestore(secret) {
    if (!root.selectedArchive) {
      root.statusText = "Error: No backup selected."
      return
    }
    root.showPasswordPrompt = false
    root.isProcessing = true
    root.statusText = "Restoring system..."
    root.inputPassword = ""
    root.pendingSecret = ""
    authProcess.secretBuffer = ""
    root.restoreSecret = (secret !== undefined && secret !== null) ? String(secret) : ""
    var archive = root.selectedArchive
    restoreProcess.command = [
      "bash", "-c",
      "OMAMIGRATE_GUI=1 exec \"" + root.cliPath + "\" restore \"$0\"\n",
      archive
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
    authProcess.secretBuffer = root.inputPassword
    root.pendingSecret = root.inputPassword
    root.inputPassword = ""
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
      height: root.showPasswordPrompt ? 360 : ((root.currentMode === "restore" || root.exportStep === 1) ? 420 : 360)
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

        // Mode Switcher (Backup / Restore)
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

            // Backup Tab
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 6
              color: root.currentMode === "export" ? "#313244" : "transparent"

              Text {
                anchors.centerIn: parent
                text: "📦 Backup"
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
                  root.scanArchives()
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
              ? "System password required to include protected proxy configs and systemd units in the backup."
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
              width: 80
              height: 38
              radius: 8
              color: "transparent"
              border.color: "#313244"
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "Cancel"
                font.pixelSize: 12
                color: "#a6adc8"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.showPasswordPrompt = false
                  root.inputPassword = ""
                  root.pendingSecret = ""
                  root.exportSecret = ""
                  root.restoreSecret = ""
                  authProcess.secretBuffer = ""
                  root.authError = ""
                  root.isProcessing = false
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
              text: "Create a Migration Backup"
              font.pixelSize: 15
              font.bold: true
              color: "#cdd6f4"
            }

            Text {
              text: "Move apps, AI tools and credentials, proxy services, system configurations, and automated workflows to another Omarchy machine."
              font.pixelSize: 12
              color: "#a6adc8"
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item { height: 2 }

            // Prominent Backup In Progress Line (shown when active)
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
                    text: (root.statusText && root.statusText !== "Ready") ? root.statusText : "Creating migration backup..."
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

            Text {
              visible: !root.isProcessing
              text: "BACKUP TYPE"
              font.pixelSize: 10
              font.bold: true
              color: "#6c7086"
            }

            // Explicit backup types distinguish scope without unreliable size estimates.
            RowLayout {
              visible: !root.isProcessing
              Layout.fillWidth: true
              spacing: 8

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                radius: 8
                color: !root.includeAiHistory ? "#1e1e2e" : "#181825"
                border.color: standardBackupMouse.containsMouse || !root.includeAiHistory ? "#89b4fa" : "#313244"
                border.width: 1

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: 10
                  spacing: 3

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                      Layout.preferredWidth: 14
                      Layout.preferredHeight: 14
                      radius: 7
                      color: !root.includeAiHistory ? "#89b4fa" : "transparent"
                      border.color: !root.includeAiHistory ? "#89b4fa" : "#585b70"
                      border.width: 1.5
                    }

                    Text {
                      text: "Standard"
                      font.pixelSize: 11
                      font.bold: true
                      color: !root.includeAiHistory ? "#cdd6f4" : "#a6adc8"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      text: "Recommended"
                      font.pixelSize: 10
                      font.bold: true
                      color: "#a6e3a1"
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: "Apps, AI credentials, proxies, and configs"
                    font.pixelSize: 9
                    color: "#a6adc8"
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: "Excludes AI history and plugins"
                    font.pixelSize: 9
                    color: "#585b70"
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  id: standardBackupMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.includeAiHistory = false
                }
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                radius: 8
                color: root.includeAiHistory ? "#1e1e2e" : "#181825"
                border.color: completeBackupMouse.containsMouse || root.includeAiHistory ? "#89b4fa" : "#313244"
                border.width: 1

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: 10
                  spacing: 3

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                      Layout.preferredWidth: 14
                      Layout.preferredHeight: 14
                      radius: 7
                      color: root.includeAiHistory ? "#89b4fa" : "transparent"
                      border.color: root.includeAiHistory ? "#89b4fa" : "#585b70"
                      border.width: 1.5
                    }

                    Text {
                      text: "Complete"
                      font.pixelSize: 11
                      font.bold: true
                      color: root.includeAiHistory ? "#cdd6f4" : "#a6adc8"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      text: "May be large"
                      font.pixelSize: 10
                      font.bold: true
                      color: "#fab387"
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: "Everything in Standard"
                    font.pixelSize: 9
                    color: "#a6adc8"
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: "Includes AI history, sessions, and plugins"
                    font.pixelSize: 9
                    color: "#585b70"
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  id: completeBackupMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.includeAiHistory = true
                }
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
              text: "✓ Migration Backup Created: " + (root.lastExportedArchive ? root.lastExportedArchive.replace(/\/home\/[^\/]+/, "~") : "")
              font.pixelSize: 13
              font.bold: true
              color: "#a6e3a1"
              wrapMode: Text.WrapAnywhere
              Layout.fillWidth: true
            }


            Text {
              text: "Transfer this backup directly to a nearby device over your local network. No cloud upload."
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
                  text: "Open LocalSend on the nearby target device first so it can be discovered."
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
                text: "📡 Open LocalSend"
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
                  root.statusText = "Opening LocalSend for local transfer..."
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
              text: "✓ LocalSend Opened"
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
              text: "✗ Backup Interrupted or Failed"
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
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
              Text {
                text: "STEP 1 OF 1"
                font.pixelSize: 10
                font.bold: true
                color: "#cba6f7"
              }
              Item { Layout.fillWidth: true }
              // Refresh button
              Text {
                visible: !root.isProcessing
                text: "🔄 Refresh"
                font.pixelSize: 10
                color: "#6c7086"
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.scanArchives()
                }
              }
            }

            Text {
              text: "Select a Migration Backup"
              font.pixelSize: 15
              font.bold: true
              color: "#cdd6f4"
            }

            Text {
              visible: !root.isProcessing
              text: "Choose a migration backup from your Downloads folder"
              font.pixelSize: 11
              color: "#6c7086"
            }

            Text {
              visible: !root.isProcessing
              text: "Only backup files named with “migration” or “migrate” are shown"
              font.pixelSize: 10
              color: "#585b70"
            }

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

            // Archive file list (shown when idle)
            Rectangle {
              visible: !root.isProcessing
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 8
              color: "#181825"
              border.color: "#313244"
              border.width: 1
              clip: true

              ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Empty state
                ColumnLayout {
                  visible: root.archiveFiles.length === 0
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  spacing: 6

                  Item { Layout.fillHeight: true }

                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "📭"
                    font.pixelSize: 24
                  }

                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.archiveScanError || "No migration backups found in Downloads"
                    font.pixelSize: 12
                    color: root.archiveScanError ? "#f38ba8" : "#6c7086"
                  }

                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Transfer an *migration*.tar.gz or *migrate*.tar.gz file first"
                    font.pixelSize: 10
                    color: "#585b70"
                  }

                  Item { Layout.fillHeight: true }
                }

                // File list
                Flickable {
                  visible: root.archiveFiles.length > 0
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  contentHeight: fileListCol.height
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds

                  ColumnLayout {
                    id: fileListCol
                    width: parent.width
                    spacing: 0

                    Repeater {
                      model: root.archiveFiles

                      Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        color: {
                          var isSelected = root.selectedArchive === modelData.path
                          if (isSelected) return "#2d2250"
                          if (fileItemMouse.containsMouse) return "#1e1e30"
                          return "transparent"
                        }
                        border.color: root.selectedArchive === modelData.path ? "#cba6f7" : "transparent"
                        border.width: root.selectedArchive === modelData.path ? 1 : 0

                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 10
                          anchors.rightMargin: 10
                          spacing: 8

                          // Radio indicator
                          Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            color: "transparent"
                            border.color: root.selectedArchive === modelData.path ? "#cba6f7" : "#585b70"
                            border.width: 1.5

                            Rectangle {
                              anchors.centerIn: parent
                              width: 8
                              height: 8
                              radius: 4
                              color: "#cba6f7"
                              visible: root.selectedArchive === modelData.path
                            }
                          }

                          ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                              Layout.fillWidth: true
                              text: modelData.name
                              font.pixelSize: 12
                              font.bold: root.selectedArchive === modelData.path
                              color: root.selectedArchive === modelData.path ? "#cdd6f4" : "#a6adc8"
                              elide: Text.ElideMiddle
                            }

                            Text {
                              Layout.fillWidth: true
                              text: modelData.size + "  ·  " + modelData.date
                              font.pixelSize: 9
                              color: "#585b70"
                            }
                          }
                        }

                        MouseArea {
                          id: fileItemMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.selectedArchive = modelData.path
                        }
                      }
                    }
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
              color: {
                if (!root.selectedArchive) return "#45475a"
                if (restoreBtnMouse.pressed) return "#b4befe"
                if (restoreBtnMouse.containsMouse) return "#d4b5fc"
                return "#cba6f7"
              }

              Text {
                anchors.centerIn: parent
                text: root.selectedArchive ? "⚡ Restore from Backup" : "Select a backup above"
                font.pixelSize: 13
                font.bold: true
                color: root.selectedArchive ? "#11111b" : "#6c7086"
              }

              MouseArea {
                id: restoreBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.selectedArchive ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                onClicked: {
                  if (root.selectedArchive) root.handleRestoreClick()
                }
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
              text: "Please verify that the backup file is valid and the password was entered correctly."
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
    id: scanArchiveProcess
    command: [root.archiveScannerPath]
    stdout: StdioCollector {
      id: archiveScanOutput
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(String(archiveScanOutput.text).trim())
          root.archiveFiles = list
          // Auto-select if only one archive, or if current selection is stale
          if (list.length === 1) {
            root.selectedArchive = list[0].path
          } else if (root.selectedArchive) {
            var stillValid = list.some(function(f) { return f.path === root.selectedArchive })
            if (!stillValid) root.selectedArchive = ""
          }
        } catch(e) {
          root.archiveFiles = []
          root.selectedArchive = ""
          root.archiveScanError = "Could not read the backup list"
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) root.archiveScanError = "Backup scan failed (code " + code + ")"
    }
  }

  Process {
    id: checkExportAuthProcess
    command: [
      "bash", "-c",
      "if sudo -n true 2>/dev/null; then echo 'no'; elif find /etc/sing-box /etc/mihomo /etc/v2raya /etc/xray /etc/v2ray /etc/daed -maxdepth 2 ! -readable 2>/dev/null | grep -q .; then echo 'yes'; else echo 'no'; fi"
    ]
    stdout: StdioCollector {
      id: exportAuthOutput
      waitForEnd: true
      onStreamFinished: {
        if (String(exportAuthOutput.text).trim() === "yes") {
          root.inputPassword = ""
          root.authError = ""
          root.showPasswordPrompt = true
          Qt.callLater(function() { passwordInput.forceActiveFocus() })
        } else {
          root.startExport("")
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
      id: restoreAuthOutput
      waitForEnd: true
      onStreamFinished: {
        if (String(restoreAuthOutput.text).trim() === "yes") {
          root.inputPassword = ""
          root.authError = ""
          root.showPasswordPrompt = true
          Qt.callLater(function() { passwordInput.forceActiveFocus() })
        } else {
          root.startRestore("")
        }
      }
    }
  }

  Process {
    id: authProcess
    command: ["sudo", "-S", "-p", "", "-v"]
    stdinEnabled: true
    property string secretBuffer: ""
    onStarted: {
      if (secretBuffer.length > 0) {
        authProcess.write(secretBuffer + "\n")
        secretBuffer = ""
      }
    }
    onExited: function(code) {
      root.authValidating = false
      secretBuffer = ""
      root.inputPassword = ""
      if (code === 0) {
        root.showPasswordPrompt = false
        root.authError = ""
        var secret = root.pendingSecret
        root.pendingSecret = ""
        if (root.pendingAction === "export") {
          root.startExport(secret)
        } else if (root.pendingAction === "restore") {
          root.startRestore(secret)
        }
      } else {
        root.pendingSecret = ""
        root.authError = "Incorrect password. Please try again."
        passwordInput.selectAll()
        passwordInput.forceActiveFocus()
      }
    }
  }

  Process {
    id: exportProcess
    stdinEnabled: true
    onStarted: {
      if (root.exportSecret.length > 0) {
        exportProcess.write(root.exportSecret + "\n")
        root.exportSecret = ""
      }
    }
    stdout: SplitParser {
      onRead: function(line) {
        var clean = String(line).replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "").trim()
        if (clean.length > 0) {
          root.statusText = clean
          var match = clean.match(/Migration backup created successfully:\s*([^\s]+)/)
          if (match && match[1]) {
            root.lastExportedArchive = match[1]
          }
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
      root.exportSecret = ""
      if (code === 0) {
        root.exportStep = 2
        if (root.lastExportedArchive) {
          var displayPath = root.lastExportedArchive.replace(/\/home\/[^\/]+/, "~")
          root.statusText = "Migration backup created: " + displayPath
        } else {
          root.statusText = "Migration backup created successfully."
        }
        root.scanArchives()
      } else {
        root.exportStep = 4
        if (!root.statusText || root.statusText === "Creating migration backup...") {
          root.statusText = "Backup failed or was interrupted (code " + code + ")."
        }
        root.scanArchives()
      }
    }
  }

  Process {
    id: sendProcess
    command: [
      "bash", "-c",
      "ARCHIVE=\"$0\"\n" +
      "if [ -n \"$ARCHIVE\" ] && [ -f \"$ARCHIVE\" ]; then\n" +
      "  \"" + root.cliPath + "\" send \"$ARCHIVE\"\n" +
      "else\n" +
      "  \"" + root.cliPath + "\" send\n" +
      "fi\n",
      root.lastExportedArchive
    ]
    onExited: function() {
      root.exportStep = 3
      root.statusText = "LocalSend opened. Select a nearby device for local transfer."
    }
  }


  Process {
    id: restoreProcess
    stdinEnabled: true
    onStarted: {
      if (root.restoreSecret.length > 0) {
        restoreProcess.write(root.restoreSecret + "\n")
        root.restoreSecret = ""
      }
    }
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
      root.restoreSecret = ""
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
