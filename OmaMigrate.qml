import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property bool opened: false
  property string statusText: "Ready to migrate or sync."
  property bool isProcessing: false

  function summon() {
    opened = !opened
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "OmaMigrate"
    width: 480
    height: 380

    color: "#1e1e2e"

    Rectangle {
      anchors.fill: parent
      color: "#1e1e2e"
      radius: 12
      border.color: "#313244"
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        // Title Row
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "⚡ OmaMigrate"
            font.pixelSize: 22
            font.bold: true
            color: "#cdd6f4"
          }
          Item { Layout.fillWidth: true }
          Text {
            text: "v1.0.0"
            font.pixelSize: 12
            color: "#6c7086"
          }
        }

        Text {
          text: "One-click Omarchy system, apps, credentials & services migration."
          font.pixelSize: 13
          color: "#a6adc8"
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: "#313244"
        }

        // Action Buttons
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 12

          Button {
            Layout.fillWidth: true
            height: 42
            text: "📦 1. Export & Package System (一键打包)"
            enabled: !root.isProcessing
            onClicked: {
              root.isProcessing = true
              root.statusText = "Exporting in terminal..."
              exportProcess.running = true
            }
          }

          Button {
            Layout.fillWidth: true
            height: 42
            text: "📡 2. Beam via LocalSend (隔空快传)"
            enabled: !root.isProcessing
            onClicked: {
              root.statusText = "Launching LocalSend..."
              sendProcess.running = true
            }
          }

          Button {
            Layout.fillWidth: true
            height: 42
            text: "⚡ 3. Restore from ~/Downloads (一键还原)"
            enabled: !root.isProcessing
            onClicked: {
              root.isProcessing = true
              root.statusText = "Restoring in terminal..."
              restoreProcess.running = true
            }
          }
        }

        Item { Layout.fillHeight: true }

        // Status text
        Rectangle {
          Layout.fillWidth: true
          height: 36
          radius: 6
          color: "#181825"
          border.color: "#313244"

          Text {
            anchors.centerIn: parent
            text: root.statusText
            color: "#89b4fa"
            font.pixelSize: 12
          }
        }
      }
    }
  }

  readonly property string cliPath: String(Qt.resolvedUrl("bin/omamigrate")).replace("file://", "")

  Process {
    id: exportProcess
    command: ["xdg-terminal-exec", "bash", "-c", "\"" + root.cliPath + "\" export; echo; read -p 'Press Enter to finish...'"]
    onExited: function(code) {
      root.isProcessing = false
      if (code === 0) {
        root.statusText = "Export completed: ~/omarchy-migration.tar.gz"
      } else {
        root.statusText = "Export finished or cancelled."
      }
    }
  }

  Process {
    id: sendProcess
    command: ["bash", "-c", "\"" + root.cliPath + "\" send"]
    onExited: function() {
      root.statusText = "LocalSend launched."
    }
  }

  Process {
    id: restoreProcess
    command: ["xdg-terminal-exec", "bash", "-c", "\"" + root.cliPath + "\" restore ~/Downloads/omarchy-migration.tar.gz; echo; read -p 'Press Enter to finish...'"]
    onExited: function(code) {
      root.isProcessing = false
      if (code === 0) {
        root.statusText = "Restoration completed successfully!"
      } else {
        root.statusText = "Restore finished or cancelled."
      }
    }
  }
}
