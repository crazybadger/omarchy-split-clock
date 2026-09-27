import QtQuick

// The world clock's list of places, kept apart from its page like the
// stopwatch and timer. Each place is what the search found:
//   { name, region, country, timezone }   (timezone: IANA, e.g. Europe/London)
// ClockPanel saves it whenever it `changed` and hands changes to the other
// monitors' copies; `load` never signals, so they can't bounce.
Item {
  id: root
  visible: false

  // As many as fit on the card without scrolling.
  readonly property int maxClocks: 6

  property var clocks: []
  readonly property bool full: clocks.length >= maxClocks

  signal changed()

  function same(a, b) { return a.name === b.name && a.region === b.region && a.timezone === b.timezone }

  function add(place) {
    if (full || !place || !place.timezone) return false
    for (var i = 0; i < clocks.length; i++) if (same(clocks[i], place)) return false
    // Newest first: it goes in at the top and pushes the rest down.
    clocks = [{
      name: String(place.name || ""),
      region: String(place.region || ""),
      country: String(place.country || ""),
      timezone: String(place.timezone)
    }].concat(clocks)
    changed()
    return true
  }

  function remove(index) {
    if (index < 0 || index >= clocks.length) return
    var c = clocks.slice()
    c.splice(index, 1)
    clocks = c
    changed()
  }

  function snapshot() { return clocks }

  // Only well-formed entries; the helper checks the zones themselves when it
  // works out their offsets, and drops any it doesn't know.
  function load(s) {
    if (!Array.isArray(s)) return
    var out = []
    for (var i = 0; i < s.length && out.length < maxClocks; i++) {
      var p = s[i]
      if (!p || typeof p !== "object" || typeof p.name !== "string" || typeof p.timezone !== "string") continue
      if (!/^[A-Za-z0-9_+\-]+(\/[A-Za-z0-9_+\-]+)*$/.test(p.timezone) || p.timezone.length > 64) continue
      out.push({
        name: p.name.slice(0, 100),
        region: typeof p.region === "string" ? p.region.slice(0, 100) : "",
        country: typeof p.country === "string" ? p.country.slice(0, 100) : "",
        timezone: p.timezone
      })
    }
    clocks = out
  }
}
