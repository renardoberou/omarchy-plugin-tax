// node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

test("parseSample reads the tree sampler and picks the busiest helper", () => {
  const s = M.parseSample(JSON.stringify({
    cpuPct: 19.5, shellPct: 1.5, childrenPct: 18,
    children: [{ comm: "voxtype", cpuPct: 0 }, { comm: "python3", cpuPct: 18 }]
  }))
  assert.equal(s.cpuPct, 19.5)
  assert.equal(s.shellPct, 1.5)
  assert.deepEqual(s.topChild, { comm: "python3", cpuPct: 18 })
})

test("parseSample rejects error lines; sampleError reports them", () => {
  const line = '{"error":"wrong-process","pid":1,"comm":"bash"}'
  assert.equal(M.parseSample(line), null)
  assert.equal(M.sampleError(line), "wrong-process")
  assert.equal(M.sampleError("garbage"), "")
})

test("baseline ignores one lucky zero (v0.1 used min)", () => {
  const h = [0, 3, 3, 3, 3, 3, 3, 3, 3, 3].map((c, i) => ({ t: i, cpuPct: c }))
  assert.ok(M.baselineOf(h) > 2, "baseline should sit near the usual 3%")
})

test("alerting needs sustained excess over baseline", () => {
  const h = [1, 1, 1, 1, 1, 1, 1, 1, 12].map((c, i) => ({ t: i, cpuPct: c }))
  assert.equal(M.isAlerting(h, 8, 2), false, "one spike is not an alert")
  h.push({ t: 9, cpuPct: 12 })
  assert.equal(M.isAlerting(h, 8, 2), true)
})

test("analyze: interleaved rounds, flagged when every round agrees", () => {
  const r = M.analyze({ id: "a", on: [10, 10.4, 9.8], off: [2, 2.2], onChild: [0, 0, 0] }, 3)
  assert.equal(r.verdict, "flagged")
  assert.ok(Math.abs(r.deltaPct - 8.0) < 0.3)
})

test("analyze: a big but inconsistent delta is not flagged", () => {
  // one round says 6%, the other says 0 -- that is noise, not a finding
  const r = M.analyze({ id: "a", on: [6, 0.5, 0.5], off: [0, 0.5], onChild: [] }, 3)
  assert.notEqual(r.verdict, "flagged")
})

test("analyze: small deltas are 'clean' (within noise)", () => {
  const r = M.analyze({ id: "a", on: [0.5, 1.0, 0.5], off: [0.0, 0.5], onChild: [0, 0, 0] }, 3)
  assert.equal(r.verdict, "clean")
})

test("analyze: helper-process CPU flags on its own (the Help daemon case)", () => {
  // Toggle deltas can miss a daemon (it may be reaped during the settle gap);
  // the directly measured helper cost must still flag it.
  const r = M.analyze({ id: "renardoberou.help", on: [18, 18, 18], off: [18, 18], onChild: [17.8, 18.1, 17.9] }, 3)
  assert.equal(r.verdict, "flagged")
  assert.ok(r.costPct > 17)
})

test("analyze: v0.1-style row with no rounds is 'unmeasured', not 'clean'", () => {
  assert.equal(M.analyze({ id: "a", on: [], off: [] }, 3).verdict, "unmeasured")
})

test("rankAudit orders by cost and mergeResults replaces a re-tested row", () => {
  const ranked = M.rankAudit([
    { id: "low", on: [1, 1], off: [1], onChild: [] },
    { id: "high", on: [9, 9], off: [1], onChild: [] }
  ], 3)
  assert.deepEqual(ranked.map(r => r.id), ["high", "low"])
  const merged = M.mergeResults(ranked, [{ id: "low", on: [20, 20], off: [1], onChild: [] }], 3)
  assert.deepEqual(merged.map(r => r.id), ["low", "high"])
})

test("summarize uses the configured threshold, not a hard-coded 3%", () => {
  const ranked = M.rankAudit([{ id: "a", on: [4, 4], off: [0], onChild: [] }], 5)
  assert.match(M.summarize(ranked, 5), /under 5%/)
})

test("parseAudit accepts v0.2 result objects and v0.1 arrays", () => {
  assert.equal(M.parseAudit('{"type":"result","results":[{"id":"a"}]}').length, 1)
  assert.equal(M.parseAudit('[{"id":"a"}]').length, 1)
  assert.deepEqual(M.parseAudit("nope"), [])
})

test("progress and eta text", () => {
  assert.equal(M.progressText({ index: 4, total: 12, name: "Honcho", etaSec: 150 }),
    "Auditing 4/12 · Honcho · ~3 min left")
  assert.equal(M.formatEta(0), "")
})
