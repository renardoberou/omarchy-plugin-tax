// Pure parsing/formatting/statistics for Plugin Tax. No Process or file
// access here -- loads in Quickshell and in plain node (`node --test tests/`).

// ---- continuous idle-glance history ----

// One sampler line -> {cpuPct, shellPct, childrenPct, topChild} or null.
// Error lines ({"error": ...}) are not samples; see sampleError().
function parseSample(raw) {
  try {
    var line = String(raw || "").trim().split("\n")[0]
    var d = JSON.parse(line)
    if (!d || typeof d.cpuPct !== "number" || isNaN(d.cpuPct)) return null
    var kids = Array.isArray(d.children) ? d.children : []
    var top = null
    for (var i = 0; i < kids.length; i++) {
      if (!top || kids[i].cpuPct > top.cpuPct) top = kids[i]
    }
    return {
      cpuPct: d.cpuPct,
      shellPct: typeof d.shellPct === "number" ? d.shellPct : d.cpuPct,
      childrenPct: typeof d.childrenPct === "number" ? d.childrenPct : 0,
      topChild: top && top.cpuPct >= 0.5 ? { comm: String(top.comm || ""), cpuPct: top.cpuPct } : null
    }
  } catch (e) {
    return null
  }
}

function sampleError(raw) {
  try {
    var d = JSON.parse(String(raw || "").trim().split("\n")[0])
    return d && typeof d.error === "string" ? d.error : ""
  } catch (e) {
    return ""
  }
}

// Appends `sample` ({t, cpuPct, ...}) to `history`, drops entries older than
// `windowMs`, and caps length at `maxLen`.
function pushSample(history, sample, windowMs, maxLen) {
  var now = sample.t
  var next = (history || []).filter(function(h) { return now - h.t <= windowMs })
  next.push(sample)
  if (next.length > maxLen) next = next.slice(next.length - maxLen)
  return next
}

function percentile(values, p) {
  if (!values || !values.length) return null
  var s = values.slice().sort(function(a, b) { return a - b })
  var idx = (s.length - 1) * p
  var lo = Math.floor(idx), hi = Math.ceil(idx)
  return s[lo] + (s[hi] - s[lo]) * (idx - lo)
}

function median(values) { return percentile(values, 0.5) }

// Rolling "lean" baseline: the 20th percentile of the window. v0.1 used the
// minimum, which on an idle shell is almost always 0.0 -- so "headroom" was
// just current CPU with a plus sign. A low percentile still tracks "the
// shell at its best recently" but ignores the one lucky empty sample.
var BASELINE_PERCENTILE = 0.2

function baselineOf(history) {
  if (!history || !history.length) return null
  return percentile(history.map(function(h) { return h.cpuPct }), BASELINE_PERCENTILE)
}

function headroom(history) {
  var b = baselineOf(history)
  if (b === null || !history.length) return 0
  return Math.max(0, history[history.length - 1].cpuPct - b)
}

// Alerting requires the last `sustainCount` samples to all sit at least
// `thresholdPct` above baseline -- a single spiky sample shouldn't light up
// the bar.
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
  var latest = history[history.length - 1].cpuPct
  return (alerting ? "⚠ " : "") + latest.toFixed(0) + "%"
}

function tooltipText(history, alerting, error) {
  if (error === "wrong-process") return "Plugin Tax — not running under quickshell; can't measure"
  if (error) return "Plugin Tax — sampling failed (" + error + ")"
  if (!history || !history.length) return "Plugin Tax — sampling…"
  var s = history[history.length - 1]
  var b = baselineOf(history)
  var parts = ["Shell " + (s.shellPct !== undefined ? s.shellPct : s.cpuPct).toFixed(1) + "%"]
  if (s.childrenPct >= 0.1) {
    parts.push("helpers " + s.childrenPct.toFixed(1) + "%" +
      (s.topChild ? " (" + s.topChild.comm + ")" : ""))
  }
  parts.push("usual " + (b === null ? "—" : b.toFixed(1) + "%"))
  var base = parts.join(" · ")
  return alerting ? base + " — above usual, run an audit" : base
}

// ---- audit ----

// One audit output line -> object with a `type`, or null.
function parseAuditLine(line) {
  try {
    var d = JSON.parse(String(line || ""))
    return d && typeof d.type === "string" ? d : null
  } catch (e) {
    return null
  }
}

// v0.1 wrote a bare array; keep reading it so old last-audit files load.
function parseAudit(raw) {
  try {
    var d = JSON.parse(String(raw || ""))
    if (Array.isArray(d)) return d
    if (d && Array.isArray(d.results)) return d.results
    return []
  } catch (e) {
    return []
  }
}

// Differences smaller than this are indistinguishable from scheduler noise
// at idle with ~2s samples (1 tick at CLK_TCK=100 over 2s is 0.5%).
var NOISE_FLOOR_PCT = 1.0

