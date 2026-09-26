import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A small card under the bar's time while the stopwatch or timer is running:
// just the time counting up or down, in the bar clock's own font and size.
// The stopwatch wins if both are running. Hidden while this widget's own
// popups are open (they show it already); clicking it opens the clock card on
// that page.
//
// Built on PopupWindow directly rather than the stock PopupCard (whose look
// and placement it copies) because PopupCard claims the bar's single popout
// slot: a readout that stays up while a timer runs would otherwise close, and
// be closed by, every other panel on the bar.
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var stopwatch: null     // Stopwatch.qml
  property var timer: null         // CountdownTimer.qml
  property bool suppressed: false  // one of the widget's popups is open
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  // The popup text colour, not the bar label's: the card sits on the popup
  // background, where the bar's (chosen to read against the wallpaper) can
  // vanish -- light on light.
  property color foreground: Color.popups.text

  signal activated(string page)

  readonly property string mode: stopwatch && stopwatch.running ? "stopwatch"
    : timer && timer.status === "running" ? "timer" : ""
  readonly property bool shown: mode !== "" && !suppressed

  property real nowMs: Date.now()
  onModeChanged: nowMs = Date.now()
  onShownChanged: nowMs = Date.now()

  // Every frame for the stopwatch's hundredths, five times a second for the
  // timer, and not at all when neither is running.
  FrameAnimation {
    running: root.shown && root.mode === "stopwatch"
    onTriggered: root.nowMs = Date.now()
  }
  Timer {
    interval: 200
    repeat: true
    running: root.shown && root.mode === "timer"
    onTriggered: root.nowMs = Date.now()
  }

  readonly property string liveText: mode === "stopwatch" ? stopwatch.format(stopwatch.elapsedAt(nowMs))
    : mode === "timer" ? timer.format(timer.remainingAt(nowMs))
    : ""
  // Holds the last reading once nothing's running, so the card fades out
  // showing it rather than blanking and shrinking mid-fade.
  property string reading: ""
  onLiveTextChanged: if (liveText !== "") reading = liveText

  // Sized from a same-length run of zeros, not the live text: the bar font's
  // digits are all one width, so the card never twitches as it counts, and
  // stopwatch and timer (both eight characters) come out the same size.
  TextMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    text: root.reading.replace(/[0-9]/g, "0")
  }

  readonly property int margin: Style.gapsOut
  readonly property int padX: Style.space(10)
  readonly property int padY: Style.space(5)
  readonly property var borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))

  visible: shown || card.opacity > 0
  color: "transparent"
  implicitWidth: Math.ceil(metrics.advanceWidth) + padX * 2 + Border.left(borderSpec) + Border.right(borderSpec)
  implicitHeight: Math.ceil(metrics.height) + padY * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  // Placement as PopupCard does it: under the anchor on a top bar, above it
  // on a bottom bar, beside it on a side bar, and kept on screen.
  anchor {
    id: popupAnchor
    window: root.anchorItem ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return
      var target = root.anchorItem
      var window = target.QsWindow.window
      if (!window) return

      var w = root.implicitWidth, h = root.implicitHeight
      var localX = target.width / 2 - w / 2
      var localY = target.height + root.margin
      if (root.bar.position === "bottom") {
        localY = -h - root.margin
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin
        localY = target.height / 2 - h / 2
      } else if (root.bar.position === "right") {
        localX = -w - root.margin
        localY = target.height / 2 - h / 2
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)
      if (root.bar.position === "top" || root.bar.position === "bottom")
        point.x = Math.max(root.margin, Math.min(point.x, window.width - w - root.margin))
      else
        point.y = Math.max(root.margin, Math.min(point.y, window.height - h - root.margin))

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: 0
    radius: Style.cornerRadius
    opacity: root.shown ? 1 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.reading
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.activated(root.mode)
    }
  }
}
