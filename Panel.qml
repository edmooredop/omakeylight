import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Key light panel: a preview swatch, an on/off switch, and three sliders.
//
// Keyboard model follows the other Omarchy panels — j/k walks the sections,
// h/l adjusts whichever slider the cursor is on, Space toggles the light, and
// mouse hover writes the same cursor state so there is only ever one highlight
// on screen.
Panel {
  id: root
  moduleName: "io.github.edmooredop.omakeylight"
  ipcTarget: "keylight.panel"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool lightOn: service ? service.on === true : false
  readonly property int kelvin: service ? service.kelvin : 4300
  readonly property int brightness: service ? service.brightness : 80
  readonly property int coverage: service ? service.coverage : 100
  readonly property int falloffDepth: service ? service.falloffDepth : 0
  readonly property int falloffSize: service ? service.falloffSize : 70
  readonly property int falloffCenter: service ? service.falloffCenter : 50
  readonly property string falloffDirection: service ? service.falloffDirection : "left"
  readonly property bool spanMonitors: service ? service.spanMonitors === true : true
  readonly property bool falloffActive: falloffDepth > 0

  // Monitor arrangement, for the preview. Only shown when there is more than
  // one and they are being treated as one light; otherwise the row is hidden
  // rather than left as a dead control.
  readonly property var screenRects: service && service.screenRects ? service.screenRects : []
  readonly property bool multiMonitor: screenRects.length > 1
  readonly property var seams: multiMonitor && spanMonitors ? Model.screenSeams(screenRects) : []

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Sections, top to bottom. Each slider is a single row, so j/k moves
  // between them and h/l adjusts within one.
  readonly property var sections: ["power", "temperature", "brightness", "coverage",
    "falloff", "falloffSize", "falloffCenter", "direction", "span"]
  property string focusSection: "power"
  property bool cursorActive: false

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy !== 0) {
      var index = sections.indexOf(focusSection)
      if (index < 0) index = 0
      focusSection = sections[Math.max(0, Math.min(sections.length - 1, index + dy))]
      return
    }
    if (dx === 0 || !service) return
    if (focusSection === "temperature") service.nudgeKelvin(dx)
    else if (focusSection === "brightness") service.nudgeBrightness(dx)
    else if (focusSection === "coverage") service.setCoverage(coverage + dx * 5)
    else if (focusSection === "falloff") service.setFalloffDepth(falloffDepth + dx * 5)
    else if (focusSection === "falloffSize") service.setFalloffSize(falloffSize + dx * 5)
    else if (focusSection === "falloffCenter") service.setFalloffCenter(falloffCenter + dx * 5)
    else if (focusSection === "direction") service.flipFalloff()
    else if (focusSection === "span") service.toggleSpanMonitors()
  }

  function activateCursor() {
    if (focusSection === "power" && service) service.toggle()
    else if (focusSection === "direction" && service) service.flipFalloff()
    else if (focusSection === "span" && service) service.toggleSpanMonitors()
  }

  function setCursor(section) {
    cursorActive = true
    focusSection = section
  }

  function openFromHotkey() {
    root.controller.show()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "power"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(9)

        // Live preview of exactly what the screen will be filled with, at the
        // current temperature and brightness. Reading a swatch beats reading
        // "4300K" when what you actually care about is how it looks on skin.
        PanelHero {
          id: hero
          width: parent.width
          title: "Key light"
          meta: root.lightOn
            ? Model.kelvinLabel(root.kelvin) + " · " + Model.summaryText(true, root.kelvin, root.brightness)
            : "Off"
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Rectangle {
              width: Style.space(30)
              height: Style.space(30)
              radius: Style.cornerRadius > 0 ? width / 2 : Style.cornerRadius
              color: Model.lightColor(root.kelvin, root.brightness)
              opacity: root.lightOn ? 1 : 0.35
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)

              Behavior on color { ColorAnimation { duration: 160 } }
            }
          }

          trailingControl: Component {
            ToggleSwitch {
              checked: root.lightOn
              hasCursor: root.cursorActive && root.focusSection === "power"
              foreground: root.foreground
              onHovered: function(on) { if (on) root.setCursor("power") }
              onToggled: if (root.service) root.service.toggle()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        SliderRow {
          id: temperatureRow
          width: parent.width
          section: "temperature"
          label: "TEMPERATURE"
          readout: root.kelvin + "K · " + Model.kelvinLabel(root.kelvin)
          minimum: Model.MIN_KELVIN
          maximum: Model.MAX_KELVIN
          step: Model.KELVIN_STEP
          value: root.kelvin
          onCommitted: function(next) { if (root.service) root.service.setKelvin(next) }
        }

        SliderRow {
          width: parent.width
          section: "brightness"
          label: "BRIGHTNESS"
          readout: root.brightness + "%"
          minimum: Model.MIN_BRIGHTNESS
          maximum: Model.MAX_BRIGHTNESS
          step: 1
          value: root.brightness
          onCommitted: function(next) { if (root.service) root.service.setBrightness(next) }
        }

        SliderRow {
          width: parent.width
          section: "coverage"
          label: "COVERAGE"
          readout: Model.coverageLabel(root.coverage)
          minimum: Model.MIN_COVERAGE
          maximum: Model.MAX_COVERAGE
          step: 5
          value: root.coverage
          onCommitted: function(next) { if (root.service) root.service.setCoverage(next) }
        }

        PanelSeparator { foreground: root.foreground }

        // Live preview of the falloff across the screen's width, so the shape
        // is visible without staring at the monitor edge-on while dragging.
        // Doubles as the affordance that makes "size" and "centre" legible.
        Item {
          width: parent.width
          implicitHeight: Style.space(26)

          Canvas {
            id: falloffPreview
            anchors.fill: parent
            opacity: root.lightOn ? 1 : 0.45

            readonly property color tint: Model.lightColor(root.kelvin, root.brightness)
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

              ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
              ctx.lineWidth = 1
              ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
            }
          }

          // Marks where the centre of the blend sits, so the centre slider has
          // something to point at.
          Rectangle {
            visible: root.falloffActive
            width: 1
            height: parent.height - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            x: Math.round((parent.width - 1) * (root.falloffDirection === "left"
              ? root.falloffCenter / 100 : 1 - root.falloffCenter / 100))
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.5)
          }

          // Bezels. When the monitors are one light, the preview is the whole
          // arrangement and these show where one screen ends and the next
          // begins, so "centre 50%" can be read against real hardware.
          Repeater {
            model: root.seams
            delegate: Rectangle {
              required property real modelData
              width: 2
              height: parent.height
              x: Math.round((parent.width - 2) * modelData)
              color: bar ? bar.background : Color.background
              opacity: 0.85
            }
          }
        }

        SliderRow {
          width: parent.width
          section: "falloff"
          label: "FALLOFF"
          readout: Model.falloffDepthLabel(root.falloffDepth)
          minimum: Model.MIN_FALLOFF_DEPTH
          maximum: Model.MAX_FALLOFF_DEPTH
          step: 5
          value: root.falloffDepth
          onCommitted: function(next) { if (root.service) root.service.setFalloffDepth(next) }
        }

        SliderRow {
          width: parent.width
          section: "falloffSize"
          label: "BLEND SIZE"
          readout: Model.falloffSizeLabel(root.falloffSize)
          minimum: Model.MIN_FALLOFF_SIZE
          maximum: Model.MAX_FALLOFF_SIZE
          step: 5
          value: root.falloffSize
          enabled: root.falloffActive
          onCommitted: function(next) { if (root.service) root.service.setFalloffSize(next) }
        }

        SliderRow {
          width: parent.width
          section: "falloffCenter"
          label: "BLEND CENTRE"
          readout: Model.falloffCenterLabel(root.falloffCenter)
          minimum: Model.MIN_FALLOFF_CENTER
          maximum: Model.MAX_FALLOFF_CENTER
          step: 5
          value: root.falloffCenter
          enabled: root.falloffActive
          onCommitted: function(next) { if (root.service) root.service.setFalloffCenter(next) }
        }

        // Which side stays lit. Two chips rather than a switch, because
        // "bright left" and "bright right" are two named choices, not an
        // on/off of one thing.
        Column {
          width: parent.width
          spacing: Style.space(5)
          opacity: root.falloffActive ? 1 : 0.45
          bottomPadding: Style.space(2)

          Behavior on opacity { NumberAnimation { duration: 140 } }

          PanelSectionHeader {
            text: "LIGHT FROM"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            focusable: false
            options: [
              { value: "left", label: "Left", tooltip: "Bright on the left, falling away to the right" },
              { value: "right", label: "Right", tooltip: "Bright on the right, falling away to the left" }
            ]
            value: root.falloffDirection
            cursorIndex: root.cursorActive && root.focusSection === "direction"
              ? (root.falloffDirection === "left" ? 0 : 1) : -1
            foreground: root.foreground
            background: bar ? bar.background : Color.background
            accent: bar ? bar.foreground : Color.accent
            fontFamily: root.fontFamily
            onChanged: function(value) { if (root.service) root.service.setFalloffDirection(value) }
            onHovered: function(index, isHovered) { if (isHovered) root.setCursor("direction") }
          }
        }

        // Only meaningful with two or more monitors; hidden otherwise so a
        // laptop on its own doesn't carry a switch that does nothing.
        Column {
          width: parent.width
          spacing: Style.space(5)
          visible: root.multiMonitor
          opacity: root.falloffActive ? 1 : 0.45
          bottomPadding: Style.space(2)

          Behavior on opacity { NumberAnimation { duration: 140 } }

          PanelSeparator { foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(spanTitle.implicitHeight, spanSwitch.implicitHeight)

            PanelSectionHeader {
              id: spanTitle
              anchors.left: parent.left
              anchors.right: spanSwitch.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "TREAT ALL MONITORS AS ONE SOURCE"
              elide: Text.ElideRight
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleSwitch {
              id: spanSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.spanMonitors
              hasCursor: root.cursorActive && root.focusSection === "span"
              foreground: root.foreground
              onHovered: function(on) { if (on) root.setCursor("span") }
              onToggled: if (root.service) root.service.toggleSpanMonitors()
            }
          }
        }
      }
    }
  }

  // A labelled slider row: header and readout above, track below, the whole
  // thing wrapped in the shared cursor chrome so keyboard and mouse paint the
  // same highlight.
  component SliderRow: Column {
    id: row

    property string section: ""
    property string label: ""
    property string readout: ""
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property real value: 0
    property bool enabled: true

    signal committed(real value)

    readonly property bool hasCursor: root.cursorActive && root.focusSection === row.section

    spacing: Style.space(5)
    opacity: root.lightOn ? (row.enabled ? 1 : 0.45) : 0.55

    Behavior on opacity { NumberAnimation { duration: 140 } }

    Item {
      width: parent.width
      implicitHeight: Math.max(rowTitle.implicitHeight, rowValue.implicitHeight)

      PanelSectionHeader {
        id: rowTitle
        anchors.left: parent.left
        anchors.right: rowValue.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        elide: Text.ElideRight
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        id: rowValue
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: row.readout
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    CursorSurface {
      width: parent.width
      height: slider.implicitHeight + Style.spacing.controlGap
      hasCursor: row.hasCursor
      outline: true
      foreground: root.foreground
      accent: bar ? bar.foreground : Color.accent

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.setCursor(row.section)
      }

      PanelSlider {
        id: slider
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        minimum: row.minimum
        maximum: row.maximum
        step: row.step
        value: row.value
        integer: true
        // Fire on both so dragging previews live and a click on the track
        // still commits — the service clamps and dedupes either way.
        onMoved: function(next) { row.committed(next) }
        onReleased: function(next) { row.committed(next) }
      }
    }
  }
}
