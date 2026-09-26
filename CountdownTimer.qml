import QtQuick
import Quickshell
import Quickshell.Io

// Countdown timer state, kept apart from its page so it runs whether or not
// the popup is open. Same approach as Stopwatch.qml: timestamps, not ticks,
// saved to a state file that every monitor's copy of the widget shares and
// watches.
//
// This only notices that the time is up (`expired`). Finishing and alerting
// is ClockPanel's job, so that with several monitors exactly one copy does
// it -- see ClockPanel.onTimerExpired.
Item {
  id: root
  visible: false

  readonly property int maxRecents: 5
  readonly property real maxDuration: (99 * 3600 + 59 * 60 + 59) * 1000

  property string status: "idle"   // "idle" | "running" | "paused"
  property real duration: 0        // ms, of the timer last started
  property real endsAt: 0          // epoch ms, while running
  property real remaining: 0       // ms left, while paused
  property var recents: []         // durations in ms, newest first

  signal expired()

  function remainingAt(nowMs) {
    if (status === "running") return Math.max(0, endsAt - nowMs)
    if (status === "paused") return remaining
    return duration
  }

  function start(ms) {
    ms = Math.min(maxDuration, Math.round(ms))
    if (!(ms > 0)) return
    duration = ms
    endsAt = Date.now() + ms
    remaining = 0
    status = "running"
    var r = recents.filter(function(x) { return x !== ms })
    r.unshift(ms)
    recents = r.slice(0, maxRecents)
    save()
  }

  function pause() {
    if (status !== "running") return
    remaining = Math.max(0, endsAt - Date.now())
    status = "paused"
    save()
  }

  function resume() {
    if (status !== "paused") return
    endsAt = Date.now() + remaining
    status = "running"
    save()
  }

  function reset() {
    if (status === "idle") return
    status = "idle"
    endsAt = 0
    remaining = 0
    save()
  }

  function clearRecents() {
    if (recents.length === 0) return
    recents = []
    save()
  }

  // Called by whichever copy raises the alert.
  function finish() {
    if (status !== "running") return
    status = "idle"
    endsAt = 0
    remaining = 0
    save()
  }

  // Checked against the wall clock four times a second, and only while
  // running. Wall clock rather than a one-shot Timer, because a Timer's clock
  // stops during suspend: this way a timer that ran out while the lid was
  // shut goes off on wake instead of that much later.
  property real expiredFor: 0
  Timer {
    interval: 250
    repeat: true
    running: root.status === "running"
    onTriggered: {
      if (Date.now() >= root.endsAt && root.expiredFor !== root.endsAt) {
        root.expiredFor = root.endsAt
        root.expired()
      }
    }
  }

  // "15:00" -> "15 min", 5400000 -> "1 h 30 min", 45000 -> "45 s".
  function describe(ms) {
    var t = Math.round(ms / 1000)
    var h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, s = t % 60
    var parts = []
    if (h) parts.push(h + " h")
    if (m) parts.push(m + " min")
    if (s) parts.push(s + " s")
    return parts.length ? parts.join(" ") : "0 s"
  }

  // "00:15:00". Remaining time is rounded up, so it reads 00:00:01 until the
  // moment it's done, as Apple's does.
  function format(ms) {
    var t = Math.ceil(ms / 1000)
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return pad(Math.floor(t / 3600)) + ":" + pad(Math.floor(t / 60) % 60) + ":" + pad(t % 60)
  }

  // ---- Persistence. Loading never writes (see Stopwatch.qml).
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/crazybadger.split-clock.timer.json"

  function save() {
    stateFile.setText(JSON.stringify({
      status: status,
      duration: duration,
      endsAt: endsAt,
      remaining: remaining,
      recents: recents
    }) + "\n")
  }

  function finite(v) { return typeof v === "number" && isFinite(v) && v >= 0 }

  function load(text) {
    var s
    try { s = JSON.parse(text) } catch (e) { return }
    if (!s || typeof s !== "object") return

    var st = s.status === "running" || s.status === "paused" ? s.status : "idle"
    if (st === "running" && !(finite(s.endsAt) && s.endsAt > 0)) st = "idle"
    if (st === "paused" && !finite(s.remaining)) st = "idle"

    status = st
    duration = finite(s.duration) ? Math.min(maxDuration, s.duration) : 0
    endsAt = st === "running" ? s.endsAt : 0
    remaining = st === "paused" ? s.remaining : 0
    recents = Array.isArray(s.recents)
      ? s.recents.filter(function(x) { return finite(x) && x > 0 && x <= maxDuration }).slice(0, maxRecents)
      : []
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onFileChanged: reload()
  }
}
