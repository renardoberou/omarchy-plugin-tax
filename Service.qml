import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Headless. Samples the shell's own process tree on a timer, keeps a rolling
// "usual" baseline, and runs the on-demand audit that attributes cost to
// individual third-party plugins. BarWidget.qml reads this service's state
// via bar.shell.serviceFor(pluginId) and never talks to /proc or the
// omarchy CLI directly itself.
//
// IPC (also what tests/e2e.sh drives):
//   omarchy-shell renardoberou.plugin-tax runAudit
//   omarchy-shell renardoberou.plugin-tax status | jq
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

  // Audit tuning. One threshold, used by the verdicts AND the summary text.
  readonly property int auditRounds: 2
  readonly property real auditSampleSec: 2
  readonly property real auditSettleSec: 2
  readonly property real auditFlagThresholdPct: 3

  property var history: []
  property double quietUntil: 0
  property string sampleError: ""
  readonly property bool alerting: Model.isAlerting(history, alertThresholdPct, sustainSamples)
  readonly property string pillText: Model.formatPill(history, alerting)
  readonly property string tooltip: Model.tooltipText(history, alerting, sampleError)

  property bool auditing: false
  property var auditProgress: null
  property var auditWarnings: []
  property var auditResults: []
  property double auditRanAt: 0
  property string auditOnly: ""
  readonly property string auditSummary: Model.summarize(auditResults, auditFlagThresholdPct)
  readonly property string progressText: Model.progressText(auditProgress)

  // One-off message for the panel, e.g. "Re-enabled X after an interrupted audit."
  property string notice: ""

  // Plugins turned off from this panel (persisted by the audit script with
  // their bar placement, so Re-enable puts them back exactly).
  property var disabledIds: []
  property var pendingIds: []

  function sample() {
    if (sampleProc.running) return
    // Same metric as the audit: Omarchy's own tooling is left out, so the
    // pill doesn't jump to hundreds of percent every time a first-party
    // plugin refreshes (e.g. agent usage checks launching codex).
    sampleProc.command = [root.samplerPath, "--interval", String(root.sampleIntervalSec), "--ignore-first-party"]
    sampleProc.running = true
  }

  function runAudit(onlyId) {
    if (root.auditing || auditProc.running) return false
    root.auditing = true
    root.auditOnly = onlyId || ""
    root.auditProgress = null
    root.auditWarnings = []
    var cmd = [root.auditPath,
      "--rounds", String(root.auditRounds),
      "--sample", String(root.auditSampleSec),
      "--settle", String(root.auditSettleSec)]
    if (root.auditOnly) cmd.push("--only", root.auditOnly)
    auditProc.command = cmd
    auditProc.running = true
    return true
  }

  // ---- panel Disable / Re-enable, strictly one CLI call at a time --------
  // v0.1 reused a single Process, so a second click replaced the first
  // command before it ran.
  property var ctlQueue: []

  function enqueue(args, id) {
    if (root.pendingIds.indexOf(id) >= 0) return
    root.pendingIds = root.pendingIds.concat([id])
    root.ctlQueue = root.ctlQueue.concat([[root.auditPath].concat(args)])
    pumpCtl()
  }

  function pumpCtl() {
    if (ctlProc.running || !root.ctlQueue.length) return
    ctlProc.command = root.ctlQueue[0]
    root.ctlQueue = root.ctlQueue.slice(1)
    ctlProc.running = true
  }

  function disablePlugin(id) { if (id) enqueue(["--disable", id], id) }
  function reenablePlugin(id) { if (id) enqueue(["--reenable", id], id) }

  function dropPending(id) {
    root.pendingIds = root.pendingIds.filter(function(p) { return p !== id })
  }

  function handleCtlLine(line) {
    var d = Model.parseAuditLine(line)
    if (!d) return
    if (d.type === "disabled") {
      if (root.disabledIds.indexOf(d.id) < 0) root.disabledIds = root.disabledIds.concat([d.id])
      dropPending(d.id)
    } else if (d.type === "reenabled") {
      root.disabledIds = root.disabledIds.filter(function(x) { return x !== d.id })
      dropPending(d.id)
    } else if (d.type === "error") {
      root.notice = d.message
    }
  }

  function handleAuditLine(line) {
    var d = Model.parseAuditLine(line)
    if (!d) return
    if (d.type === "start") {
      root.auditProgress = { index: 0, total: d.total, name: "", etaSec: d.etaSec }
    } else if (d.type === "progress") {
      root.auditProgress = d
    } else if (d.type === "warning") {
      root.auditWarnings = root.auditWarnings.concat([d.message])
    } else if (d.type === "recovered") {
      root.notice = d.message
    } else if (d.type === "error") {
      root.notice = "Audit failed: " + d.message
    } else if (d.type === "result") {
      root.auditResults = root.auditOnly
        ? Model.mergeResults(root.auditResults, d.results, root.auditFlagThresholdPct)
        : Model.rankAudit(d.results, root.auditFlagThresholdPct)
      root.auditRanAt = d.ranAt || Date.now()
    }
  }

  function handleStartupLine(line) {
    var d = Model.parseAuditLine(line)
    if (!d) return
    if (d.type === "recovered") root.notice = d.message
    else if (d.type === "warning") root.notice = d.message
    else if (d.type === "status") {
      root.disabledIds = d.disabled || []
      if (d.last && root.auditResults.length === 0) {
        root.auditResults = Model.rankAudit(Model.parseAudit(JSON.stringify(d.last)), root.auditFlagThresholdPct)
        root.auditRanAt = d.last.ranAt || 0
      }
    }
  }

  function statusJson() {
    var last = root.history.length ? root.history[root.history.length - 1] : null
    return JSON.stringify({
      auditing: root.auditing,
      progress: root.auditProgress,
      warnings: root.auditWarnings,
      notice: root.notice,
      sample: last,
      sampleError: root.sampleError,
      disabled: root.disabledIds,
      ranAt: root.auditRanAt,
      results: root.auditResults.map(function(r) {
        return { id: r.id, verdict: r.verdict, costPct: r.costPct, deltaPct: r.deltaPct,
                 spreadPct: r.spreadPct, helperPct: r.helperPct, on: r.on, off: r.off }
      })
    })
  }

  // Put back anything a crashed audit left disabled, and load the last audit
  // and the Disabled list, before the first sample.
  Component.onCompleted: {
    // The shell itself is busy for a few seconds while it starts; the first
    // pill sample would otherwise always show a scary startup spike.
    root.quietUntil = Date.now() + 10000
    startupProc.command = [root.auditPath, "--startup"]
    startupProc.running = true
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    // Skip the periodic sample while an audit owns the sampler.
    onTriggered: if (!root.auditing && Date.now() >= root.quietUntil) root.sample()
  }

  Process {
    id: sampleProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseSample(text)
        if (!parsed) {
          root.sampleError = Model.sampleError(text) || "no output"
          return
        }
        root.sampleError = ""
        parsed.t = Date.now()
        root.history = Model.pushSample(root.history, parsed, root.historyWindowMs, root.historyMaxLen)
      }
    }
  }

  Process {
    id: auditProc
    stdout: SplitParser { onRead: function(line) { root.handleAuditLine(line) } }
    onExited: function(exitCode, exitStatus) {
      root.auditing = false
      root.auditProgress = null
      // The audit's last config write still has the shell busy for a few
      // seconds; skip the pill's next sample rather than record that.
      root.quietUntil = Date.now() + root.pollMs
    }
  }

  Process {
    id: startupProc
    stdout: SplitParser { onRead: function(line) { root.handleStartupLine(line) } }
  }

  Process {
    id: ctlProc
    stdout: SplitParser { onRead: function(line) { root.handleCtlLine(line) } }
    onExited: function(exitCode, exitStatus) {
      // A crashed call must not leave its row stuck in "pending".
      var cmd = ctlProc.command || []
      root.dropPending(String(cmd[cmd.length - 1] || ""))
      Qt.callLater(root.pumpCtl)
    }
  }

  IpcHandler {
    target: "renardoberou.plugin-tax"
    function runAudit(): string { return root.runAudit("") ? "started" : "already running" }
    function runAuditOnly(id: string): string { return root.runAudit(id) ? "started" : "already running" }
    function status(): string { return root.statusJson() }
  }
}
