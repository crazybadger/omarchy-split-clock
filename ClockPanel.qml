import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The analogue clock popup: a square card with a bare face -- hour and
// minute hands in the bar's foreground, a slim accent-coloured second hand
// that sweeps rather than ticks, and a small 24-hour digital time. No numerals, no
// chrome; sized to sit where the calendar does.
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

  FrameAnimation {
    running: root.opened && root.secondHandMode === "sweep"
    onTriggered: root.now = new Date()
  }

  Timer {
    interval: root.secondHandMode === "tick" ? 1000 : 60000
    repeat: true
    running: root.opened && root.secondHandMode !== "sweep"
    onTriggered: root.now = new Date()
  }

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

      Item {
        id: face
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width

        readonly property real r: width / 2
        readonly property color ink: root.contentForeground
        readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.28)

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
  }
}
