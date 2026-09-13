import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button for the key light, and the owner of its persisted settings.
//
// Division of labour: the service owns the live values and the on-screen
// surface; this widget owns the shell.json entry. Anything that mutates the
// light — this panel, a keybinding hitting the service over IPC — ends up
// here, in `persist`, so the setting you left it on is the setting you get
// back after a shell restart.
BarWidget {
  id: root
  moduleName: "io.github.edmooredop.omakeylight"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  readonly property bool lightOn: service ? service.on === true : false
  readonly property int kelvin: service ? service.kelvin : Model.clampKelvin(setting("kelvin", 4300))
  readonly property int brightness: service ? service.brightness : Model.clampBrightness(setting("brightness", 80))
  readonly property int coverage: service ? service.coverage : Model.clampCoverage(setting("coverage", 100))
  readonly property int falloffDepth: service ? service.falloffDepth : Model.clampFalloffDepth(setting("falloffDepth", 0))

  // Settings as they currently sit in shell.json, normalized.
  readonly property var storedState: Model.normalizeSettings({
    on: setting("on", false),
    kelvin: setting("kelvin", 4300),
    brightness: setting("brightness", 80),
    coverage: setting("coverage", 100),
    falloffDepth: setting("falloffDepth", 0),
    falloffSize: setting("falloffSize", 70),
    falloffCenter: setting("falloffCenter", 50),
    falloffDirection: setting("falloffDirection", "left")
  }, null)

  // Push shell.json's values into the service. Runs when the service first
  // appears and whenever the file changes underneath us, so a hand edit of
  // shell.json takes effect live like every other Omarchy setting.
  function adoptStored() {
    if (service) service.adopt(root.storedState)
  }

  // Write the service's live values back to shell.json. Skipped when nothing
  // actually differs so a no-op mutation doesn't dirty the file.
  function persist() {
    if (!service) return
    var next = service.state()
    if (Model.settingsEqual(next, root.storedState)) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.on = next.on
    entry.kelvin = next.kelvin
    entry.brightness = next.brightness
    entry.coverage = next.coverage
    entry.falloffDepth = next.falloffDepth
    entry.falloffSize = next.falloffSize
    entry.falloffCenter = next.falloffCenter
    entry.falloffDirection = next.falloffDirection

    // Applied locally first so the bar icon updates on the click itself; the
    // write comes back through the host as the same value.
    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleLight() {
    if (service) service.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing: Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root, not on the nested panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity when the user clicks straight from one bar panel to another.
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    adoptStored()
  }
  onServiceChanged: {
    injectPanel()
    adoptStored()
  }

  Connections {
    target: root.service
    // A mutation that did not come from shell.json — the panel's sliders, or a
    // keybinding calling the service over IPC — needs writing back.
    function onChanged() { root.persist() }
  }

  // Belt and braces alongside the service's own hydration: if a reload hands
  // us a service still sitting at its defaults while shell.json says
  // otherwise, push the stored values in. `serviceFor` is a plain call rather
  // than a reactive binding, so this also runs on a short timer to catch a
  // service that appears after the widget has already been constructed.
  Timer {
    interval: 400
    repeat: true
    running: true
    onTriggered: {
      if (!root.service) return
      root.adoptStored()
      if (root.service.hydrated !== undefined) root.service.hydrated = true
      stop()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Filled bulb when lit, outline when dark.
    text: root.lightOn ? "󰛨" : "󰌵"
    active: root.lightOn
    tooltipText: root.lightOn
      ? "Key light · " + Model.summaryText(true, root.kelvin, root.brightness)
      : "Key light off"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleLight()
      else root.togglePanel()
    }

    // Scrolling on the bar icon rides the temperature — the control you are
    // most likely to want to nudge while already on camera, without opening
    // anything. Brightness and coverage live in the panel.
    onWheelMoved: function(delta) {
      if (root.service) root.service.nudgeKelvin(delta > 0 ? 1 : -1)
    }
  }
}
