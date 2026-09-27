import QtQuick

// Stopwatch state, kept apart from its page so it keeps running whether or
// not the popup is open.
//
// Timestamp-based: elapsed = banked + (now - startedAt). Nothing accumulates
// tick by tick, so it can't drift, and it counts through suspend as Apple's
// does. ClockPanel saves it (through the helper) whenever it `changed`, loads
// it at start, and hands each change to the other monitors' copies.
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

  // Never below what's banked: if the wall clock is stepped back while it
  // runs (an NTP correction at boot, a manual change), it holds rather than
  // going negative.
  function elapsedAt(nowMs) { return running ? banked + Math.max(0, nowMs - startedAt) : banked }
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

  // "12:34.56", or "1:02:03.45" past the hour -- the same eight-character
  // shape as the timer's 00:00:00.
  function format(ms) {
    var cs = Math.floor(ms / 10)
    var c = cs % 100
    var s = Math.floor(cs / 100) % 60
    var m = Math.floor(cs / 6000) % 60
    var h = Math.floor(cs / 360000)
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(s) + "." + pad(c)
  }

  // ---- Persistence. `load` never signals `changed`, so copies passing a
  //      change along can't bounce it back and forth.
  signal changed()
  function save() { changed() }

  function snapshot() {
    return { running: running, startedAt: startedAt, banked: banked, laps: laps }
  }

  function finite(v) { return typeof v === "number" && isFinite(v) && v >= 0 }

  function load(s) {
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
}
