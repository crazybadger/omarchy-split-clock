import QtQuick
import qs.Commons
import qs.Ui

// The alarms page, laid out like the world clock: a row to add one at the top
// (a time typed or scrolled like the timer's, an optional label, +), and the
// alarms below -- the time, the label and the repeat days (click a letter;
// none lit is once), an on/off switch, and the ringed ✕ on hover. Six fit,
// which is also the limit. While one is ringing, the add row gives way to
// Snooze and Stop. The alarms themselves live in Alarms.qml.
Item {
  id: root

  property var alarms: null      // Alarms.qml
  property bool active: false
  property color ink: "white"
  property string fontFamily: "monospace"

  readonly property bool labelFocused: labelField.activeFocus
  signal releaseFocus()

  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.28)
  readonly property color soft: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
  readonly property real unit: width
  readonly property var list: alarms ? alarms.alarms : []
  readonly property bool full: alarms ? alarms.full : false
  readonly property bool ringing: alarms ? alarms.ringing : false

  onActiveChanged: if (!active) { clearEntry(); labelField.text = ""; if (labelField.activeFocus) releaseFocus() }

  // ---- The new alarm's time: up to four typed digits, HHMM from the right,
  //      or scroll the hours / minutes. Untyped, it offers 07:00.
  property string entry: ""
  readonly property string digits: entry === "" ? "0700" : ("0000" + entry).slice(-4)
  readonly property int entryHour: parseInt(digits.slice(0, 2), 10)
  readonly property int entryMinute: parseInt(digits.slice(2, 4), 10)
  readonly property bool entryValid: entryHour < 24 && entryMinute < 60

  function pad(n) { return n < 10 ? "0" + n : String(n) }
  function typeDigit(d) { if (!ringing && entry.length < 4 && !(entry === "" && d === "0")) entry += d }
  function backspace() { entry = entry.slice(0, -1) }
  function clearEntry() { entry = "" }
  function adjust(field, delta) {
    var h = Math.min(23, entryHour), m = Math.min(59, entryMinute)
    if (field === 0) h = (h + delta + 24) % 24
    else m = (m + delta + 60) % 60
    entry = pad(h) + pad(m)
  }

  function addAlarm() {
    if (!alarms || full || !entryValid) return
    alarms.add(entryHour, entryMinute, labelField.text.trim())
    clearEntry()
    labelField.text = ""
    if (labelField.activeFocus) releaseFocus()
  }

  // ---- "Next: Tue 07:00 · in 9 h 12 min", refreshed while the page shows.
  property real nowMs: Date.now()
  Timer {
    interval: 15000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  function inText(ms) {
    var mins = Math.max(1, Math.round(ms / 60000))
    var h = Math.floor(mins / 60), m = mins % 60
    return "in " + (h ? h + " h" + (m ? " " + m + " min" : "") : m + " min")
  }

  readonly property string nextText: {
    if (!alarms) return ""
    var n = alarms.nextAlarm(nowMs)
    if (!n) return list.length ? "No alarms on" : ""
    var when = new Date(n.at), today = new Date(nowMs)
    var day = when.toDateString() === today.toDateString() ? "" : Qt.formatDate(when, "ddd") + " "
    return "Next: " + day + Qt.formatTime(when, "HH:mm") + " · " + inText(n.at - nowMs)
  }

  readonly property real contentWidth: Math.round(unit * 0.84)
  readonly property real rowHeight: Math.round(unit * 0.118)

  // ---- Top: the add row, or Snooze / Stop while ringing.
  Item {
    id: top
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(root.height * 0.04)
    width: root.contentWidth
    height: Math.max(labelField.height, entryRow.height)
    visible: !root.ringing

    // The time, a character at a time so each field can be scrolled, and so
    // the untyped digits sit back in the muted colour (as on the timer).
    Row {
      id: entryRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      property real wheel: 0

      Repeater {
        model: 5
        Text {
          required property int index
          readonly property bool colon: index === 2
          readonly property int field: index < 2 ? 0 : 1
          readonly property int digit: index < 2 ? index : index - 1
          readonly property bool typed: root.entry !== "" && digit >= 4 - root.entry.length
          textFormat: Text.PlainText
          text: colon ? ":" : root.digits.charAt(digit)
          color: !root.entryValid ? Color.urgent : (colon || typed ? root.ink : root.muted)
          font.family: root.fontFamily
          font.pixelSize: Math.round(root.unit * 0.068)
          font.weight: Font.Light

          MouseArea {
            anchors.fill: parent
            enabled: !parent.colon
            onClicked: root.releaseFocus()          // digits go to the time again
            onWheel: function(event) {
              if (Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)) { event.accepted = false; return }
              var dy = event.inverted ? -event.angleDelta.y : event.angleDelta.y
              entryRow.wheel += dy
              while (Math.abs(entryRow.wheel) >= 120) {
                root.adjust(parent.field, entryRow.wheel > 0 ? 1 : -1)
                entryRow.wheel -= entryRow.wheel > 0 ? 120 : -120
              }
            }
          }
        }
      }
    }

    TextField {
      id: labelField
      anchors.left: entryRow.right
      anchors.leftMargin: Style.space(12)
      anchors.right: addButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      enabled: !root.full
      placeholderText: root.full ? "Remove one to add more" : "Label"
      foreground: root.ink
      font.family: root.fontFamily
      maximumLength: 40
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.addAlarm(); event.accepted = true }
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          if (event.key === Qt.Key_Escape && labelField.text !== "") labelField.text = ""
          else root.releaseFocus()
          event.accepted = true
        }
      }
    }

    Rectangle {
      id: addButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: labelField.height
      height: width
      radius: width / 2
      readonly property bool ready: !root.full && root.entryValid
      opacity: ready ? 1 : 0.4
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, addArea.containsMouse && ready ? 0.28 : 0.18)
      antialiasing: true

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "+"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Math.round(parent.height * 0.62)
      }

      MouseArea {
        id: addArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: parent.ready
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addAlarm()
      }
    }
  }

  // Ringing: which alarm, and the stopwatch/timer's round buttons.
  Item {
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(root.height * 0.02)
    width: root.contentWidth
    height: snoozeButton.height
    visible: root.ringing

    RoundButton {
      id: snoozeButton
      anchors.left: parent.left
      unit: root.unit
      fontFamily: root.fontFamily
      tint: root.ink
      label: "Snooze"
      onClicked: if (root.alarms) root.alarms.snooze()
    }

    Column {
      anchors.centerIn: parent
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.alarms && root.alarms.ringingAlarm ? root.alarms.timeText(root.alarms.ringingAlarm) : ""
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Math.round(root.unit * 0.068)
        font.weight: Font.Light
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.alarms && root.alarms.ringingAlarm ? (root.alarms.ringingAlarm.label || "Alarm") : ""
        color: root.soft
        font.family: root.fontFamily
        font.pixelSize: Math.round(root.unit * 0.032)
      }
    }

    RoundButton {
      anchors.right: parent.right
      unit: root.unit
      fontFamily: root.fontFamily
      tint: Color.urgent
      label: "Stop"
      onClicked: if (root.alarms) root.alarms.stop()
    }
  }

  Text {
    id: nextLine
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.ringing ? Math.round(root.height * 0.02) + snoozeButton.height + Style.space(6) : top.y + top.height + Style.space(6)
    textFormat: Text.PlainText
    text: root.nextText
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.unit * 0.032)
  }

  // ---- The alarms.
  Column {
    id: rows
    anchors.top: nextLine.bottom
    anchors.topMargin: Math.round(root.height * 0.03)
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.contentWidth

    Repeater {
      model: root.list

      Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool on: modelData.enabled
        readonly property bool once: !modelData.days.some(function(d) { return d })
        width: rows.width
        height: root.rowHeight

        Rectangle {
          anchors.top: parent.top
          width: parent.width
          height: 1
          color: root.muted
        }

        // Time over label + days, centred in the row as on the world clock.
        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Style.space(1)

        Text {
          id: timeText
          textFormat: Text.PlainText
          text: root.alarms ? root.alarms.timeText(row.modelData) : ""
          color: row.on ? root.ink : root.muted
          font.family: root.fontFamily
          font.pixelSize: Math.round(root.unit * 0.058)
          font.weight: Font.Light
        }

        // Label, then the repeat days: click a letter to set or clear it.
        Row {
          spacing: Style.space(4)

          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            text: row.modelData.label ? row.modelData.label + (row.once ? " · once ·" : " ·") : (row.once ? "Once ·" : "")
            color: root.soft
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.unit * 0.029)
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.contentWidth * 0.4)
          }

          Repeater {
            model: 7
            Text {
              required property int index
              readonly property bool set: row.modelData.days[index]
              textFormat: Text.PlainText
              text: root.alarms ? root.alarms.dayLetters[index] : ""
              color: set ? (row.on ? root.ink : root.soft) : root.muted
              font.family: root.fontFamily
              font.pixelSize: Math.round(root.unit * 0.029)
              font.weight: set ? Font.Bold : Font.Normal

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(2)
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.alarms) root.alarms.toggleDay(row.modelData.id, parent.index)
              }
            }
          }
        }

        }

        // ✕ in a small grey ring, shown while the row is hovered (as on the
        // world clock).
        Rectangle {
          anchors.right: toggle.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(root.unit * 0.05)
          height: width
          radius: width / 2
          color: removeArea.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.12) : "transparent"
          border.width: 1
          border.color: removeArea.containsMouse ? Color.urgent : root.muted
          antialiasing: true
          opacity: rowHover.hovered ? 1 : 0

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "✕"
            color: removeArea.containsMouse ? Color.urgent : root.soft
            font.family: root.fontFamily
            font.pixelSize: Math.round(parent.width * 0.5)
          }

          MouseArea {
            id: removeArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            enabled: rowHover.hovered
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.alarms) root.alarms.remove(row.modelData.id)
          }
        }

        ToggleSwitch {
          id: toggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: row.on
          cursorRing: false
          foreground: root.ink
          accent: Color.accent
          onToggled: if (root.alarms) root.alarms.setEnabled(row.modelData.id, !row.on)
        }

        HoverHandler { id: rowHover }
      }
    }
  }

  Text {
    visible: root.list.length === 0 && !root.ringing
    anchors.top: rows.top
    anchors.topMargin: Math.round(root.height * 0.08)
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.PlainText
    text: "Type a time, then + to add an alarm"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.unit * 0.032)
  }
}
