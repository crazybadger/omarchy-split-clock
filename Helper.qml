import QtQuick
import Quickshell.Io

// Runs split-clock-helper.py, which does all the disk and network work (see
// the notes at its top). One command at a time, in order; each runs under a
// deadline, and what it prints is capped before the shell collects it.
Item {
  id: root
  visible: false

  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("split-clock-helper.py")).replace(/^file:\/\//, ""))
  readonly property int maxOutput: 65536

  property var queue: []     // [{ args, done }]
  property var current: null
  property int runId: 0      // which run the process's output belongs to

  // done(text) gets what the helper printed -- empty when it failed (it
  // reports failures on stderr only), so callers treat "" as nothing.
  function run(args, done) {
    queue = queue.concat([{ args: args, done: done || null }])
    next()
  }

  // Only the newest save of each state matters: drop one still waiting.
  function save(name, value) {
    queue = queue.filter(function(job) { return !(job.args[0] === "write" && job.args[1] === name) })
    run(["write", name, JSON.stringify(value)])
  }

  function next() {
    if (proc.running || current || queue.length === 0) return
    current = queue[0]
    queue = queue.slice(1)
    current.id = ++runId
    proc.command = ["bash", "-c",
      "set -o pipefail; timeout -k 2 8 python3 \"$0\" \"$@\" | head -c " + maxOutput,
      root.script].concat(current.args)
    proc.running = true
    watchdog.restart()
  }

  // The helper is already killed after 8 s (`timeout`); this only keeps the
  // queue moving if it never managed to start at all.
  Timer {
    id: watchdog
    interval: 12000
    onTriggered: if (root.current) root.finish("")
  }

  // `id`: the run the output came from -- a run the watchdog already gave up
  // on mustn't complete the job after it.
  function finish(text, id) {
    if (!current || (id !== undefined && id !== current.id)) return
    watchdog.stop()
    var job = current
    current = null
    if (job && job.done) job.done(text)
    Qt.callLater(next)
  }

  Process {
    id: proc
    property int id: 0
    onStarted: id = root.runId
    // Output can finish before the process is reaped; pick up the queue then.
    onRunningChanged: if (!running) Qt.callLater(root.next)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finish(text, proc.id)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text !== "") console.warn(text.slice(0, 300).trim())
    }
  }
}
