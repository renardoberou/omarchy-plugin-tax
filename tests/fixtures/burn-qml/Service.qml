import QtQuick

// Test fixture: a plugin whose cost is in QML on the shell's own thread.
Item {
  property var shell: null
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: { var t = Date.now(); while (Date.now() - t < 6) {} }
  }
}
