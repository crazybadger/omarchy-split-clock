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
  function toggleWeekStart() { if (calendarLoader.item) calendarLoader.item.toggleWeekStart() }

  // Forwarded so this widget can stand in for the calendar as the bar's
  // popout identity (see the stock clock for the reasoning).
  readonly property bool popoutSwitchClosing: calendarLoader.item ? calendarLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (calendarLoader.item) calendarLoader.item.closeForPopoutSwitch() }

  // The open-panel dot sits under the whole label, not just one half.
  readonly property real openPanelIndicatorWidth: Math.max(0, layout.implicitWidth - Style.spaceReal(12))
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

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