// Raw per-plugin rounds -> statistics + verdict.
//   on:  [ON_0, ON_1, ... ON_R]   off: [OFF_1 ... OFF_R]
// Each OFF is compared with the mean of the ON samples on either side of
// it, which cancels slow drift and the order bias v0.1 had (one plugin's
// reload cost landing in the next plugin's "before").
function analyze(r, thresholdPct) {
  var on = r.on || [], off = r.off || []
  var deltas = []
  for (var i = 0; i < off.length; i++) {
    var a = on[i], b = on[i + 1] !== undefined ? on[i + 1] : on[i]
    if (a === undefined) continue
    deltas.push((a + b) / 2 - off[i])
  }
  var med = median(deltas)
  var lo = deltas.length ? Math.min.apply(null, deltas) : null
  var hi = deltas.length ? Math.max.apply(null, deltas) : null
  var spread = deltas.length ? hi - lo : 0
  // Helper-process CPU is measured directly (no toggling), so it is the
  // most trustworthy number here -- a daemon at 18% is 18%.
  var helper = median(r.onChild || []) || 0
  var cost = Math.max(med === null ? 0 : med, helper)

  var verdict
  if (med === null && !helper) verdict = "unmeasured"
  else if (helper >= thresholdPct) verdict = "flagged"
  else if (med >= thresholdPct && lo >= thresholdPct / 2) verdict = "flagged"
  else if (Math.abs(cost) <= Math.max(NOISE_FLOOR_PCT, spread)) verdict = "clean"
  else verdict = cost > 0 ? "minor" : "clean"

  var out = {}
  for (var k in r) out[k] = r[k]
  out.deltas = deltas
  out.deltaPct = med === null ? 0 : med
  out.spreadPct = spread
  out.helperPct = helper
  out.costPct = cost
  out.deltaRssKb = (r.onRssKb || 0) - (r.offRssKb || 0)
  out.verdict = verdict
  out.flagged = verdict === "flagged"
  return out
}

function rankAudit(results, thresholdPct) {
  return (results || []).map(function(r) {
    return r.verdict ? r : analyze(r, thresholdPct)
  }).sort(function(a, b) { return (b.costPct || 0) - (a.costPct || 0) })
}

// A single-plugin re-test replaces that plugin's row in the previous list.
function mergeResults(previous, fresh, thresholdPct) {
  var byId = {}
  ;(previous || []).forEach(function(r) { byId[r.id] = r })
  ;(fresh || []).forEach(function(r) { byId[r.id] = r })
  return rankAudit(Object.keys(byId).map(function(k) { return byId[k] }), thresholdPct)
}

function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s") }

function summarize(results, thresholdPct) {
  if (!results || !results.length) return "No plugins audited yet."
  var t = thresholdPct.toFixed(0) + "%"
  var flagged = results.filter(function(r) { return r.verdict === "flagged" })
  if (!flagged.length) return "All " + plural(results.length, "plugin") + " under " + t + " CPU at idle."
  return flagged.length + " of " + plural(results.length, "plugin") + " cost " + t + "+ CPU at idle."
}

function formatCost(r) {
  if (r.verdict === "unmeasured") return "not measured"
  var s = (r.costPct >= 0 ? "+" : "") + r.costPct.toFixed(1) + "% cpu"
  if (r.spreadPct >= 0.1 && r.verdict !== "flagged") s += " ±" + (r.spreadPct / 2).toFixed(1)
  if (r.helperPct >= 0.5) s += " · helpers " + r.helperPct.toFixed(1) + "%"
  if (r.verdict === "clean") s += " · within noise"
  return s
}

function formatEta(sec) {
  if (!(sec > 0)) return ""
  if (sec < 60) return "~" + Math.round(sec) + "s left"
  return "~" + Math.round(sec / 60) + " min left"
}

function progressText(p) {
  if (!p || !p.total) return "Auditing…"
  return "Auditing " + p.index + "/" + p.total + (p.name ? " · " + p.name : "") +
    (p.etaSec ? " · " + formatEta(p.etaSec) : "")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseSample: parseSample,
    sampleError: sampleError,
    pushSample: pushSample,
    percentile: percentile,
    median: median,
    baselineOf: baselineOf,
    headroom: headroom,
    isAlerting: isAlerting,
    formatPill: formatPill,
    tooltipText: tooltipText,
    parseAuditLine: parseAuditLine,
    parseAudit: parseAudit,
    analyze: analyze,
    rankAudit: rankAudit,
    mergeResults: mergeResults,
    summarize: summarize,
    formatCost: formatCost,
    formatEta: formatEta,
    progressText: progressText,
    NOISE_FLOOR_PCT: NOISE_FLOOR_PCT
  }
}
