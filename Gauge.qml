import QtQuick
import QtQuick.Shapes
import qs.Commons

// Copied from omarchy-plugin-speed-dashboard so the two bar dials match;
// keep fixes in sync.
//
// One analog dial, drawn after Omarchy's own speed-test cluster: an open
// 270° scale with the gap at the bottom, a red zone at the top of the scale,
// a value arc that fills behind a hubless needle. The same component draws
// the tiny bar dials and the big ones in the popup; `compact` drops the
// ticks and numerals that wouldn't survive at bar size.
Item {
  id: dial

  property real fraction: 0
  property real redlineFraction: 0.9
  property bool hot: false
  property bool live: true
  property bool compact: true
  property string glyph: ""
  property string reading: ""
  property string label: ""
  property string fontFamily: Style.font.family
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property int sweepMs: 450

  property real diameter: 22
  readonly property real dialStart: 135
  readonly property real dialSweep: 270
  readonly property real arcWidth: compact ? Math.max(1.5, diameter / 11) : Math.max(3, diameter / 40)
  readonly property real arcRadius: diameter / 2 - arcWidth
  readonly property color valueColor: hot ? urgent : accent

  // Every write to the needle funnels through `shown`, so the ignition sweep
  // and live readings share one animation.
  property real shown: 0
  readonly property real shownClamped: Math.max(0, Math.min(1, shown))
  readonly property bool arcVisible: shownClamped > 0.004

  width: diameter
  height: diameter
  opacity: live ? 1 : 0.4

  onFractionChanged: if (!ignition.running) shown = fraction
  Component.onCompleted: ignite()

  // sweepMs 0 snaps the needle: each animation frame repaints the whole
  // bar window on every monitor, so the bar dials only sweep at ignition.
  Behavior on shown {
    enabled: !ignition.running && dial.sweepMs > 0
    NumberAnimation { duration: dial.sweepMs; easing.type: Easing.OutCubic }
  }
  Behavior on opacity { NumberAnimation { duration: 240 } }

  // Car-cluster power-on: needle sweeps to full scale and falls back before
  // the live reading takes over.
  function ignite() { ignition.restart() }

  SequentialAnimation {
    id: ignition
    NumberAnimation { target: dial; property: "shown"; to: 1; duration: 500; easing.type: Easing.InOutCubic }
    NumberAnimation { target: dial; property: "shown"; to: dial.fraction; duration: 600; easing.type: Easing.OutCubic }
    onFinished: dial.shown = dial.fraction
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // Track: the full scale, always visible, dim.
    ShapePath {
      strokeWidth: dial.arcWidth
      strokeColor: Qt.rgba(dial.foreground.r, dial.foreground.g, dial.foreground.b, 0.18)
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: dial.width / 2; centerY: dial.height / 2
        radiusX: dial.arcRadius; radiusY: dial.arcRadius
        startAngle: dial.dialStart; sweepAngle: dial.dialSweep
      }
    }

    // Red zone, painted on the track the way a tach paints its redline.
    ShapePath {
      strokeWidth: dial.arcWidth
      strokeColor: Qt.rgba(dial.urgent.r, dial.urgent.g, dial.urgent.b, 0.55)
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: dial.width / 2; centerY: dial.height / 2
        radiusX: dial.arcRadius; radiusY: dial.arcRadius
        startAngle: dial.dialStart + dial.dialSweep * dial.redlineFraction
        sweepAngle: dial.dialSweep * (1 - dial.redlineFraction)
      }
    }

    // Value: fills behind the needle (big dials only). Transparent at rest
    // so the cap doesn't leave a stray dot at the foot of the scale. The bar
    // dials skip it: a changing sweep angle re-tessellates the arc on the
    // CPU every frame, where a needle is just a rotation.
    ShapePath {
      strokeWidth: dial.arcWidth
      strokeColor: !dial.compact && dial.arcVisible && dial.live ? dial.valueColor : "transparent"
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: dial.width / 2; centerY: dial.height / 2
        radiusX: dial.arcRadius; radiusY: dial.arcRadius
        startAngle: dial.dialStart; sweepAngle: dial.dialSweep * dial.shownClamped
      }
    }
  }

  // Tick ring for the big dials; every fifth tick is a major.
  Repeater {
    model: dial.compact ? 0 : 31
    Item {
      required property int index
      readonly property bool major: index % 5 === 0
      anchors.fill: parent
      rotation: dial.dialStart + (index / 30) * dial.dialSweep - 270
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dial.arcWidth * 2 + (parent.major ? 0 : 2)
        width: parent.major ? 2 : 1
        height: parent.major ? dial.diameter * 0.07 : dial.diameter * 0.045
        radius: width / 2
        color: Qt.rgba(dial.foreground.r, dial.foreground.g, dial.foreground.b, parent.major ? 0.35 : 0.15)
      }
    }
  }

  // Needle: pivots at the dial's centre, fading toward the pivot so it reads
  // as floating. On the bar dials a small hub keeps it legible at 22px.
  Item {
    anchors.fill: parent
    rotation: dial.dialStart + dial.shownClamped * dial.dialSweep - 270
    visible: dial.live
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: dial.compact ? dial.arcWidth * 0.5 : dial.arcWidth * 2 + dial.diameter * 0.06
      width: dial.compact ? Math.max(1.5, dial.diameter / 14) : Math.max(2, dial.diameter / 45)
      height: dial.compact ? dial.diameter / 2 - y : dial.diameter * 0.34
      radius: width / 2
      antialiasing: true
      gradient: Gradient {
        GradientStop { position: 0.0; color: dial.valueColor }
        GradientStop { position: dial.compact ? 0.8 : 0.55; color: dial.valueColor }
        GradientStop { position: 1.0; color: dial.compact ? dial.valueColor : "transparent" }
      }
    }
  }

  Rectangle {
    visible: dial.compact && dial.live
    anchors.centerIn: parent
    width: Math.max(3, dial.diameter / 6)
    height: width
    radius: width / 2
    color: dial.valueColor
  }

  // Bar dials: the gauge's glyph sits in the open gap at the bottom.
  Text {
    visible: dial.compact && dial.glyph !== ""
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: -2
    text: dial.glyph
    color: dial.hot ? dial.urgent : dial.foreground
    opacity: 0.8
    font.family: dial.fontFamily
    font.pixelSize: Math.max(8, Math.round(dial.diameter * 0.42))
  }

  // Big dials: digital readout in the middle, label in the gap.
  Text {
    visible: !dial.compact
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.verticalCenter
    anchors.topMargin: dial.diameter * 0.08
    text: dial.reading
    color: dial.hot ? dial.urgent : dial.foreground
    font.family: dial.fontFamily
    font.pixelSize: Math.round(dial.diameter * 0.16)
    font.bold: true
  }

  Text {
    visible: !dial.compact
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    text: dial.label
    color: Qt.rgba(dial.foreground.r, dial.foreground.g, dial.foreground.b, 0.6)
    font.family: dial.fontFamily
    font.pixelSize: Math.max(9, Math.round(dial.diameter * 0.1))
    font.bold: true
    font.letterSpacing: 1.5
  }
}
