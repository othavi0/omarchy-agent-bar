import QtQuick

QtObject {
  id: lane

  required property var process
  property var stdoutSource: null
  property var stderrSource: null
  property int timeoutMs: 0

  readonly property bool busy: lane.outstanding
  readonly property bool ready: !lane.outstanding && !lane.process.running
  readonly property bool stalled: lane.stallMark
  readonly property string stdinText: lane.pendingStdin

  signal settled(var outcome)

  property bool outstanding: false
  property bool stallMark: false
  property int runId: 0
  property int startedRunId: 0
  property string pendingStdin: ""
  property var pendingContext: null

  function start(argv, stdin, runContext) {
    if (!lane.ready)
      return false
    if (!argv || !argv.length)
      return false
    lane.runId++
    lane.startedRunId = lane.runId
    lane.outstanding = true
    lane.pendingContext = runContext === undefined ? null : runContext
    lane.pendingStdin = stdin === undefined || stdin === null ? "" : String(stdin)
    lane.process.stdinEnabled = lane.pendingStdin.length > 0
    lane.process.command = argv
    lane.deadline.restart()
    lane.process.running = true
    return true
  }

  function clearStall() {
    lane.stallMark = false
  }

  function deliverStdin() {
    if (!lane.pendingStdin.length)
      return
    // write() alone does not deliver EOF; stdinEnabled = false closes the channel.
    lane.process.write(lane.pendingStdin + "\n")
    lane.process.stdinEnabled = false
  }

  function finish(exitCode) {
    if (lane.startedRunId !== lane.runId) {
      lane.stallMark = false
      return
    }
    if (!lane.outstanding)
      return
    lane.settle({
      ok: exitCode === 0,
      exitCode: exitCode,
      stdout: lane.stdoutSource ? String(lane.stdoutSource.text || "") : "",
      stderr: lane.stderrSource ? String(lane.stderrSource.text || "") : "",
      timedOut: false,
      runId: lane.startedRunId,
      context: lane.pendingContext
    })
  }

  function expire() {
    if (!lane.outstanding)
      return
    if (lane.process.running)
      lane.process.running = false
    lane.stallMark = true
    var abandoned = lane.startedRunId
    lane.runId++
    lane.settle({
      ok: false,
      exitCode: 1,
      stdout: "",
      stderr: "timeout",
      timedOut: true,
      runId: abandoned,
      context: lane.pendingContext
    })
  }

  function settle(outcome) {
    lane.deadline.stop()
    lane.pendingStdin = ""
    lane.pendingContext = null
    if (!outcome.timedOut)
      lane.stallMark = false
    lane.outstanding = false
    lane.settled(outcome)
  }

  property Timer deadline: Timer {
    interval: lane.timeoutMs
    repeat: false
    onTriggered: lane.expire()
  }

  property Connections processEvents: Connections {
    target: lane.process
    function onStarted() { lane.deliverStdin() }
    function onExited(exitCode) { lane.finish(exitCode) }
  }

  Component.onDestruction: {
    lane.deadline.stop()
    if (lane.process && lane.process.running)
      lane.process.running = false
  }
}
