import QtQuick
import qs.Commons

// The countdown timer page. Laid out like the stopwatch so the two feel like
// one app: the time at the top, Reset and Start/Pause in the middle, and the
// last five timers below as one-click presets. All the state lives in
// CountdownTimer.qml; this draws it and handles setting a new time.
//
// Setting the time, in place of Apple's barrels: type the digits and they fill
// in from the right, microwave style (1-5-0-0 -> 00:15:00; Backspace takes one
// back), or scroll over the hours, minutes or seconds to step that field.
Item {
  id: root

  property var timer: null       // CountdownTimer.qml
  property bool active: false    // popup open and this page showing
  property color ink: "white"
  property string fontFamily: "monospace"

  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.28)
  readonly property real unit: width
  readonly property string status: timer ? timer.status : "idle"
  readonly property bool idle: status === "idle"

  // ---- The entry: up to six typed digits, HHMMSS read from the right. When
  //      it was filled in from the last timer rather than typed (`prefilled`),
  //      the first digit typed starts afresh instead of shifting it along.
  property string entry: ""
  property bool prefilled: false

  function pad2(n) { return n < 10 ? "0" + n : String(n) }
  function entryDigits() { return ("000000" + entry).slice(-6) }
  function entryFields() {
    var d = entryDigits()
    return [parseInt(d.slice(0, 2), 10), parseInt(d.slice(2, 4), 10), parseInt(d.slice(4, 6), 10)]
  }
  // Minutes or seconds typed past 59 (90 s) are simply added up, as a microwave does.
  function entryMs() {
    var f = entryFields()
    return (f[0] * 3600 + f[1] * 60 + f[2]) * 1000
  }
  function digitsFor(ms) {
    var t = Math.round(ms / 1000)
    return pad2(Math.min(99, Math.floor(t / 3600))) + pad2(Math.floor(t / 60) % 60) + pad2(t % 60)
  }
  function prefillFromLast() {
    root.entry = root.timer && root.timer.duration > 0 ? digitsFor(root.timer.duration) : ""
    root.prefilled = root.entry !== ""
  }

  function typeDigit(d) {
    if (!idle) return
    if (prefilled) { entry = ""; prefilled = false }
    if (entry === "" && d === "0") return
    if (entry.length < 6) entry += d
  }

  function backspace() {
    if (!idle) return
    if (prefilled) { entry = ""; prefilled = false; return }
    entry = entry.slice(0, -1)
  }

  function clearEntry() {
    if (!idle) return
    entry = ""
    prefilled = false
  }

  // Scroll over a field: step it by one, wrapping (hours 0-99, the rest 0-59).
  function adjust(field, delta) {
    if (!idle) return
    var f = entryFields()
    var span = field === 0 ? 100 : 60
    f[1] = Math.min(59, f[1]); f[2] = Math.min(59, f[2])
    f[field] = (f[field] + delta + span) % span
    entry = pad2(f[0]) + pad2(f[1]) + pad2(f[2])
    prefilled = false
  }

  // The right button: Start, Pause, Resume.
  function primary() {
    if (!timer) return
    if (status === "running") timer.pause()
    else if (status === "paused") timer.resume()
    else if (entryMs() > 0) timer.start(entryMs())
  }

  // The left button: Reset -- back to the last timer's time, ready to run
  // again, or clear what's been typed.
  function secondary() {
    if (!timer) return
    if (!idle) timer.reset()
    else if (prefilled) clearEntry()
    else prefillFromLast()
  }

  // Press and hold Reset: a clean slate -- stops any timer, clears the entry,
  // and forgets the recent timers, as Reset clears the stopwatch's laps.
  function clearAll() {
    if (!timer) return
    timer.reset()
    timer.clearRecents()
    entry = ""
    prefilled = false
  }

  function startRecent(ms) {
    if (timer && idle) timer.start(ms)
  }

  Component.onCompleted: prefillFromLast()
  Connections {
    target: root.timer
    // Load the last timer's time back in whenever one ends or is reset.
    function onStatusChanged() { if (root.timer.status === "idle") root.prefillFromLast() }
    function onDurationChanged() { if (root.timer.status === "idle" && root.entry === "") root.prefillFromLast() }
  }

  // Five repaints a second while it's on screen and counting down.
  property real nowMs: Date.now()
  Timer {
    interval: 200
    repeat: true
    running: root.active && root.status === "running"
    onTriggered: root.nowMs = Date.now()
  }
  onActiveChanged: nowMs = Date.now()

  readonly property string shown: idle
    ? entryDigits().slice(0, 2) + ":" + entryDigits().slice(2, 4) + ":" + entryDigits().slice(4, 6)
    : (timer ? timer.format(timer.remainingAt(nowMs)) : "00:00:00")

  // ---- The time. Drawn a character at a time so each field can be scrolled,
  //      and so the digits not yet typed can sit back in the muted colour.
  Row {
    id: display
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(root.height * 0.07)

    property real wheel: 0

    Repeater {
      model: root.shown.length

      Text {
        required property int index
        readonly property bool colon: index === 2 || index === 5
        readonly property int field: Math.floor(index / 3)
        readonly property int digit: index - Math.floor(index / 3)
        readonly property bool typed: !root.idle || digit >= 6 - root.entry.length

        textFormat: Text.PlainText
        text: root.shown.charAt(index)
        color: colon || typed ? root.ink : root.muted
        font.family: root.fontFamily
        font.pixelSize: Math.round(root.unit * 0.15)
        font.weight: Font.Light

        MouseArea {
          anchors.fill: parent
          enabled: !parent.colon && root.idle
          acceptedButtons: Qt.NoButton
          onWheel: function(event) {
            // Let a sideways swipe through to the page switcher.
            if (Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)) { event.accepted = false; return }
            var dy = event.inverted ? -event.angleDelta.y : event.angleDelta.y
            display.wheel += dy
            // One step per mouse-wheel notch (120); a touchpad gets there in
            // several smaller deltas.
            while (Math.abs(display.wheel) >= 120) {
              root.adjust(parent.field, display.wheel > 0 ? 1 : -1)
              display.wheel -= display.wheel > 0 ? 120 : -120
            }
          }
        }
      }
    }
  }

  // Under the time: how to set it, when it'll finish, or that it's paused.
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: display.bottom
    textFormat: Text.PlainText
    text: root.status === "running" && root.timer
      ? "Ends " + Qt.formatTime(new Date(root.timer.endsAt), "HH:mm")
      : root.status === "paused" ? "Paused"
      : "Type or scroll to set"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.unit * 0.032)
  }

  // ---- Reset and Start/Pause, in the same place as the stopwatch's.
  Item {
    id: buttons
    y: Math.round(root.height * 0.35)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.round(root.unit * 0.74)
    height: resetButton.height

    RoundButton {
      id: resetButton
      anchors.left: parent.left
      unit: root.unit
      fontFamily: root.fontFamily
      tint: root.ink
      label: "Reset"
      enabled: !root.idle || root.entry !== "" || (root.timer !== null && root.timer.recents.length > 0)
      onClicked: root.secondary()
      onHeld: root.clearAll()
    }

    RoundButton {
      anchors.right: parent.right
      unit: root.unit
      fontFamily: root.fontFamily
      label: root.status === "running" ? "Pause" : root.status === "paused" ? "Resume" : "Start"
      tint: root.status === "running" ? Color.urgent : Color.accent
      enabled: !root.idle || root.entryMs() > 0
      onClicked: root.primary()
    }
  }

  // ---- Recent timers: one click starts one again. Greyed out while a timer
  //      is already going, since there's only the one.
  readonly property real rowHeight: Math.round(unit * 0.07)

  Item {
    id: recentArea
    anchors.top: buttons.bottom
    anchors.topMargin: Math.round(root.height * 0.05)
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: buttons.width

    readonly property int maxRows: Math.max(0, Math.min(5, Math.floor(height / root.rowHeight)))

    Column {
      width: parent.width
      opacity: root.idle ? 1 : 0.4

      Repeater {
        model: root.timer ? root.timer.recents.slice(0, recentArea.maxRows) : []

        Item {
          required property var modelData
          width: recentArea.width
          height: root.rowHeight

          Rectangle {
            anchors.fill: parent
            color: root.ink
            opacity: recentMouse.containsMouse && root.idle ? 0.06 : 0
            radius: Style.space(4)
          }

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
            text: root.timer ? root.timer.describe(modelData) : ""
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.unit * 0.036)
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.timer ? root.timer.format(modelData) : ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.unit * 0.036)
          }

          MouseArea {
            id: recentMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.idle
            cursorShape: Qt.PointingHandCursor
            onClicked: root.startRecent(parent.modelData)
          }
        }
      }
    }
  }
}
