import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The analogue clock popup: a square card with a bare face -- hour and
// minute hands in the bar's foreground, a slim accent-coloured second hand
// that sweeps rather than ticks, and a small 24-hour digital time. No numerals, no
// chrome; sized to sit where the calendar does.
//
// The card has five pages -- world, clock, stopwatch, timer, alarms -- after Apple's Clock
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

  // The world clock sits left of the face, but the card always opens on the
  // face -- or on the stopwatch or timer while one is running (the stopwatch
  // first, as in the bar's readout).
  readonly property var pageNames: ["world", "clock", "stopwatch", "timer", "alarms"]
  readonly property string pageName: pageNames[page]
  readonly property var pageIcons: ["󰖟", "󰅐", "󰔛", "󰔟", "󰀠"]
  readonly property var pageTitles: ["World clock", "Clock", "Stopwatch", "Timer", "Alarms"]
  property int page: 1

  function defaultPage() {
    if (alarmState.ringing) return "alarms"
    if (stopwatch.running) return "stopwatch"
    if (countdown.status === "running") return "timer"
    return "clock"
  }

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
  Stopwatch {
    id: stopwatch
    onChanged: root.persist("stopwatch", snapshot())
  }
  CountdownTimer {
    id: countdown
    onExpired: root.timerExpired()
    onChanged: root.persist("timer", snapshot())
  }
  WorldClocks {
    id: world
    onChanged: root.persist("world", snapshot())
  }
  Alarms {
    id: alarmState
    onChanged: root.persist("alarms", snapshot())
    onDue: function(alarm, occurrence, snoozed) { root.alarmDue(alarm, occurrence, snoozed) }
  }

  // ---- Saving. The helper does the disk work (`store`) and the searching
  //      (`net`, so a slow search never holds up a save). Each state is read
  //      once at start. A change is saved by the copy it happened on, which
  //      also hands it straight to the other monitors' copies.
  Helper { id: store }
  Helper { id: net }

  function stateFor(name) {
    return name === "stopwatch" ? stopwatch : name === "timer" ? countdown : name === "world" ? world
      : name === "alarms" ? alarmState : null
  }

  Component.onCompleted: {
    ["stopwatch", "timer", "world", "alarms"].forEach(function(name) {
      store.run(["read", name], function(text) {
        if (!text) return
        var s = null
        try { s = JSON.parse(text) } catch (e) { return }
        root.stateFor(name).load(s)
      })
    })
  }

  function persist(name, snap) {
    store.save(name, snap)
    var copies = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    for (var i = 0; i < copies.length; i++) {
      if (copies[i] !== root.sibling && typeof copies[i].receiveState === "function")
        copies[i].receiveState(name, snap)
    }
  }

  // From another monitor's copy (via BarWidget.receiveState).
  function receiveState(name, snap) {
    var target = stateFor(name)
    if (target) target.load(JSON.parse(JSON.stringify(snap)))
  }

  // Every monitor's bar has its own copy of this widget, all following the
  // same timer (see `persist`). Only the first copy the bar lists raises the
  // alert and finishes the timer (which hands the finish to the rest), so it
  // goes off once, not once per screen -- and if that
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

    // Repeating: straight into the next round, with the alarm and a notice
    // that closes itself after about as long as the alarm plays (low urgency
    // takes a timeout; the one-off "Timer done" below stays until dismissed).
    if (countdown.repeat) {
      var done = countdown.round
      if (countdown.nextRound()) {
        Util.execArgv(["omarchy-notification-send", "-g", "󰑖", "-u", "low", "-t", "6000",
          "Round " + done + " done", countdown.describe(duration) + " · round " + countdown.round + " running"])
        root.playAlarm()
        return
      }
    }

    countdown.finish()

    // A timer that ran out while the laptop was asleep or off says when.
    var detail = countdown.describe(duration)
    if (Date.now() - endedAt > 60000) detail += " (finished at " + countdown.clockTime(endedAt, Date.now()) + ")"

    Util.execArgv(["omarchy-notification-send", "-g", "󰔛", "-u", "critical", "Timer done", detail])
    root.playAlarm()
  }

  // An alarm fell due (on every copy; the one that owns alerts acts). On time,
  // it rings: the alarm sound repeating for up to a minute and a notification
  // that stays, which opens this page. Found late -- it fell due while the
  // laptop slept -- it only says so.
  function alarmDue(alarm, occurrence, snoozed) {
    if (!ownsAlerts()) return
    var label = alarm.label || "Alarm"
    var time = alarmState.timeText(alarm)
    var open = ["--exec", "omarchy-shell", root.moduleName, "openPage", "alarms"]
    if (Date.now() - occurrence > 60000) {
      alarmState.markMissed(alarm.id, occurrence)
      Util.execArgv(["omarchy-notification-send", "-g", "󰀠", "-u", "critical", "Missed alarm " + time,
        label + " (the laptop was asleep)"].concat(open))
      return
    }
    alarmState.ring(alarm.id, occurrence)
    Util.execArgv(["omarchy-notification-send", "-g", "󰀠", "-u", "critical",
      (snoozed ? "Snoozed alarm " : "Alarm ") + time, label].concat(open))
    alarmRings = 0
    alarmSound.restart()
  }

  property int alarmRings: 0
  Timer {
    id: alarmSound
    interval: 7000              // the sound is ~6 s
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!alarmState.ringing || ++root.alarmRings > 9) { stop(); return }
      root.playAlarm()
    }
  }

  function playAlarm() {
    // One at a time: the sound is ~6 s, so short repeating rounds would
    // otherwise stack up overlapping players.
    if (!alarm.running) alarm.running = true
  }

  Process {
    id: alarm
    // The spec's alarm sound from whichever sound theme has it (freedesktop's
    // is the usual one, but it's an optional package). Fixed paths only --
    // nothing from outside the plugin reaches the shell.
    command: ["sh", "-c",
      "for f in /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga /usr/share/sounds/*/stereo/alarm-clock-elapsed.*; do " +
      "[ -e \"$f\" ] && exec timeout 15 pw-play \"$f\"; done"]
  }


  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // `pageName` when asked for a particular page (the readout, IPC openPage).
  function open(pageName) {
    showPageNamed(pageName && pageNames.indexOf(String(pageName).toLowerCase()) >= 0 ? pageName : defaultPage())
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
    running: root.opened && root.pageName === "clock" && root.secondHandMode === "sweep"
    onTriggered: root.now = new Date()
  }

  Timer {
    interval: root.secondHandMode === "tick" ? 1000 : 60000
    repeat: true
    running: root.opened && root.pageName === "clock" && root.secondHandMode !== "sweep"
    onTriggered: root.now = new Date()
  }

  onPageChanged: if (root.pageName === "clock") root.refresh()

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
      // The world page's search and the alarm label take the keys while focused.
      blocked: worldPage.searchFocused || alarmsPage.labelFocused
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
        if (root.pageName === "stopwatch") stopwatch.lapOrReset()
        else if (root.pageName === "timer") timerPage.secondary()
        else if (root.pageName === "alarms") alarmState.ringing ? alarmState.snooze() : alarmsPage.addAlarm()
      }
      onActivateRequested: {
        if (enterHandled) { enterHandled = false; return }
        if (root.pageName === "stopwatch") stopwatch.toggle()
        else if (root.pageName === "timer") timerPage.primary()
        else if (root.pageName === "alarms") alarmState.stop()
      }

      // Timer page: digits set the time, Backspace takes one back, x clears,
      // r turns repeat on or off.
      onTextKey: function(t) {
        if (root.pageName === "alarms") {
          if (t >= "0" && t <= "9") alarmsPage.typeDigit(t)
          else if (t === "\b") alarmsPage.backspace()
          return
        }
        if (root.pageName !== "timer") return
        if (t === "r" || t === "R") countdown.toggleRepeat()
        else if (t >= "0" && t <= "9") timerPage.typeDigit(t)
        else if (t === "\b") timerPage.backspace()
      }
      onDeleteRequested: {
        if (root.pageName === "timer") timerPage.clearEntry()
        else if (root.pageName === "alarms") alarmsPage.clearEntry()
      }

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

          // Slides between pages, but jumps when the card opens on its page.
          Behavior on x {
            enabled: root.opened
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
          }

          // ---- Page 1: world clock.
          WorldPage {
            id: worldPage
            width: pager.width
            height: pager.height
            clocks: world
            helper: net
            active: root.opened && root.pageName === "world"
            ink: root.ink
            fontFamily: root.contentFontFamily
            onReleaseFocus: keyCatcher.forceActiveFocus()
            onPageRequested: function(dx) { root.showPage(root.page + dx) }
          }

          // ---- Page 2: the clock face.
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

          // ---- Page 3: stopwatch.
          StopwatchPage {
            width: pager.width
            height: pager.height
            sw: stopwatch
            active: root.opened && root.pageName === "stopwatch"
            ink: root.ink
            fontFamily: root.contentFontFamily
          }

          // ---- Page 4: countdown timer.
          TimerPage {
            id: timerPage
            width: pager.width
            height: pager.height
            timer: countdown
            active: root.opened && root.pageName === "timer"
            ink: root.ink
            fontFamily: root.contentFontFamily
          }

          // ---- Page 5: alarms.
          AlarmsPage {
            id: alarmsPage
            width: pager.width
            height: pager.height
            alarms: alarmState
            active: root.opened && root.pageName === "alarms"
            ink: root.ink
            fontFamily: root.contentFontFamily
            onReleaseFocus: keyCatcher.forceActiveFocus()
          }
        }
      }

      // The page dots, after Apple's page control: the current page solid,
      // the others faint. Each has a generous click target around it.
      Row {
        id: dots
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: Style.space(26)
        spacing: Style.space(2)

        Repeater {
          model: root.pageNames.length

          Item {
            required property int index
            width: Style.space(30)
            height: dots.height

            // A small icon per page, lit like a page dot when it's the one
            // showing: globe, clock, stopwatch, hourglass, alarm clock.
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.pageIcons[parent.index]
              // The page showing is lit in the theme's accent, the rest muted.
              color: root.page === parent.index ? Color.accent : root.ink
              font.family: root.contentFontFamily
              font.pixelSize: Style.space(15)
              opacity: root.page === parent.index ? 1 : (dotArea.containsMouse ? 0.5 : 0.28)
              Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            MouseArea {
              id: dotArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showPage(parent.index)
            }

            PanelToolTip {
              visible: dotArea.containsMouse
              text: root.pageTitles[parent.index]
              fontFamily: root.contentFontFamily
            }
          }
        }
      }
    }
  }
}
