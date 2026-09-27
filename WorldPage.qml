import QtQuick
import qs.Commons
import qs.Ui

// The world clock page. A search field and + button at the top, the places
// below: the city on the left with its country and offset from GMT under it,
// the time there on the right. Hover a row for the ✕ that removes it. Six
// fit without scrolling, which is also the limit. The list lives in
// WorldClocks.qml; the search and the offsets come from the helper.
Item {
  id: root

  property var clocks: null      // WorldClocks.qml
  property var helper: null      // Helper.qml, for search and offsets
  property bool active: false    // popup open and this page showing
  property color ink: "white"
  property string fontFamily: "monospace"

  // Keys go to the search field while it has focus; the panel steps aside.
  readonly property bool searchFocused: search.activeFocus
  signal releaseFocus()                   // hand keys back to the panel
  signal pageRequested(int dx)            // Left/Right in an empty field

  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.28)
  readonly property color soft: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
  readonly property real unit: width
  readonly property var list: clocks ? clocks.clocks : []
  readonly property bool full: clocks ? clocks.full : false

  // Arriving on the page puts you in the search field, ready to type.
  onActiveChanged: {
    if (active) {
      nowMs = Date.now()
      refreshOffsets()
      if (!full) Qt.callLater(function() { if (root.active) search.forceActiveFocus() })
    } else {
      clearSearch()
      if (search.activeFocus) releaseFocus()
    }
  }

  // ---- Search: debounced, one request at a time, the latest query wins.
  property var suggestions: []
  property int suggestionIndex: 0
  property string pendingQuery: ""
  property bool searching: false

  function clearSearch() {
    search.text = ""
    suggestions = []
    suggestionIndex = 0
    pendingQuery = ""
  }

  function requestSearch() {
    var q = search.text.trim()
    pendingQuery = q
    if (q.length < 2) { suggestions = []; return }
    if (!searching) startSearch()
  }

  function startSearch() {
    if (!helper) return
    var q = pendingQuery
    searching = true
    helper.run(["geocode", q], function(text) {
      root.searching = false
      if (q !== root.pendingQuery) {       // moved on while this was in flight
        if (root.pendingQuery.length >= 2) root.startSearch()
        return
      }
      var r = []
      try { r = JSON.parse(text) } catch (e) {}
      root.suggestions = Array.isArray(r) ? r.slice(0, 5) : []
      root.suggestionIndex = 0
    })
  }

  Timer {
    id: searchDebounce
    interval: 300
    onTriggered: root.requestSearch()
  }

  function addPlace(place) {
    if (!clocks || !place) return
    clocks.add(place)
    clearSearch()
    if (clocks.full) releaseFocus()
  }

  function addSelected() {
    if (suggestions.length > 0) addPlace(suggestions[Math.min(suggestionIndex, suggestions.length - 1)])
  }

  // ---- Offsets from GMT, in minutes, by zone. Asked for when the page is
  //      shown or the list changes, and every ten minutes while it's up, so
  //      a clock change (summer time) shows within ten minutes.
  property var offsets: ({})

  function refreshOffsets() {
    if (!helper || list.length === 0) return
    var zones = []
    for (var i = 0; i < list.length; i++) if (zones.indexOf(list[i].timezone) < 0) zones.push(list[i].timezone)
    helper.run(["offsets"].concat(zones), function(text) {
      var o = null
      try { o = JSON.parse(text) } catch (e) {}
      if (o && typeof o === "object") root.offsets = o
    })
  }

  onListChanged: if (active) refreshOffsets()

  Timer {
    interval: 600000
    repeat: true
    running: root.active && root.list.length > 0
    onTriggered: root.refreshOffsets()
  }

  // The times only show minutes, but a one-second tick keeps them turning
  // over on the minute rather than up to a minute late.
  property real nowMs: Date.now()
  Timer {
    interval: 1000
    repeat: true
    running: root.active && root.list.length > 0
    onTriggered: root.nowMs = Date.now()
  }

  function pad(n) { return n < 10 ? "0" + n : String(n) }

  function gmtLabel(min) {
    if (min === 0) return "GMT"
    var a = Math.abs(min)
    return "GMT" + (min > 0 ? "+" : "-") + Math.floor(a / 60) + (a % 60 ? ":" + pad(a % 60) : "")
  }

  // The time there, and whether it's already tomorrow (or still yesterday)
  // compared with here.
  function timeAt(zone) {
    var off = offsets[zone]
    if (typeof off !== "number") return { time: "--:--", day: "" }
    var there = new Date(nowMs + off * 60000)
    var here = new Date(nowMs)
    var a = Date.UTC(there.getUTCFullYear(), there.getUTCMonth(), there.getUTCDate())
    var b = Date.UTC(here.getFullYear(), here.getMonth(), here.getDate())
    return {
      time: pad(there.getUTCHours()) + ":" + pad(there.getUTCMinutes()),
      day: a > b ? "Tomorrow" : a < b ? "Yesterday" : ""
    }
  }

  // ---- Layout: the same width as the other pages' content, a touch wider.
  readonly property real contentWidth: Math.round(unit * 0.84)
  readonly property real rowHeight: Math.round(unit * 0.108)

  Item {
    id: searchRow
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(root.height * 0.04)
    width: root.contentWidth
    height: search.height
    z: 2

    TextField {
      id: search
      anchors.left: parent.left
      anchors.right: addButton.left
      anchors.rightMargin: Style.space(8)
      enabled: !root.full
      placeholderText: root.full ? "Remove one to add more" : "Search city"
      foreground: root.ink
      font.family: root.fontFamily

      onTextChanged: searchDebounce.restart()

      Keys.onPressed: function(event) {
        var k = event.key
        if (k === Qt.Key_Escape) {
          if (search.text !== "") root.clearSearch()
          else root.releaseFocus()
          event.accepted = true
        } else if (k === Qt.Key_Down) {
          if (root.suggestionIndex < root.suggestions.length - 1) root.suggestionIndex++
          event.accepted = true
        } else if (k === Qt.Key_Up) {
          if (root.suggestionIndex > 0) root.suggestionIndex--
          event.accepted = true
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
          root.addSelected()
          event.accepted = true
        } else if ((k === Qt.Key_Left || k === Qt.Key_Right) && search.text === "") {
          root.pageRequested(k === Qt.Key_Right ? 1 : -1)
          event.accepted = true
        } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
          root.releaseFocus()
          event.accepted = true
        }
      }
    }

    // + adds the highlighted suggestion.
    Rectangle {
      id: addButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: search.height
      height: width
      radius: width / 2
      readonly property bool ready: root.suggestions.length > 0 && !root.full
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
        onClicked: root.addSelected()
      }
    }

    // Suggestions drop down over the list, as the weather panel's do.
    Rectangle {
      anchors.top: search.bottom
      anchors.topMargin: Style.space(4)
      anchors.left: search.left
      anchors.right: search.right
      visible: root.suggestions.length > 0 && search.activeFocus
      height: suggestionColumn.height + Style.space(8)
      radius: Style.cornerRadius
      color: Color.popups.background
      border.width: 1
      border.color: root.muted

      Column {
        id: suggestionColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(4)

        Repeater {
          model: root.suggestions

          Rectangle {
            required property var modelData
            required property int index
            width: suggestionColumn.width
            height: Math.round(root.unit * 0.085)
            radius: Style.space(4)
            color: index === root.suggestionIndex ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: modelData.name
                color: root.ink
                font.family: root.fontFamily
                font.pixelSize: Math.round(root.unit * 0.036)
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: [modelData.region, modelData.country].filter(function(s) { return !!s }).join(", ")
                color: root.soft
                font.family: root.fontFamily
                font.pixelSize: Math.round(root.unit * 0.028)
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.suggestionIndex = parent.index
              onClicked: root.addPlace(parent.modelData)
            }
          }
        }
      }
    }
  }

  // ---- The places.
  Column {
    id: rows
    anchors.top: searchRow.bottom
    anchors.topMargin: Math.round(root.height * 0.05)
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.contentWidth

    Repeater {
      model: root.list

      Item {
        id: row
        required property var modelData
        required property int index
        readonly property var at: root.timeAt(modelData.timezone)
        width: rows.width
        height: root.rowHeight

        Rectangle {
          anchors.top: parent.top
          width: parent.width
          height: 1
          color: root.muted
        }

        Column {
          anchors.left: parent.left
          anchors.right: removeButton.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: row.modelData.name
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.unit * 0.04)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: [row.modelData.country || row.modelData.region,
                   typeof root.offsets[row.modelData.timezone] === "number" ? root.gmtLabel(root.offsets[row.modelData.timezone]) : "",
                   row.at.day].filter(function(s) { return !!s }).join(" · ")
            color: root.soft
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.unit * 0.029)
          }
        }

        // ✕ in a small grey ring, shown while the row is hovered.
        Rectangle {
          id: removeButton
          anchors.right: timeText.left
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
            onClicked: if (root.clocks) root.clocks.remove(row.index)
          }
        }

        Text {
          id: timeText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.at.time
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Math.round(root.unit * 0.068)
          font.weight: Font.Light
        }

        HoverHandler { id: rowHover }
      }
    }
  }

  Text {
    visible: root.list.length === 0
    anchors.top: rows.top
    anchors.topMargin: Math.round(root.height * 0.08)
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.PlainText
    text: "Search for a city to add its clock"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.unit * 0.032)
  }
}
