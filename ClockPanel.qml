import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The analogue clock popup: a square card with a bare face -- hour and
// minute hands in the bar's foreground, a slim accent-coloured second hand
// that sweeps rather than ticks, and a small 24-hour digital time. No numerals, no
// chrome; sized to sit where the calendar does.
//
// The card has three pages -- clock, stopwatch, timer -- after Apple's Clock
// app, switched by the dots along the bottom, Left/Right (or h/l), or a
// horizontal two-finger swipe. Tab still hands over to the calendar. The card
// keeps the same size on every page so switching never moves the popup.
//
// This panel is deliberately its own popout identity (no hostWidget), so the
// bar hands over between the calendar and this face with its normal
// cross-fade. BarWidget.qml injects `bar`, `settings`, `anchorItem` and
// `sibling` (the widget, so Tab can flip to the calendar).
//
// Settings (shell.json, on the widget entry):
//   secondHand: "sweep" (default) | "tick" | "off"
Panel {
  id: root
  moduleName: "crazybadger.split-clock"
  manageIpc: false

  property var anchorItem: null
  property var sibling: null

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string secondHandMode: {
    var v = String(setting("secondHand", "sweep")).toLowerCase()
    return v === "tick" || v === "off" ? v : "sweep"
  }

  // The time on the face. Refreshed every frame while the panel is open
  // (sweep), once a second (tick), or once a minute (off).
  property date now: new Date()
  readonly property real seconds: now.getSeconds() + (secondHandMode === "sweep" ? now.getMilliseconds() / 1000 : 0)
  readonly property real minutes: now.getMinutes() + (secondHandMode === "off" ? 0 : seconds / 60)
  readonly property real hours: (now.getHours() % 12) + minutes / 60

  function refresh() { root.now = new Date() }

  // Kept across open/close (the panel is hidden, not destroyed), so the popup
  // comes back on the page you left it on, as Apple's app does.
  readonly property var pageNames: ["clock", "stopwatch", "timer"]
  property int page: 0

  function showPage(index) {
    root.page = Math.max(0, Math.min(root.pageNames.length - 1, index))
  }

  function showPageNamed(name) {
    var i = root.pageNames.indexOf(String(name).toLowerCase())
    if (i >= 0) root.showPage(i)
  }

  readonly property color ink: root.contentForeground
  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.28)

  // Owned by the panel, not the page, so they run with the popup closed.
  // Exposed for the bar widget's running readout.
  readonly property var stopwatchState: stopwatch
  readonly property var timerState: countdown
  Stopwatch { id: stopwatch }
  CountdownTimer {
    id: countdown
    onExpired: root.timerExpired()
  }

  // Every monitor's bar has its own copy of this widget, all following the
  // same timer through the shared state file. Only the first copy the bar
  // lists raises the alert and finishes the timer (the rest see the file
  // change), so it goes off once, not once per screen -- and if that
  // monitor goes away, the next copy becomes the first.
  function ownsAlerts() {
    var copies = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    return copies.length === 0 || copies[0] === root.sibling
  }

  function timerExpired() {
    if (!ownsAlerts()) return
    var duration = countdown.duration
    var endedAt = countdown.endsAt
    countdown.finish()

    // A timer that ran out while the laptop was asleep or off says when.
    var detail = countdown.describe(duration)
    if (Date.now() - endedAt > 60000) detail += " (finished at " + Qt.formatTime(new Date(endedAt), "HH:mm") + ")"

    Util.execArgv(["omarchy-notification-send", "-g", "󰔛", "-u", "critical", "Timer done", detail])
    Util.execArgv(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  // Only while the clock page is the one showing: no per-frame work for a
  // face that's slid out of view.
  FrameAnimation {
    running: root.opened && root.page === 0 && root.secondHandMode === "sweep"
    onTriggered: root.now = new Date()
  }

  Timer {
    interval: root.secondHandMode === "tick" ? 1000 : 60000
    repeat: true
    running: root.opened && root.page === 0 && root.secondHandMode !== "sweep"
    onTriggered: root.now = new Date()
  }

  onPageChanged: if (root.page === 0) root.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // Square, and as tall as the calendar card so the two popups feel like
    // a pair. Capped by whichever screen dimension is tighter.
    readonly property int side: Math.min(fittedContentWidth(Style.space(440)), fittedContentHeight(Style.space(440)))
    contentWidth: side
    contentHeight: side

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { if (root.sibling) root.sibling.open() }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.showPage(root.page + dx) }

      // Stopwatch and timer pages share one scheme: Space is the right-hand
      // button (Start/Stop, Start/Pause), Enter the left (Lap/Reset, Reset).
      // PanelKeyCatcher emits returnRequested *then* activateRequested for
      // Enter but only activateRequested for Space, so Enter marks the
      // activate that follows it as already handled.
      property bool enterHandled: false
      onReturnRequested: {
        enterHandled = true
        if (root.page === 1) stopwatch.lapOrReset()
        else if (root.page === 2) timerPage.secondary()
      }
      onActivateRequested: {
        if (enterHandled) { enterHandled = false; return }
        if (root.page === 1) stopwatch.toggle()
        else if (root.page === 2) timerPage.primary()
      }

      // Timer page: digits set the time, Backspace takes one back, x clears.
      onTextKey: function(t) {
        if (root.page !== 2) return
        if (t >= "0" && t <= "9") timerPage.typeDigit(t)
        else if (t === "\b") timerPage.backspace()
      }
      onDeleteRequested: if (root.page === 2) timerPage.clearEntry()

      // The viewport: one page wide, the three pages side by side in `strip`,
      // which slides to the current one.
      Item {
        id: pager
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: dots.top
        clip: true

        // Two-finger horizontal swipe. Accumulated so a single flick moves one
        // page, then locked until the fingers lift (no events for a moment),
        // so one long swipe can't skip across all three.
        property real swipe: 0
        property bool swipeLocked: false

        Timer {
          id: swipeSettle
          interval: 220
          onTriggered: { pager.swipe = 0; pager.swipeLocked = false }
        }

        WheelHandler {
          acceptedDevices: PointerDevice.TouchPad
          orientation: Qt.Horizontal
          onWheel: function(event) {
            swipeSettle.restart()
            if (pager.swipeLocked) return
            // With natural scrolling the delta arrives inverted; normalise so
            // fingers moving left always means "next page".
            var dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 2
            if (event.inverted) dx = -dx
            pager.swipe += dx
            if (Math.abs(pager.swipe) > 60) {
              root.showPage(root.page + (pager.swipe < 0 ? 1 : -1))
              pager.swipeLocked = true
            }
          }
        }

        Row {
          id: strip
          height: pager.height
          x: -root.page * pager.width

          Behavior on x {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
          }

          // ---- Page 1: the clock face.
          Item {
            width: pager.width
            height: pager.height

            Item {
              id: face
              anchors.centerIn: parent
              width: Math.min(parent.width, parent.height)
              height: width

              readonly property real r: width / 2
              readonly property color ink: root.ink
              readonly property color muted: root.muted

              // Outer ring.
              Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: face.muted
              }

              // 60 ticks: the hours are solid and a little longer, the minutes a
              // faint dot's worth.
              Repeater {
                model: 60

                Item {
                  required property int index
                  readonly property bool hour: index % 5 === 0
                  anchors.fill: parent
                  rotation: index * 6

                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: face.r * 0.08
                    width: parent.hour ? Math.max(2, face.r * 0.024) : Math.max(1, face.r * 0.01)
                    height: parent.hour ? face.r * 0.11 : face.r * 0.035
                    radius: width / 2
                    color: parent.hour ? face.ink : face.muted
                    antialiasing: true
                  }
                }
              }

              // Digital 24-hour time, low on the face so the hands pass over it.
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: face.r * 1.5
                textFormat: Text.PlainText
                text: Qt.formatTime(root.now, "HH:mm")
                color: Qt.rgba(face.ink.r, face.ink.g, face.ink.b, 0.55)
                font.family: root.contentFontFamily
                font.pixelSize: Math.max(Style.font.bodySmall, Math.round(face.r * 0.085))
                font.letterSpacing: 1.5
              }

              // Hour hand.
              Item {
                anchors.fill: parent
                rotation: root.hours * 30
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: face.r - face.r * 0.5
                  width: Math.max(4, face.r * 0.05)
                  height: face.r * 0.5 + face.r * 0.06
                  radius: width / 2
                  color: face.ink
                  antialiasing: true
                }
              }

              // Minute hand.
              Item {
                anchors.fill: parent
                rotation: root.minutes * 6
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: face.r - face.r * 0.78
                  width: Math.max(3, face.r * 0.035)
                  height: face.r * 0.78 + face.r * 0.06
                  radius: width / 2
                  color: face.ink
                  antialiasing: true
                }
              }

              // Second hand, with a short counterweight tail.
              Item {
                visible: root.secondHandMode !== "off"
                anchors.fill: parent
                rotation: root.seconds * 6
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: face.r - face.r * 0.88
                  width: Math.max(1.5, face.r * 0.014)
                  height: face.r * 0.88 + face.r * 0.2
                  radius: width / 2
                  color: Color.accent
                  antialiasing: true
                }
              }

              // Centre cap.
              Rectangle {
                anchors.centerIn: parent
                width: Math.max(9, face.r * 0.075)
                height: width
                radius: width / 2
                color: root.secondHandMode === "off" ? face.ink : Color.accent
              }
            }
          }

          // ---- Page 2: stopwatch.
          StopwatchPage {
            width: pager.width
            height: pager.height
            sw: stopwatch
            active: root.opened && root.page === 1
            ink: root.ink
            fontFamily: root.contentFontFamily
          }

          // ---- Page 3: countdown timer.
          TimerPage {
            id: timerPage
            width: pager.width
            height: pager.height
            timer: countdown
            active: root.opened && root.page === 2
            ink: root.ink
            fontFamily: root.contentFontFamily
          }
        }
      }

      // The page dots, after Apple's page control: the current page solid,
      // the others faint. Each has a generous click target around it.
      Row {
        id: dots
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: Style.space(22)
        spacing: 0

        Repeater {
          model: root.pageNames.length

          Item {
            required property int index
            width: Style.space(22)
            height: dots.height

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(7)
              height: width
              radius: width / 2
              color: root.ink
              opacity: root.page === parent.index ? 0.9 : (dotArea.containsMouse ? 0.5 : 0.28)
              antialiasing: true
              Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            MouseArea {
              id: dotArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showPage(parent.index)
            }
          }
        }
      }
    }
  }
}
