import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omarchy's clock, split in two. The day and the time are separate bar
// buttons, each with its own popup:
//
//   day  -> the stock calendar (CalendarPanel.qml, unchanged apart from its ids)
//   time -> an analogue clock face (ClockPanel.qml)
//
// The two panels are separate popout identities on purpose: the bar's popout
// coordinator allows one panel per identity, so giving the clock face its own
// identity is what lets clicking the time while the calendar is open (or the
// other way round) hand over with the bar's normal cross-fade.
//
// Right click on either half cycles that half's label format; middle click
// opens the timezone picker, as on the stock clock.
BarWidget {
  id: root
  moduleName: "crazybadger.split-clock"

  property date displayDate: clock.date

  readonly property var dayFormats: ["dddd", "ddd d MMM", "d MMMM yyyy", "dddd d"]
  readonly property var timeFormats: ["HH:mm", "HH:mm:ss", "h:mm AP"]

  readonly property string dayFormat: setting("dayFormat", dayFormats[0])
  readonly property string timeFormat: setting("timeFormat", timeFormats[0])
  readonly property string verticalDayFormat: setting("verticalDayFormat", "ddd")
  readonly property string verticalTimeFormat: setting("verticalTimeFormat", "HH\n—\nmm")

  readonly property string dayText: Qt.formatDateTime(displayDate, vertical ? verticalDayFormat : dayFormat)
  readonly property string timeText: Qt.formatDateTime(displayDate, vertical ? verticalTimeFormat : timeFormat)
  readonly property var verticalTimeLines: timeText.split("\n")

  function refresh() {
    displayDate = new Date()
    if (calendarLoader.item && calendarLoader.item.refresh) calendarLoader.item.refresh()
  }

  // Written back to shell.json so a cycled format survives a restart. Applied
  // locally first so the label changes on the click itself.
  function persist(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function nextIn(ring, current) {
    var i = ring.indexOf(String(current))
    return ring[(i + 1) % ring.length]
  }

  function cycleDayFormat() { persist(vertical ? "verticalDayFormat" : "dayFormat", nextIn(vertical ? ["ddd", "d"] : dayFormats, vertical ? verticalDayFormat : dayFormat)) }
  function cycleTimeFormat() { if (!vertical) persist("timeFormat", nextIn(timeFormats, timeFormat)) }

  // ---- Popups. The calendar is this widget's identity (the shape contract
  //      for shell.summon/hide/toggle routing needs open/close/opened on the
  //      bar-widget root); the clock face is its own.
  readonly property bool opened: (calendarLoader.item ? calendarLoader.item.opened === true : false)
    || (faceLoader.item ? faceLoader.item.opened === true : false)

  function open() { if (calendarLoader.item) calendarLoader.item.open() }
  function close() {
    if (calendarLoader.item) calendarLoader.item.close()
    if (faceLoader.item) faceLoader.item.close()
  }
  function togglePanel() { if (calendarLoader.item) calendarLoader.item.toggle() }
  function openFace() { if (faceLoader.item) faceLoader.item.open() }
  function toggleFace() { if (faceLoader.item) faceLoader.item.toggle() }
  function openFacePage(name) {
    if (!faceLoader.item) return
    faceLoader.item.showPageNamed(name)
    faceLoader.item.open()
  }
  function toggleWeekStart() { if (calendarLoader.item) calendarLoader.item.toggleWeekStart() }

  // Forwarded so this widget can stand in for the calendar as the bar's
  // popout identity (see the stock clock for the reasoning).
  readonly property bool popoutSwitchClosing: calendarLoader.item ? calendarLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (calendarLoader.item) calendarLoader.item.closeForPopoutSwitch() }

  // The bar draws its open-panel mark centred under the whole widget, and
  // only for the widget's primary popup. Here the mark belongs under the half
  // that is open (day for the calendar, time for the clock face), so the bar's
  // own is reduced to nothing (a hint that rounds to 0) and `underline` below
  // draws it instead, in the same style.
  readonly property real openPanelIndicatorWidth: 0.001
  readonly property real openPanelIndicatorHeight: 0.001

  readonly property bool dayOpen: calendarLoader.item ? calendarLoader.item.opened === true : false
  readonly property bool faceOpen: faceLoader.item ? faceLoader.item.opened === true : false

  function injectPanels() {
    var cal = calendarLoader.item
    if (cal) {
      if ("bar" in cal) cal.bar = root.bar
      if ("settings" in cal) cal.settings = root.settings
      if ("anchorItem" in cal) cal.anchorItem = dayButton
      if ("hostWidget" in cal) cal.hostWidget = root
    }
    var face = faceLoader.item
    if (face) {
      if ("bar" in face) face.bar = root.bar
      if ("settings" in face) face.settings = root.settings
      if ("anchorItem" in face) face.anchorItem = timeButton
      if ("sibling" in face) face.sibling = root
    }
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  onBarChanged: injectPanels()
  onSettingsChanged: injectPanels()

  SystemClock {
    id: clock
    precision: !root.vertical && root.timeFormat.indexOf("ss") >= 0 ? SystemClock.Seconds : SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: calendarLoader
    active: true
    source: Qt.resolvedUrl("CalendarPanel.qml")
    visible: false
    onLoaded: { root.injectPanels(); Qt.callLater(root.injectPanels) }
  }

  Loader {
    id: faceLoader
    active: true
    source: Qt.resolvedUrl("ClockPanel.qml")
    visible: false
    onLoaded: { root.injectPanels(); Qt.callLater(root.injectPanels) }
  }

  IpcHandler {
    target: "crazybadger.split-clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleTimeFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function openFace(): void { root.openFace() }
    function toggleFace(): void { root.toggleFace() }
    function openPage(name: string): void { root.openFacePage(name) }
  }

  // The open-panel mark: an accent bar on the bar's inner edge, under (or
  // beside, on a vertical bar) the half whose popup is open. It slides
  // between the halves when one popup hands over to the other, and fades in
  // and out in place otherwise.
  Rectangle {
    id: underline

    // Kept while fading out, so it does not slide away as the popup closes.
    property Item target: dayButton
    readonly property bool shown: root.dayOpen || root.faceOpen
    readonly property int inset: Style.space(2)
    readonly property string edge: root.bar && root.bar.position ? root.bar.position : "top"
    readonly property real along: root.vertical
      ? Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
      : Math.max(Style.space(10), target === timeButton ? timeButton.labelWidth : dayButton.labelWidth)

    Connections {
      target: root
      function onFaceOpenChanged() { if (root.faceOpen) underline.target = timeButton }
      function onDayOpenChanged() { if (root.dayOpen) underline.target = dayButton }
    }

    z: 50
    visible: opacity > 0
    opacity: shown ? 0.9 : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
    width: root.vertical ? Style.space(2) : along
    height: root.vertical ? along : Style.space(2)
    x: root.vertical
      ? (edge === "left" ? root.width - width - inset : inset)
      : Math.round(layout.x + target.x + (target.width - width) / 2)
    y: root.vertical
      ? Math.round(layout.y + target.y + (target.height - height) / 2)
      : (edge === "top" ? root.height - height - inset : inset)

    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on x { enabled: underline.opacity > 0.5; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: underline.opacity > 0.5; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: underline.opacity > 0.5; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }

  Grid {
    id: layout
    anchors.fill: parent
    columns: root.vertical ? 1 : 2
    spacing: 0

    WidgetButton {
      id: dayButton
      bar: root.bar
      text: root.dayText
      hasVisualContent: text !== ""
      horizontalMargin: 5
      verticalPadding: 8.75
      tooltipText: "Calendar"

      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycleDayFormat()
        else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
        else root.togglePanel()
      }
    }

    WidgetButton {
      id: timeButton
      bar: root.bar
      text: root.vertical ? "" : root.timeText
      labelVisible: !root.vertical
      hasVisualContent: root.vertical ? root.verticalTimeLines.length > 0 : text !== ""
      fixedHeight: root.vertical ? root.verticalTimeLines.length * Style.bar.iconSlot : -1
      horizontalMargin: 5
      verticalPadding: 8.75
      tooltipText: "Clock"

      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycleTimeFormat()
        else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
        else root.toggleFace()
      }

      Column {
        visible: root.vertical
        anchors.fill: parent

        Repeater {
          model: root.verticalTimeLines

          OpticalGlyph {
            required property string modelData
            width: timeButton.width
            height: Style.bar.iconSlot
            text: modelData
            fontFamily: timeButton.fontFamily
            fontSize: modelData.length > 3 ? timeButton.fontSize * 0.9 : timeButton.fontSize
            color: timeButton.foreground
          }
        }
      }
    }
  }
}
