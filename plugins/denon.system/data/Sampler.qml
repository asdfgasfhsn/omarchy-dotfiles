pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One sampler for every rail: each monitor's bar gets its own denon.system
// widget, and they all read these properties instead of each running
// sample.py. A JSON line every two seconds; three minutes of history.
Singleton {
  id: sampler

  property var cpu: null
  property var gpu: null
  property var mem: null
  property var disks: []
  property var cpuHistory: []
  property var gpuHistory: []
  property var memHistory: []
  readonly property int historyLength: 90

  function push(list, value) {
    var next = list.concat([value])
    return next.length > historyLength ? next.slice(next.length - historyLength) : next
  }
  function ingest(line) {
    var s
    try { s = JSON.parse(line) } catch (e) { return }
    cpu = s.cpu || null
    gpu = s.gpu || null
    mem = s.mem || null
    disks = s.disks || []
    if (cpu) cpuHistory = push(cpuHistory, cpu.total)
    if (gpu && gpu.util !== null) gpuHistory = push(gpuHistory, gpu.util)
    if (mem && mem.total > 0) memHistory = push(memHistory, 100 * mem.used / mem.total)
  }

  readonly property string script: String(Qt.resolvedUrl("../sample.py")).replace(/^file:\/\//, "")
  Process {
    id: proc
    command: ["python3", "-I", sampler.script, "2"]
    running: true
    stdout: SplitParser { onRead: function(line) { sampler.ingest(line) } }
    // Keep sampling if the helper ever dies.
    onRunningChanged: if (!running) restart.restart()
  }
  Timer { id: restart; interval: 5000; onTriggered: proc.running = true }
}
