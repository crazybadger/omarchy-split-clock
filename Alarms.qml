import QtQuick

// Alarms: a clock time, an optional label, repeat days (none = once), on/off.
// Kept apart from the page like the other states; ClockPanel saves it when it
// `changed`, hands changes to the other monitors' copies, and -- on the one
// copy that owns alerts -- rings when `due` fires.
//
// Checked against the wall clock every few seconds, so one that fell due
// while the laptop slept is noticed on wake: `due` says how late it is, and
// ClockPanel rings only if it's on time (a notification says it was missed
// otherwise).
Item {
  id: root
  visible: false

  readonly property int maxAlarms: 6
  readonly property int snoozeMinutes: 9          // Apple's
  readonly property var dayLetters: ["M", "T", "W", "T", "F", "S", "S"]   // Monday first

  // { id, hour, minute, label, days: [7 bools, Mon..Sun], enabled,
  //   armedAt, lastFired, snoozeUntil }   (times in epoch ms)
  property var alarms: []
  property string ringingId: ""
  property real ringingSince: 0

  readonly property bool full: alarms.length >= maxAlarms
  readonly property bool ringing: ringingId !== ""
  readonly property var ringingAlarm: find(ringingId)

  signal changed()
  signal due(var alarm, real occurrence, bool snoozed)

  function find(id) {
    for (var i = 0; i < alarms.length; i++) if (alarms[i].id === id) return alarms[i]
    return null
  }

  function copy(a) { return JSON.parse(JSON.stringify(a)) }

  function update(id, fn) {
    var list = alarms.map(copy)
    for (var i = 0; i < list.length; i++) if (list[i].id === id) fn(list[i])
    alarms = list
    changed()
  }

  function repeats(a) { return a.days.some(function(d) { return d }) }

  // Listed by time of day, earliest first (as Apple's are): the order stays put
  // as alarms ring, and the page's "Next:" line says which is next.
  function sorted(list) {
    return list.slice().sort(function(a, b) {
      return (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
    })
  }

  // ---- Editing. Every edit re-arms the alarm from now, so changing it never
  //      makes an occurrence that has already passed go off.
  function add(hour, minute, label, days) {
    if (full || !(hour >= 0 && hour < 24 && minute >= 0 && minute < 60)) return false
    var now = Date.now()
    alarms = sorted([{
      id: String(now) + "-" + Math.floor(Math.random() * 1e6),
      hour: hour, minute: minute,
      label: String(label || "").slice(0, 40),
      days: (days || [false, false, false, false, false, false, false]).slice(0, 7),
      enabled: true, armedAt: now, lastFired: 0, snoozeUntil: 0
    }].concat(alarms))
    changed()
    return true
  }

  function remove(id) {
    if (ringingId === id) ringingId = ""
    alarms = alarms.filter(function(a) { return a.id !== id })
    changed()
  }

  function setEnabled(id, on) {
    update(id, function(a) { a.enabled = on; a.armedAt = Date.now(); a.snoozeUntil = 0 })
  }

  function toggleDay(id, index) {
    update(id, function(a) { a.days[index] = !a.days[index]; a.armedAt = Date.now() })
  }

  // ---- Ringing.
  function ring(id, occurrence) {
    update(id, function(a) {
      a.lastFired = occurrence
      a.snoozeUntil = 0
      if (!repeats(a)) a.enabled = false          // a one-off turns itself off
    })
    ringingId = id
    ringingSince = Date.now()
    changed()
  }

  // Marked as handled without ringing (it fell due while asleep).
  function markMissed(id, occurrence) {
    update(id, function(a) {
      a.lastFired = occurrence
      a.snoozeUntil = 0
      if (!repeats(a)) a.enabled = false
    })
  }

  function stop() {
    if (!ringing) return
    ringingId = ""
    changed()
  }

  function snooze() {
    if (!ringing) return
    var id = ringingId
    ringingId = ""
    update(id, function(a) { a.snoozeUntil = Date.now() + snoozeMinutes * 60000 })
  }

  // ---- Time maths, in local time. Day index: Monday 0 .. Sunday 6.
  function dayIndex(d) { return (d.getDay() + 6) % 7 }

  function at(base, dayOffset, a) {
    return new Date(base.getFullYear(), base.getMonth(), base.getDate() + dayOffset, a.hour, a.minute, 0, 0)
  }

  // The most recent scheduled moment at or before `nowMs`.
  function latestDue(a, nowMs) {
    var base = new Date(nowMs)
    for (var d = 0; d <= 7; d++) {
      var t = at(base, -d, a)
      if (t.getTime() <= nowMs && (!repeats(a) || a.days[dayIndex(t)])) return t.getTime()
    }
    return 0
  }

  // The next scheduled moment after `fromMs`.
  function nextOccurrence(a, fromMs) {
    if (a.snoozeUntil > fromMs) return a.snoozeUntil
    var base = new Date(fromMs)
    for (var d = 0; d <= 7; d++) {
      var t = at(base, d, a)
      if (t.getTime() > fromMs && (!repeats(a) || a.days[dayIndex(t)])) return t.getTime()
    }
    return 0
  }

  // The soonest enabled alarm, for the page's "Next:" line.
  function nextAlarm(nowMs) {
    var best = null, when = 0
    for (var i = 0; i < alarms.length; i++) {
      var a = alarms[i]
      if (!a.enabled && !(a.snoozeUntil > nowMs)) continue
      var t = nextOccurrence(a, nowMs)
      if (t && (!best || t < when)) { best = a; when = t }
    }
    return best ? { alarm: best, at: when } : null
  }

  function check() {
    var now = Date.now()
    for (var i = 0; i < alarms.length; i++) {
      var a = alarms[i]
      if (a.snoozeUntil > 0 && now >= a.snoozeUntil) {
        due(a, a.snoozeUntil, true)
        continue
      }
      if (!a.enabled) continue
      var occ = latestDue(a, now)
      if (occ && occ > Math.max(a.lastFired || 0, a.armedAt || 0)) due(a, occ, false)
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.alarms.some(function(a) { return a.enabled || a.snoozeUntil > 0 })
    triggeredOnStart: true
    onTriggered: root.check()
  }

  function pad(n) { return n < 10 ? "0" + n : String(n) }
  function timeText(a) { return pad(a.hour) + ":" + pad(a.minute) }

  // ---- Persistence (see Stopwatch.qml).
  function snapshot() { return { alarms: alarms, ringingId: ringingId, ringingSince: ringingSince } }

  function finite(v) { return typeof v === "number" && isFinite(v) && v >= 0 }

  function load(s) {
    if (!s || typeof s !== "object" || !Array.isArray(s.alarms)) return
    var out = []
    for (var i = 0; i < s.alarms.length && out.length < maxAlarms; i++) {
      var a = s.alarms[i]
      if (!a || typeof a !== "object" || typeof a.id !== "string" || a.id.length > 40) continue
      if (!(a.hour >= 0 && a.hour < 24 && a.minute >= 0 && a.minute < 60)) continue
      var days = Array.isArray(a.days) ? a.days.slice(0, 7).map(function(d) { return d === true }) : []
      while (days.length < 7) days.push(false)
      out.push({
        id: a.id, hour: Math.floor(a.hour), minute: Math.floor(a.minute),
        label: typeof a.label === "string" ? a.label.slice(0, 40) : "",
        days: days, enabled: a.enabled === true,
        armedAt: finite(a.armedAt) ? a.armedAt : Date.now(),
        lastFired: finite(a.lastFired) ? a.lastFired : 0,
        snoozeUntil: finite(a.snoozeUntil) ? a.snoozeUntil : 0
      })
    }
    alarms = sorted(out)
    ringingId = typeof s.ringingId === "string" && find(s.ringingId) ? s.ringingId : ""
    ringingSince = finite(s.ringingSince) ? s.ringingSince : 0
  }
}
