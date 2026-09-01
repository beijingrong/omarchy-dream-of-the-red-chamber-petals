import QtQuick

// Layer surfaces sometimes keep their previous global position when a monitor
// is rearranged or unplugged. Briefly unmapping the surface after the new
// screen coordinates settle lets the compositor place it correctly again.
Item {
  id: root

  required property var targetWindow
  readonly property var targetScreen: targetWindow ? targetWindow.screen : null
  property bool remapping: false

  visible: false

  function scheduleRemap() {
    settleTimer.restart()
  }

  Timer {
    id: settleTimer
    interval: 200
    onTriggered: root.remapping = true
  }

  Timer {
    interval: 50
    running: root.remapping
    onTriggered: root.remapping = false
  }

  Connections {
    target: root.targetScreen
    function onXChanged() { root.scheduleRemap() }
    function onYChanged() { root.scheduleRemap() }
  }
}
