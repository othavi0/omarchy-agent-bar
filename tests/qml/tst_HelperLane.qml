import QtQuick
import QtTest
import "../../components"

TestCase {
  id: testCase
  name: "AgentBarHelperLane"
  when: windowShown

  property var rig: null

  Component {
    id: rigFactory

    QtObject {
      id: rig

      property var log: []
      property var outcomes: []

      property QtObject out: QtObject { property string text: "" }
      property QtObject err: QtObject { property string text: "" }

      // Models Quickshell 0.3.1: running = false is SIGTERM, so the process
      // stays alive until its own exit arrives.
      property QtObject proc: QtObject {
        id: fakeProcess
        property bool alive: false
        property bool running: false
        property var command: []
        property bool stdinEnabled: false
        signal started()
        signal exited(int exitCode)
        function write(data) { rig.log.push("write:" + data) }
        function finish(code) { alive = false; running = false; exited(code) }
        onStdinEnabledChanged: rig.log.push("stdin:" + stdinEnabled)
        onRunningChanged: {
          if (running && !alive) {
            alive = true
            started()
          } else if (!running && alive) {
            running = true
          }
        }
      }

      property HelperLane lane: HelperLane {
        process: rig.proc
        stdoutSource: rig.out
        stderrSource: rig.err
        timeoutMs: 40
        onSettled: function (outcome) { rig.outcomes.push(outcome) }
      }
    }
  }

  function init() {
    rig = rigFactory.createObject(testCase)
    verify(rig !== null)
  }

  function cleanup() {
    if (rig) {
      rig.destroy()
      rig = null
    }
  }

  function argv() {
    return ["/nonexistent/agent-bar", "status"]
  }

  function test_start_refuses_a_second_run_while_busy() {
    compare(rig.lane.start(argv()), true)
    compare(rig.lane.busy, true)
    compare(rig.lane.ready, false)
    compare(rig.lane.start(argv()), false)
    compare(rig.lane.runId, 1)
  }

  function test_start_refuses_empty_argv() {
    compare(rig.lane.start([]), false)
    compare(rig.lane.start(null), false)
    compare(rig.lane.busy, false)
    compare(rig.lane.runId, 0)
  }

  function test_an_exit_settles_the_run_once_with_its_output() {
    rig.lane.start(argv())
    rig.out.text = "done\n"
    rig.err.text = "noise\n"
    rig.proc.finish(0)
    compare(rig.outcomes.length, 1)
    compare(rig.outcomes[0].ok, true)
    compare(rig.outcomes[0].exitCode, 0)
    compare(rig.outcomes[0].stdout, "done\n")
    compare(rig.outcomes[0].stderr, "noise\n")
    compare(rig.outcomes[0].timedOut, false)
    compare(rig.lane.busy, false)
    compare(rig.lane.ready, true)
  }

  function test_a_deadline_terminates_and_settles_once_as_timed_out() {
    rig.lane.start(argv())
    tryCompare(rig.lane, "busy", false, 500)
    compare(rig.outcomes.length, 1)
    compare(rig.outcomes[0].timedOut, true)
    compare(rig.outcomes[0].ok, false)
    compare(rig.outcomes[0].exitCode, 1)
    compare(rig.outcomes[0].stderr, "timeout")
    compare(rig.lane.stalled, true)
    compare(rig.proc.alive, true)
    compare(rig.lane.ready, false)
  }

  function test_a_timed_out_lane_stays_closed_until_its_corpse_exits() {
    rig.lane.start(argv())
    tryCompare(rig.lane, "busy", false, 500)
    compare(rig.lane.start(argv()), false)
    rig.proc.finish(143)
    compare(rig.outcomes.length, 1)
    compare(rig.lane.ready, true)
    compare(rig.lane.start(argv()), true)
  }

  function test_a_corpse_exit_never_becomes_the_next_runs_result() {
    rig.lane.start(argv())
    tryCompare(rig.lane, "busy", false, 500)
    rig.out.text = "stale\n"
    rig.proc.finish(0)
    compare(rig.outcomes.length, 1)

    rig.lane.start(argv())
    rig.out.text = "fresh\n"
    rig.proc.finish(0)
    compare(rig.outcomes.length, 2)
    compare(rig.outcomes[1].stdout, "fresh\n")
    compare(rig.outcomes[1].runId, 3)
  }

  function test_stdin_is_written_then_closed_when_the_process_starts() {
    rig.lane.start(argv(), "{\"ok\":true}")
    var wrote = rig.log.indexOf("write:{\"ok\":true}\n")
    var closed = rig.log.indexOf("stdin:false")
    verify(wrote >= 0, "the payload must reach stdin")
    verify(closed > wrote, "stdinEnabled = false must follow write for EOF")
    compare(rig.log[0], "stdin:true")
  }

  function test_a_run_without_stdin_never_opens_the_channel() {
    rig.lane.start(argv())
    compare(rig.proc.stdinEnabled, false)
    compare(rig.log.length, 0)
  }

  function test_an_accepted_run_clears_the_stall_mark() {
    rig.lane.start(argv())
    tryCompare(rig.lane, "busy", false, 500)
    compare(rig.lane.stalled, true)
    rig.proc.finish(143)
    compare(rig.lane.stalled, false)

    rig.lane.start(argv())
    tryCompare(rig.lane, "busy", false, 500)
    compare(rig.lane.stalled, true)
    rig.lane.clearStall()
    compare(rig.lane.stalled, false)
  }
}
