import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Headless. Samples the shell's own CPU on a timer, keeps a rolling
// "lean baseline", and runs the on-demand disable/re-enable audit that
// attributes cost to individual third-party plugins. BarWidget.qml reads
// this service's state via bar.shell.serviceFor(pluginId) and never talks
// to /proc or the omarchy CLI directly itself.
Item {
  id: root
  property var shell: null

  readonly property string helperDir: Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "")
  readonly property string samplerPath: helperDir + "/plugin-tax-sample"
  readonly property string auditPath: helperDir + "/plugin-tax-audit"

  // Continuous idle-glance tuning.
  readonly property real sampleIntervalSec: 1.2
  readonly property int pollMs: 20000
  readonly property real alertThresholdPct: 8
  readonly property int sustainSamples: 2
  readonly property int historyWindowMs: 30 * 60 * 1000
  readonly property int historyMaxLen: 120

  // Audit tuning.
  readonly property real auditSampleIntervalSec: 1.5
  readonly property real auditFlagThresholdPct: 3

  property var history: []
  readonly property bool alerting: Model.isAlerting(history, alertThresholdPct, sustainSamples)
  readonly property string pillText: Model.formatPill(history, alerting)
  readonly property string tooltip: Model.tooltipText(history, alerting)

  property bool auditing: false
  property var auditResults: []
  property double auditRanAt: 0
  readonly property string auditSummary: Model.summarize(auditResults)

  // Plugins this session has disabled via the panel's per-row button —
  // purely for the UI to grey the row out; the omarchy CLI is the source
  // of truth for actual enabled state.
  property var disabledIds: []

  function sample() {
    if (sampleProc.running) return
    sampleProc.command = [root.samplerPath, String(root.sampleIntervalSec)]
    sampleProc.running = true
  }

  function runAudit() {
    if (root.auditing || auditProc.running) return
    root.auditing = true
    auditProc.command = [root.auditPath, String(root.auditSampleIntervalSec)]
    auditProc.running = true
  }

  function disablePlugin(id) {
    if (!id) return
    disableProc.command = ["omarchy", "plugin", "disable", id]
    disableProc.running = true
    var next = root.disabledIds.slice()
    if (next.indexOf(id) < 0) next.push(id)
    root.disabledIds = next
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    // Skip the periodic sample while an audit owns the sampler — an audit
    // is already toggling plugins and reading CPU far more precisely than
    // this idle poll would in the middle of it.
    onTriggered: if (!root.auditing) root.sample()
  }

  Process {
    id: sampleProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseSample(text)
        if (!parsed || typeof parsed.cpuPct !== "number") return
        root.history = Model.pushSample(
          root.history,
          { t: Date.now(), cpuPct: parsed.cpuPct },
          root.historyWindowMs,
          root.historyMaxLen
        )
      }
    }
  }

  Process {
    id: auditProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.auditResults = Model.rankAudit(Model.parseAudit(text), root.auditFlagThresholdPct)
        root.auditRanAt = Date.now()
        root.auditing = false
        // The audit already disabled/re-enabled everything it touched — a
        // fresh audit run starts clean, so per-row "disabled by me" state
        // from a previous run no longer applies.
        root.disabledIds = []
      }
    }
    onExited: if (root.auditing) root.auditing = false
  }

  Process {
    id: disableProc
    stdout: StdioCollector { waitForEnd: true }
  }
}
