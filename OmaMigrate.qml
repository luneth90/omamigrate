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
  // Export: 1 = Ready to export, 2 = Exported (show Send), 3 = Sent (show Done)
  property int exportStep: 1
  // Restore: 1 = Ready to restore, 2 = Restored (show Success)
  property int restoreStep: 1

  property bool isProcessing: false
  property string statusText: "Ready"
  property bool archiveDetected: false

  readonly property string cliPath: String(Qt.resolvedUrl("bin/omamigrate")).replace("file://", "")

  function open(payloadJson) {
    root.opened = true
    root.checkArchive()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
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
    root.statusText = "Ready"
    root.checkArchive()
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
      width: 460
      height: 330
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
            root.dismiss()
            event.accepted = true
          }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14

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
          Layout.fillWidth: true
          height: 36
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
                font.pixelSize: 13
                font.bold: root.currentMode === "export"
                color: root.currentMode === "export" ? "#cdd6f4" : "#6c7086"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
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
                font.pixelSize: 13
                font.bold: root.currentMode === "restore"
                color: root.currentMode === "restore" ? "#cdd6f4" : "#6c7086"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
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

        // Content Area: EXPORT FLOW
        ColumnLayout {
          visible: root.currentMode === "export"
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 12

          // Step 1: Export
          ColumnLayout {
            visible: root.exportStep === 1
            Layout.fillWidth: true
            spacing: 12

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
              text: "Includes installed apps, daemons, dotfiles, and AI credentials."
              font.pixelSize: 12
              color: "#a6adc8"
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item { height: 4 }

            Rectangle {
              Layout.fillWidth: true
              height: 42
              radius: 8
              color: root.isProcessing ? "#313244" : (exportBtnMouse.pressed ? "#74c7ec" : exportBtnMouse.containsMouse ? "#b4befe" : "#89b4fa")

              Text {
                anchors.centerIn: parent
                text: root.isProcessing ? "Exporting in terminal..." : "📦 Create Backup"
                font.pixelSize: 13
                font.bold: true
                color: root.isProcessing ? "#6c7086" : "#11111b"
              }

              MouseArea {
                id: exportBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.isProcessing ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                  if (root.isProcessing) return
                  root.isProcessing = true
                  root.statusText = "Exporting..."
                  exportProcess.running = true
                }
              }
            }
          }

          // Step 2: Send (Shown ONLY after Export succeeds)
          ColumnLayout {
            visible: root.exportStep === 2
            Layout.fillWidth: true
            spacing: 12

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

            Item { height: 4 }

            Rectangle {
              Layout.fillWidth: true
              height: 42
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
            spacing: 12

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

            Item { height: 8 }

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

        // Content Area: RESTORE FLOW
        ColumnLayout {
          visible: root.currentMode === "restore"
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 12

          // Step 1: Restore
          ColumnLayout {
            visible: root.restoreStep === 1
            Layout.fillWidth: true
            spacing: 12

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
              height: 34
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

            Rectangle {
              Layout.fillWidth: true
              height: 42
              radius: 8
              color: root.isProcessing ? "#313244" : (restoreBtnMouse.pressed ? "#b4befe" : restoreBtnMouse.containsMouse ? "#cba6f7" : "#cba6f7")

              Text {
                anchors.centerIn: parent
                text: root.isProcessing ? "Restoring in terminal..." : "⚡ Start Restore"
                font.pixelSize: 13
                font.bold: true
                color: root.isProcessing ? "#6c7086" : "#11111b"
              }

              MouseArea {
                id: restoreBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.isProcessing ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                  if (root.isProcessing) return
                  root.isProcessing = true
                  root.statusText = "Restoring..."
                  restoreProcess.running = true
                }
              }
            }
          }

          // Step 2: Restore Complete
          ColumnLayout {
            visible: root.restoreStep === 2
            Layout.fillWidth: true
            spacing: 12

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

            Item { height: 8 }

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
    id: exportProcess
    command: [
      "xdg-terminal-exec", "bash", "-c",
      "\"" + root.cliPath + "\" export; code=$?; echo $code > /tmp/.omamigrate_export_status; echo; read -p 'Press Enter to finish...'"
    ]
    onExited: function() {
      root.isProcessing = false
      checkExportStatusProcess.running = true
    }
  }

  Process {
    id: checkExportStatusProcess
    command: ["bash", "-c", "if [ -f /tmp/.omamigrate_export_status ] && [ \"$(cat /tmp/.omamigrate_export_status)\" = \"0\" ] && [ -f \"$HOME/omarchy-migration.tar.gz\" ]; then echo 'ok'; else echo 'fail'; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        if (String(text).trim() === "ok") {
          root.exportStep = 2
          root.statusText = "Backup ready."
          root.checkArchive()
        } else {
          root.statusText = "Export cancelled or failed."
        }
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
      "xdg-terminal-exec", "bash", "-c",
      "ARCHIVE=\"$([ -f $HOME/Downloads/omarchy-migration.tar.gz ] && echo $HOME/Downloads/omarchy-migration.tar.gz || echo $HOME/omarchy-migration.tar.gz)\"; \"" + root.cliPath + "\" restore \"$ARCHIVE\"; code=$?; echo $code > /tmp/.omamigrate_restore_status; echo; read -p 'Press Enter to finish...'"
    ]
    onExited: function() {
      root.isProcessing = false
      checkRestoreStatusProcess.running = true
    }
  }

  Process {
    id: checkRestoreStatusProcess
    command: ["bash", "-c", "if [ -f /tmp/.omamigrate_restore_status ] && [ \"$(cat /tmp/.omamigrate_restore_status)\" = \"0\" ]; then echo 'ok'; else echo 'fail'; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        if (String(text).trim() === "ok") {
          root.restoreStep = 2
          root.statusText = "Restore completed successfully."
        } else {
          root.statusText = "Restore cancelled or failed."
        }
      }
    }
  }

  Process {
    id: reloadProcess
    command: ["bash", "-c", "hyprctl reload && omarchy restart shell"]
  }
}
