import QtQuick
import Quickshell
import Quickshell.Io

// Stopwatch state, kept apart from its page so it keeps running whether or
// not the popup is open.
//
// Timestamp-based: elapsed = banked + (now - startedAt). Nothing accumulates
// tick by tick, so it can't drift, it counts through suspend as Apple's does,
// and it survives a shell restart through the state file. Every bar gets its
// own copy of this widget (one per monitor); they all share the one file and
// watch it, so a stopwatch started on one screen reads the same on the others.
Item {
  id: root
  visible: false

  // Bounded, so a runaway Lap key can't grow the list or the file forever.
  readonly property int maxLaps: 999

  property bool running: false
  property real startedAt: 0   // epoch ms the current run started
  property real banked: 0      // ms carried over from earlier runs
  property var laps: []        // completed lap durations in ms, oldest first
  property real lapsTotal: 0   // sum of `laps`; the running lap is elapsed - this

  readonly property bool fresh: !running && banked === 0

  function elapsedAt(nowMs) { return running ? banked + (nowMs - startedAt) : banked }
  function currentLapAt(nowMs) { return Math.max(0, elapsedAt(nowMs) - lapsTotal) }

  function start() {
    if (running) return
    startedAt = Date.now()
    running = true
    save()
  }

  function stop() {
    if (!running) return
    banked = elapsedAt(Date.now())
    running = false
    save()
  }

  function toggle() { running ? stop() : start() }

  function lap() {
    if (!running || laps.length >= maxLaps) return
    var split = currentLapAt(Date.now())
    laps = laps.concat([split])
    lapsTotal += split
    save()
  }

  function reset() {
    if (running) return
    banked = 0
    laps = []
    lapsTotal = 0
    save()
  }

  // The left button: Lap while running, Reset once stopped (as Apple's).
  function lapOrReset() { running ? lap() : reset() }

  // "12:34.5", or "1:02:03.4" past the hour.
  function format(ms) {
    var tenths = Math.floor(ms / 100)
    var t = tenths % 10
    var s = Math.floor(tenths / 10) % 60
    var m = Math.floor(tenths / 600) % 60
    var h = Math.floor(tenths / 36000)
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(s) + "." + t
  }

  // ---- Persistence. Loading never writes, so the watching copies can't
  //      bounce the file back and forth between them.
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/crazybadger.split-clock.stopwatch.json"

  function save() {
    stateFile.setText(JSON.stringify({
      running: running,
      startedAt: startedAt,
      banked: banked,
      laps: laps
    }) + "\n")
  }

  function finite(v) { return typeof v === "number" && isFinite(v) && v >= 0 }

  function load(text) {
    var s
    try { s = JSON.parse(text) } catch (e) { return }
    if (!s || typeof s !== "object") return

    var cleanLaps = Array.isArray(s.laps) ? s.laps.filter(finite).slice(0, maxLaps) : []
    var total = 0
    for (var i = 0; i < cleanLaps.length; i++) total += cleanLaps[i]

    running = s.running === true && finite(s.startedAt) && s.startedAt > 0
    startedAt = running ? s.startedAt : 0
    banked = finite(s.banked) ? s.banked : 0
    laps = cleanLaps
    lapsTotal = total
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
