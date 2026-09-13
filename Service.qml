import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import "Model.js" as Model

// The light itself.
//
// One layer-shell surface per monitor, sitting on WlrLayer.Bottom: above the
// wallpaper, below every ordinary window. That single choice is what makes the
// plugin useful on a call — the light fills whatever part of the screen you
// are not currently covering with a browser or a terminal, and those windows
// keep working normally on top of it. Nothing is ever raised over your work.
//
// The surface's input region is empty (`mask: Region {}`), so clicks, drags,
// and scrolls pass straight through to the desktop underneath. The light is
// only ever something you look at, never something you hit.
Item {
  id: root

  // Injected by the host.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // The shell recreates this service on every plugin reload, which means a
  // fresh instance starts at the property defaults above — light off — even
  // though shell.json still says it was on. The bar widget cannot be relied on
  // to repair that: its `serviceFor` lookup is a plain function call, not a
  // reactive binding, so a swapped-out service does not re-notify it.
  //
  // So hydrate from the injected bar config instead. It carries this plugin's
  // own layout entry, which is exactly the persisted state, and it is injected
  // before anything paints. `hydrated` makes it strictly a startup step: a
  // later re-injection carrying a stale snapshot must not stamp over values
  // the user has since changed.
  property bool hydrated: false

  onShellChanged: hydrateFromConfig()

  function hydrateFromConfig() {
    if (hydrated || !shell || !shell.barConfig) return
    var layout = shell.barConfig.layout
    if (!layout) return

    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry || String(entry.id) !== "io.github.edmooredop.omakeylight") continue
        hydrated = true
        adopt(entry)
        return
      }
    }
  }

  // ---- state -------------------------------------------------------------
  // The bar widget owns persistence (it is the thing with a shell.json entry).
  // This service owns the live values and the pixels. `changed()` is how the
  // widget hears about a mutation that came in over IPC — a keybinding, say —
  // so it can write the new value back to shell.json.
  property bool on: false
  property int kelvin: 4300
  property int brightness: 80
  property int coverage: 100

  // Horizontal falloff, simulating the way a real light source drops off
  // across a face. `falloffDepth` 0 disables it entirely and keeps the old
  // flat-panel behaviour.
  property int falloffDepth: 0
  property int falloffSize: 70
  property int falloffCenter: 50
  property string falloffDirection: "left"

  signal changed()

  readonly property color lightColor: Model.lightColor(root.kelvin, root.brightness)
  readonly property string summary: Model.summaryText(root.on, root.kelvin, root.brightness)

  // Gradient stops for the current falloff, as {position, level} pairs. The
  // surface turns each level into a colour; keeping the maths out here means
  // the same numbers are unit-testable under plain Node.
  readonly property var falloffStops: Model.falloffStops(
    root.falloffDepth, root.falloffSize, root.falloffCenter, root.falloffDirection, 14)
  readonly property bool falloffActive: root.falloffDepth > 0

  // Adopt persisted settings without echoing them straight back as a change.
  // Used by the bar widget on load and whenever shell.json is edited by hand.
  function adopt(state) {
    if (!state) return
    var next = Model.normalizeSettings(state, null)
    if (next.on === root.on && next.kelvin === root.kelvin
      && next.brightness === root.brightness && next.coverage === root.coverage
      && next.falloffDepth === root.falloffDepth && next.falloffSize === root.falloffSize
      && next.falloffCenter === root.falloffCenter
      && next.falloffDirection === root.falloffDirection) return
    root.on = next.on
    root.kelvin = next.kelvin
    root.brightness = next.brightness
    root.coverage = next.coverage
    root.falloffDepth = next.falloffDepth
    root.falloffSize = next.falloffSize
    root.falloffCenter = next.falloffCenter
    root.falloffDirection = next.falloffDirection
  }

  function state() {
    return {
      on: root.on,
      kelvin: root.kelvin,
      brightness: root.brightness,
      coverage: root.coverage,
      falloffDepth: root.falloffDepth,
      falloffSize: root.falloffSize,
      falloffCenter: root.falloffCenter,
      falloffDirection: root.falloffDirection
    }
  }

  function setOn(value) {
    var next = value === true
    if (next === root.on) return
    root.on = next
    root.changed()
  }

  function toggle() { setOn(!root.on) }

  function setKelvin(value) {
    var next = Model.clampKelvin(value, root.kelvin)
    if (next === root.kelvin) return
    root.kelvin = next
    root.changed()
  }

  function setBrightness(value) {
    var next = Model.clampBrightness(value, root.brightness)
    if (next === root.brightness) return
    root.brightness = next
    root.changed()
  }

  function setCoverage(value) {
    var next = Model.clampCoverage(value, root.coverage)
    if (next === root.coverage) return
    root.coverage = next
    root.changed()
  }

  function nudgeKelvin(delta) { setKelvin(Model.stepKelvin(root.kelvin, delta)) }
  function nudgeBrightness(delta) { setBrightness(Model.stepBrightness(root.brightness, delta)) }

  function setFalloffDepth(value) {
    var next = Model.clampFalloffDepth(value, root.falloffDepth)
    if (next === root.falloffDepth) return
    root.falloffDepth = next
    root.changed()
  }

  function setFalloffSize(value) {
    var next = Model.clampFalloffSize(value, root.falloffSize)
    if (next === root.falloffSize) return
    root.falloffSize = next
    root.changed()
  }

  function setFalloffCenter(value) {
    var next = Model.clampFalloffCenter(value, root.falloffCenter)
    if (next === root.falloffCenter) return
    root.falloffCenter = next
    root.changed()
  }

  function setFalloffDirection(value) {
    var next = Model.clampDirection(value, root.falloffDirection)
    if (next === root.falloffDirection) return
    root.falloffDirection = next
    root.changed()
  }

  function flipFalloff() {
    setFalloffDirection(Model.flipDirection(root.falloffDirection))
  }

  // ---- IPC ---------------------------------------------------------------
  // Bindable from Hyprland, e.g.
  //   o.bind("SUPER SHIFT", "L", "exec", "omarchy-shell keylight toggle")
  IpcHandler {
    target: "keylight"

    function toggle(): string { root.toggle(); return root.on ? "on" : "off" }
    function on(): string { root.setOn(true); return "on" }
    function off(): string { root.setOn(false); return "off" }
    function warmer(): string { root.nudgeKelvin(-1); return String(root.kelvin) }
    function cooler(): string { root.nudgeKelvin(1); return String(root.kelvin) }
    function brighter(): string { root.nudgeBrightness(1); return String(root.brightness) }
    function dimmer(): string { root.nudgeBrightness(-1); return String(root.brightness) }
    function setTemperature(value: string): string { root.setKelvin(value); return String(root.kelvin) }
    function setBrightness(value: string): string { root.setBrightness(value); return String(root.brightness) }
    function setCoverage(value: string): string { root.setCoverage(value); return String(root.coverage) }
    function setFalloff(value: string): string { root.setFalloffDepth(value); return String(root.falloffDepth) }
    function setFalloffSize(value: string): string { root.setFalloffSize(value); return String(root.falloffSize) }
    function setFalloffCenter(value: string): string { root.setFalloffCenter(value); return String(root.falloffCenter) }
    function setFalloffDirection(value: string): string { root.setFalloffDirection(value); return root.falloffDirection }
    function flipFalloff(): string { root.flipFalloff(); return root.falloffDirection }
    function status(): string { return JSON.stringify(root.state()) }
    function ping(): string { return "ok" }
  }

  Component.onCompleted: hydrateFromConfig()

  // ---- the surface -------------------------------------------------------

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      // Kept mapped through the fade so the opacity animation has something to
      // animate; `remapping` pulses it unmapped when the monitor moves.
      visible: (root.on || fill.opacity > 0) && !remapGuard.remapping
      color: "transparent"

      anchors { top: true; left: true; right: true }
      // Coverage measures down from the top of the screen, because a webcam
      // above the monitor wants light on your face rather than on your desk.
      // Leaving the bottom unanchored and setting an explicit height is what
      // gives layer-shell a partial-height surface to place against the top
      // edge; anchoring all four sides would force it full-height.
      implicitHeight: Math.max(1, Math.round(
        (panel.screen ? panel.screen.height : 0) * root.coverage / 100))

      // Above the wallpaper, below every window. The whole point of the
      // plugin: you get lit, and you can still work over the top of it.
      WlrLayershell.namespace: "keylight"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Empty input region: purely something to look at. Clicks, scrolls, and
      // drags all land on whatever is underneath, including the wallpaper's
      // own double-click-to-change-background handler.
      mask: Region {}

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }

      // The light itself. Painted as a horizontal gradient rather than a flat
      // fill, so brightness can fall away across the screen the way a real
      // light does.
      //
      // Canvas rather than Rectangle+Gradient: a declarative Gradient needs
      // its stops declared literally, so the stop list cannot be generated
      // from live settings — a Repeater is rejected outright, and a JS array
      // binding evaluates once and then freezes. Repainting a canvas on change
      // keeps the falloff genuinely reactive.
      Canvas {
        id: fill
        anchors.fill: parent
        opacity: root.on ? 1 : 0

        // Long enough to read as a light coming up rather than a flash, short
        // enough not to feel sluggish when you toggle it mid-call.
        Behavior on opacity {
          NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }

        // Repaint whenever anything about the light changes. Cheap: this is a
        // single fillRect over a linear gradient, not a per-pixel loop.
        readonly property color tint: root.lightColor
        readonly property int depth: root.falloffDepth
        readonly property int size: root.falloffSize
        readonly property int center: root.falloffCenter
        readonly property string direction: root.falloffDirection

        onTintChanged: requestPaint()
        onDepthChanged: requestPaint()
        onSizeChanged: requestPaint()
        onCenterChanged: requestPaint()
        onDirectionChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)

          var gradient = ctx.createLinearGradient(0, 0, width, 0)
          var stops = Model.falloffStops(depth, size, center, direction)
          for (var i = 0; i < stops.length; i++) {
            var level = stops[i].level
            gradient.addColorStop(stops[i].position,
              Qt.rgba(tint.r * level, tint.g * level, tint.b * level, 1))
          }

          ctx.fillStyle = gradient
          ctx.fillRect(0, 0, width, height)
        }
      }
    }
  }
}
