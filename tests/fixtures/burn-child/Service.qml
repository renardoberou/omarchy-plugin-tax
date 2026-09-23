import QtQuick
import Quickshell.Io

// Test fixture: a plugin whose cost lives in a helper process, the case
// Plugin Tax v0.1 could not see.
Item {
  property var shell: null
  Process {
    command: [Qt.resolvedUrl("bin/burn").toString().replace(/^file:\/\//, ""), "0.15"]
    running: true
  }
}
