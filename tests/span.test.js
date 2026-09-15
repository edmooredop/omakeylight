const test = require("node:test")
const assert = require("node:assert")
const Model = require("../Model.js")

// ---- multi-monitor span ----------------------------------------------------

// A 4K laptop panel at x=0 with a 4K external to its right. Layout
// coordinates are post-scale (both at scale 2), so 1920 wide each.
const twoWide = [{ x: 0, width: 1920 }, { x: 1920, width: 1920 }]

test("a single monitor always gets the full span", () => {
  assert.deepStrictEqual(Model.screenSpan([{ x: 0, width: 1920 }], { x: 0, width: 1920 }), { from: 0, to: 1 })
  assert.deepStrictEqual(Model.screenSpan([], { x: 0, width: 1920 }), { from: 0, to: 1 })
  assert.deepStrictEqual(Model.screenSpan(twoWide, null), { from: 0, to: 1 })
  assert.deepStrictEqual(Model.screenSeams([{ x: 0, width: 1920 }]), [])
})

test("two equal monitors side by side split the span in half", () => {
  assert.deepStrictEqual(Model.screenSpan(twoWide, twoWide[0]), { from: 0, to: 0.5 })
  assert.deepStrictEqual(Model.screenSpan(twoWide, twoWide[1]), { from: 0.5, to: 1 })
  assert.deepStrictEqual(Model.screenSeams(twoWide), [0.5])
})

test("unequal monitors split proportionally and a negative origin is fine", () => {
  // Ultrawide to the LEFT of a laptop panel, so the layout starts at negative x.
  const rects = [{ x: -2560, width: 2560 }, { x: 0, width: 1280 }]
  const left = Model.screenSpan(rects, rects[0])
  const right = Model.screenSpan(rects, rects[1])
  assert.ok(Math.abs(left.to - 2560 / 3840) < 1e-9)
  assert.strictEqual(left.from, 0)
  assert.ok(Math.abs(right.from - 2560 / 3840) < 1e-9)
  assert.strictEqual(right.to, 1)
})

test("stacked monitors share the same horizontal slice", () => {
  const rects = [{ x: 0, width: 1920 }, { x: 0, width: 1920, y: 1080 }]
  assert.deepStrictEqual(Model.screenSpan(rects, rects[1]), { from: 0, to: 1 })
  assert.deepStrictEqual(Model.screenSeams(rects), [])
})

test("the ramp is continuous across the seam", () => {
  // The last stop of the left monitor's slice and the first stop of the right
  // monitor's slice sample the same point in the overall light.
  const args = [60, 120, 50, "left"]
  const left = Model.falloffStops(...args, undefined, 0, 0.5)
  const right = Model.falloffStops(...args, undefined, 0.5, 1)
  assert.ok(Math.abs(left[left.length - 1].level - right[0].level) < 1e-9)
  // And the two halves together reproduce the full-span ramp end to end.
  const whole = Model.falloffStops(...args)
  assert.ok(Math.abs(left[0].level - whole[0].level) < 1e-9)
  assert.ok(Math.abs(right[right.length - 1].level - whole[whole.length - 1].level) < 1e-9)
  // Positions are still 0-1 in surface space, not the sub-range.
  assert.strictEqual(right[0].position, 0)
  assert.strictEqual(right[right.length - 1].position, 1)
})

test("with the span the dim monitor is genuinely dimmer than the lit one", () => {
  const args = [100, 100, 50, "left"]
  const left = Model.falloffStops(...args, undefined, 0, 0.5)
  const right = Model.falloffStops(...args, undefined, 0.5, 1)
  const mean = stops => stops.reduce((a, s) => a + s.level, 0) / stops.length
  assert.ok(mean(left) > 0.75, String(mean(left)))
  assert.ok(mean(right) < 0.25, String(mean(right)))
  // Without the span, both monitors would paint the identical full ramp.
  const same = Model.falloffStops(...args)
  assert.ok(Math.abs(mean(same) - 0.5) < 0.05)
})

test("spanMonitors normalises like the other booleans and defaults on", () => {
  assert.strictEqual(Model.clampSpanMonitors("false"), false)
  assert.strictEqual(Model.clampSpanMonitors(false), false)
  assert.strictEqual(Model.clampSpanMonitors("nonsense"), true)
  assert.strictEqual(Model.normalizeSettings({ on: true }, null).spanMonitors, true)
  const a = Model.normalizeSettings({ on: true }, null)
  const b = Model.normalizeSettings({ on: true, spanMonitors: false }, null)
  assert.ok(!Model.settingsEqual(a, b))
})
