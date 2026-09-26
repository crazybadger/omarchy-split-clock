import QtQuick
import qs.Commons

// The stopwatch page, after Apple's (digital view only): the running time at
// the top, Lap/Reset and Start/Stop in the middle, and the running lap plus
// the most recent laps below -- as many as fit, at most five. All the state
// lives in Stopwatch.qml; this only draws it.
Item {
  id: root

  property var sw: null          // Stopwatch.qml
  property bool active: false    // popup open and this page showing
  property color ink: "white"
  property string fontFamily: "monospace"

  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.28)

  // Repainted every 50 ms only while it's on screen and counting; otherwise
  // the figures are static and nothing ticks.
  property real nowMs: Date.now()
  Timer {
    interval: 50
    repeat: true
    running: root.active && root.sw !== null && root.sw.running
    onTriggered: root.nowMs = Date.now()
  }
  onActiveChanged: nowMs = Date.now()

  readonly property real elapsed: sw ? sw.elapsedAt(nowMs) : 0
  readonly property real currentLap: sw ? sw.currentLapAt(nowMs) : 0

  // Fastest and slowest completed laps, marked once there are two to compare.
  readonly property int bestLap: {
    if (!sw || sw.laps.length < 2) return -1
    var best = 0
    for (var i = 1; i < sw.laps.length; i++) if (sw.laps[i] < sw.laps[best]) best = i
    return best
  }
  readonly property int worstLap: {
    if (!sw || sw.laps.length < 2) return -1
    var worst = 0
    for (var i = 1; i < sw.laps.length; i++) if (sw.laps[i] > sw.laps[worst]) worst = i
    return worst
  }

  readonly property real unit: width
  readonly property real rowHeight: Math.round(unit * 0.07)
  readonly property int maxRows: Math.max(0, Math.min(5, Math.floor(lapArea.height / rowHeight)))

  // The running lap first, then completed laps newest first, trimmed to fit.
  readonly property var rows: {
    if (!sw || sw.fresh) return []
    var out = [{ n: sw.laps.length + 1, ms: -1 }]
    for (var i = sw.laps.length - 1; i >= 0 && out.length < maxRows; i--)
      out.push({ n: i + 1, ms: sw.laps[i] })
    return out.slice(0, maxRows)
  }

  component RoundButton: Item {
    id: button
    property string label: ""
    property color tint: root.ink
    signal clicked()

    width: Math.round(root.unit * 0.19)
    height: width
    opacity: enabled ? 1 : 0.4

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Qt.rgba(button.tint.r, button.tint.g, button.tint.b, area.containsMouse && button.enabled ? 0.28 : 0.18)
      antialiasing: true
      Behavior on color { ColorAnimation { duration: 120 } }
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.label
      color: button.tint
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.unit * 0.042)
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }

  // ---- The running time.
  Text {
    id: display
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(root.height * 0.07)
    textFormat: Text.PlainText
    text: root.sw ? root.sw.format(root.elapsed) : "00:00.0"
    color: root.ink
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.unit * 0.16)
    font.weight: Font.Light
  }

  // ---- Lap/Reset and Start/Stop.
  Item {
    id: buttons
    anchors.top: display.bottom
    anchors.topMargin: Math.round(root.height * 0.05)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.round(root.unit * 0.74)
    height: lapButton.height

    RoundButton {
      id: lapButton
      anchors.left: parent.left
      label: root.sw && !root.sw.running && !root.sw.fresh ? "Reset" : "Lap"
      enabled: root.sw !== null && !root.sw.fresh
      onClicked: root.sw.lapOrReset()
    }

    RoundButton {
      anchors.right: parent.right
      label: root.sw && root.sw.running ? "Stop" : "Start"
      tint: root.sw && root.sw.running ? Color.urgent : Color.accent
      onClicked: root.sw.toggle()
    }
  }

  // ---- Laps.
  Item {
    id: lapArea
    anchors.top: buttons.bottom
    anchors.topMargin: Math.round(root.height * 0.05)
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: buttons.width

    Column {
      width: parent.width

      Repeater {
        model: root.rows

        Item {
          required property var modelData
          width: lapArea.width
          height: root.rowHeight

          readonly property bool isCurrent: modelData.ms < 0
          readonly property int lapIndex: modelData.n - 1
          readonly property color tone: isCurrent ? root.ink
            : lapIndex === root.bestLap ? Color.accent
            : lapIndex === root.worstLap ? Color.urgent
            : root.ink

          Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: root.muted
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Lap " + modelData.n
            color: parent.tone
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.unit * 0.036)
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.sw ? root.sw.format(parent.isCurrent ? root.currentLap : modelData.ms) : ""
            color: parent.tone
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.unit * 0.036)
          }
        }
      }
    }
  }
}
