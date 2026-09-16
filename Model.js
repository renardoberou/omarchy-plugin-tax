// Pure parsing/formatting logic for Plugin Tax. No Process or file access
// here — loads fine in Quickshell and in a plain node test runner.

// ---- continuous idle-glance history ----

function parseSample(raw) {
  try {
    var line = String(raw || "").trim().split("\n")[0]
    var d = JSON.parse(line)
    if (!d || typeof d.cpuPct !== "number" || isNaN(d.cpuPct)) return null
    return d
  } catch (e) {
    return null
  }
}

// Appends `sample` ({t, cpuPct}) to `history`, drops entries older than
// `windowMs`, and caps length at `maxLen` so the array can't grow unbounded
// across a long shell session.
function pushSample(history, sample, windowMs, maxLen) {
  var now = sample.t
  var next = (history || []).filter(function(h) { return now - h.t <= windowMs })
  next.push(sample)
  if (next.length > maxLen) next = next.slice(next.length - maxLen)
  return next
}

// The rolling "lean" baseline: the lowest CPU% seen inside the window.
// Simple on purpose — a percentile would resist one warm sample better, but
// min is honest about "the best this shell has looked recently" and needs
// no tuning.
function baselineOf(history) {
  if (!history || !history.length) return null
  var min = history[0].cpuPct
  for (var i = 1; i < history.length; i++) {
    if (history[i].cpuPct < min) min = history[i].cpuPct
  }
  return min
}

function headroom(history) {
  var b = baselineOf(history)
  if (b === null || !history.length) return 0
  return history[history.length - 1].cpuPct - b
}

// Alerting requires the last `sustainCount` samples to all sit at least
// `thresholdPct` above baseline — a single spiky sample (a menu opening,
// a screenshot) shouldn't light up the bar.
function isAlerting(history, thresholdPct, sustainCount) {
  if (!history || history.length < sustainCount) return false
  var b = baselineOf(history)
  if (b === null) return false
  for (var i = history.length - sustainCount; i < history.length; i++) {
    if (history[i].cpuPct - b < thresholdPct) return false
  }
  return true
}

function formatPill(history, alerting) {
  if (!history || !history.length) return "Plugin Tax"
  var h = headroom(history)
  var arrow = h > 0.5 ? "+" : ""
  return (alerting ? "⚠ " : "") + arrow + h.toFixed(0) + "%"
}

function tooltipText(history, alerting) {
  if (!history || !history.length) return "Plugin Tax — sampling…"
  var latest = history[history.length - 1].cpuPct
  var b = baselineOf(history)
  var base = "Shell CPU " + latest.toFixed(1) + "% · lean baseline " +
    (b === null ? "—" : b.toFixed(1) + "%")
  return alerting ? base + " — above baseline, run an audit" : base
}

// ---- one-shot audit results ----

function parseAudit(raw) {
  try {
    var d = JSON.parse(String(raw || ""))
    return Array.isArray(d) ? d : []
  } catch (e) {
    return []
  }
}

function rankAudit(results, thresholdPct) {
  var sorted = (results || []).slice().sort(function(a, b) {
    return (b.deltaPct || 0) - (a.deltaPct || 0)
  })
  return sorted.map(function(r) {
    var out = {}
    for (var k in r) out[k] = r[k]
    out.flagged = (r.deltaPct || 0) >= thresholdPct
    return out
  })
}

function summarize(results) {
  if (!results || !results.length) return "No plugins audited yet."
  var flagged = results.filter(function(r) { return r.flagged })
  if (!flagged.length) {
    return "All " + results.length + " plugin" + (results.length === 1 ? "" : "s") + " under 3% CPU at idle — clean."
  }
  return flagged.length + " of " + results.length + " plugin" +
    (results.length === 1 ? "" : "s") + " cost 3%+ CPU at idle."
}

if (typeof module !== "undefined") {
  module.exports = {
    parseSample: parseSample,
    pushSample: pushSample,
    baselineOf: baselineOf,
    headroom: headroom,
    isAlerting: isAlerting,
    formatPill: formatPill,
    tooltipText: tooltipText,
    parseAudit: parseAudit,
    rankAudit: rankAudit,
    summarize: summarize
  }
}
