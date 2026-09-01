pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  // Injected by omarchy-shell. Optional settings live alongside this plugin's
  // entry in ~/.config/omarchy/shell.json.
  property var shell: null
  property bool active: true
  property bool themeOptIn: false
  property string activeTheme: ""

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")
  readonly property bool rendering: active && themeOptIn

  readonly property var settings: {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    var entries = config && config.plugins instanceof Array ? config.plugins : []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && String(entries[i].id || "") === "io.github.beijingrong.red-chamber-petals") return entries[i]
    }
    return ({})
  }

  function numberSetting(key, fallback, minimum, maximum) {
    var value = Number(settings[key])
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  readonly property int framesPerSecond: Math.round(numberSetting("fps", 20, 12, 30))
  readonly property int basePetalCount: Math.round(numberSetting("petals", 27, 12, 55))
  readonly property real density: numberSetting("density", 0.78, 0.35, 1.4)
  readonly property real speed: numberSetting("speed", 1.0, 0.45, 2.0)
  readonly property real wind: numberSetting("wind", 1.0, -1.5, 2.5)
  readonly property var petalSources: [
    "petal-blush.svg",
    "petal-rose.svg",
    "petal-ivory.svg"
  ]

  function markerEnabled(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (/^\s*enabled\s*=\s*true\s*(?:#.*)?$/i.test(lines[i])) return true
    }
    return false
  }

  function refreshThemeMarker() {
    Qt.callLater(function() { themeMarkerFile.reload() })
  }

  function stateLabel() {
    if (!active) return "paused"
    return themeOptIn ? "running" : "inactive-theme"
  }

  // Themes opt in with a static red-chamber-petals.toml file. Watching the
  // always-present theme name lets us re-probe the marker after Omarchy swaps
  // the current theme directory atomically.
  FileView {
    id: themeNameFile
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.activeTheme = String(text() || "").trim()
      root.refreshThemeMarker()
    }
    onLoadFailed: {
      root.activeTheme = ""
      root.themeOptIn = false
    }
    onFileChanged: reload()
  }

  FileView {
    id: themeMarkerFile
    path: root.stateHome + "/omarchy/current/theme/red-chamber-petals.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.themeOptIn = root.markerEnabled(text())
    onLoadFailed: root.themeOptIn = false
    onFileChanged: reload()
  }

  IpcHandler {
    target: "red-chamber-petals"

    function pause(): string {
      root.active = false
      return root.stateLabel()
    }

    function resume(): string {
      root.active = true
      return root.stateLabel()
    }

    function toggle(): string {
      root.active = !root.active
      return root.stateLabel()
    }

    function status(): string {
      return root.stateLabel()
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: root.rendering && !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      updatesEnabled: root.rendering

      WlrLayershell.namespace: "io-github-beijingrong-red-chamber-petals"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Decorative only: desktop and application input passes through.
      mask: Region {}

      ScreenRemapGuard {
        id: remapGuard
        targetWindow: panel
      }

      Item {
        id: petalField
        anchors.fill: parent

        readonly property real areaScale: Math.sqrt(
          Math.max(1, width * height) / (1920 * 1080)
        )

        Repeater {
          id: petals
          model: Math.min(80, Math.max(8, Math.round(root.basePetalCount * root.density * petalField.areaScale)))

          delegate: Item {
            id: petal
            required property int index

            property real petalSize: 13
            property real centerX: 0
            property real fallSpeed: 20
            property real windSpeed: 4
            property real driftRange: 30
            property real phase: 0
            property real swayRate: 0.8
            property real spinSpeed: 20
            property int variant: 0

            width: petalSize
            height: petalSize * 1.42
            transformOrigin: Item.Center

            function reset(firstRun) {
              petalSize = 9 + Math.random() * 10
              centerX = Math.random() * Math.max(1, panel.width)
              // Speeds are expressed per second. At the default 20 fps they
              // match the original motion, while changing fps now affects only
              // smoothness rather than the physical fall rate.
              fallSpeed = (0.85 + Math.random() * 1.35) * 20 * root.speed
              windSpeed = (0.10 + Math.random() * 0.18) * 20 * root.wind
              driftRange = 14 + Math.random() * 42
              phase = Math.random() * Math.PI * 2
              swayRate = (0.025 + Math.random() * 0.035) * 20
              spinSpeed = (Math.random() - 0.5) * 3.2 * 20
              variant = Math.floor(Math.random() * root.petalSources.length)
              opacity = 0.48 + Math.random() * 0.40
              rotation = Math.random() * 360
              x = centerX
              y = firstRun
                ? -height + Math.random() * (Math.max(1, panel.height) + height)
                : -height - Math.random() * Math.max(20, panel.height * 0.12)
            }

            function step(deltaSeconds) {
              phase += swayRate * deltaSeconds
              centerX += windSpeed * deltaSeconds
              x = centerX + Math.sin(phase) * driftRange
              y += fallSpeed * deltaSeconds
              rotation += spinSpeed * deltaSeconds

              if (y > panel.height + height || x > panel.width + 120 || x < -120) reset(false)
            }

            Component.onCompleted: reset(true)

            Image {
              anchors.fill: parent
              source: root.petalSources[petal.variant]
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true
              asynchronous: true
            }
          }
        }

        Timer {
          property double lastTickMs: 0

          interval: Math.round(1000 / root.framesPerSecond)
          repeat: true
          running: root.rendering && panel.visible
          onRunningChanged: lastTickMs = running ? Date.now() : 0
          onTriggered: {
            var now = Date.now()
            var deltaSeconds = lastTickMs > 0
              ? Math.max(0.001, Math.min(0.1, (now - lastTickMs) / 1000))
              : 1 / root.framesPerSecond
            lastTickMs = now

            for (var i = 0; i < petals.count; i++) {
              var petal = petals.itemAt(i)
              if (petal) petal.step(deltaSeconds)
            }
          }
        }
      }
    }
  }
}
