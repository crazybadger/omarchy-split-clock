import QtQuick

// The round, tinted button shared by the stopwatch and timer pages, after
// Apple's: a soft circle in the tint colour with the label in full tint.
Item {
  id: button

  property string label: ""
  property color tint: "white"
  property string fontFamily: "monospace"
  property real unit: 400   // the page width, which everything scales from
  signal clicked()

  width: Math.round(unit * 0.19)
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
    font.family: button.fontFamily
    font.pixelSize: Math.round(button.unit * 0.042)
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
