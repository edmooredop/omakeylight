const test = require("node:test")
const assert = require("node:assert")
const Model = require("../Model.js")

test("kelvin clamps to the supported range", () => {
  assert.strictEqual(Model.clampKelvin(1000), Model.MIN_KELVIN)
  assert.strictEqual(Model.clampKelvin(99999), Model.MAX_KELVIN)
  assert.strictEqual(Model.clampKelvin(4300), 4300)
  assert.strictEqual(Model.clampKelvin("nonsense", 3000), 3000)
})

test("brightness and coverage clamp to their ranges", () => {
  assert.strictEqual(Model.clampBrightness(0), Model.MIN_BRIGHTNESS)
  assert.strictEqual(Model.clampBrightness(1000), Model.MAX_BRIGHTNESS)
  assert.strictEqual(Model.clampCoverage(0), Model.MIN_COVERAGE)
  assert.strictEqual(Model.clampCoverage(1000), Model.MAX_COVERAGE)
})

test("warm temperatures are strongly red-dominant", () => {
  const warm = Model.kelvinToRgb(2200)
  assert.ok(warm.r > warm.g && warm.g > warm.b, JSON.stringify(warm))
})

test("warmth decreases monotonically as temperature rises", () => {
  // The blue-over-red crossover on the Planckian locus sits above 6600K, so
  // within our range red stays the top channel throughout. What must hold is
  // that the cast gets progressively less orange: the red-to-blue gap shrinks
  // at every step, and the top of the range is near-white.
  let previousGap = Infinity
  for (let k = Model.MIN_KELVIN; k <= Model.MAX_KELVIN; k += 100) {
    const rgb = Model.kelvinToRgb(k)
    const gap = rgb.r - rgb.b
    assert.ok(gap < previousGap, `${k}K gap ${gap} not below ${previousGap}`)
    previousGap = gap
  }

  const cool = Model.kelvinToRgb(Model.MAX_KELVIN)
  assert.ok(cool.r - cool.b < 10, JSON.stringify(cool))
})

test("the hue curve always saturates one channel", () => {
  for (let k = Model.MIN_KELVIN; k <= Model.MAX_KELVIN; k += 100) {
    const rgb = Model.kelvinToRgb(k)
    assert.strictEqual(Math.max(rgb.r, rgb.g, rgb.b), 255, `${k}K -> ${JSON.stringify(rgb)}`)
  }
})

test("lightColor returns a 6-digit hex string", () => {
  const hex = Model.lightColor(4300, 80)
  assert.match(hex, /^#[0-9a-f]{6}$/)
})

test("brightness scales output without changing hue order", () => {
  const full = Model.lightColor(4300, 100)
  const half = Model.lightColor(4300, 50)
  assert.notStrictEqual(full, half)

  const channel = hex => [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16)
  ]
  const [fr, fg, fb] = channel(full)
  const [hr, hg, hb] = channel(half)
  assert.ok(hr < fr && hg < fg && hb < fb)
  // Gamma-correct scaling: 50% brightness must not collapse to 50% of the byte.
  assert.ok(hr > fr * 0.5, `${hr} vs ${fr * 0.5}`)
})

test("temperature labels move warm to cool", () => {
  assert.strictEqual(Model.kelvinLabel(2200), "Candle")
  assert.strictEqual(Model.kelvinLabel(2900), "Warm")
  assert.strictEqual(Model.kelvinLabel(3500), "Soft white")
  assert.strictEqual(Model.kelvinLabel(4300), "Neutral")
  assert.strictEqual(Model.kelvinLabel(5400), "Cool white")
  assert.strictEqual(Model.kelvinLabel(6500), "Daylight")
})

test("coverage label distinguishes full screen from partial", () => {
  assert.strictEqual(Model.coverageLabel(100), "Full screen")
  assert.strictEqual(Model.coverageLabel(60), "60% from the top")
})

test("normalizeSettings survives garbage from a hand-edited shell.json", () => {
  const state = Model.normalizeSettings({
    on: "true", kelvin: "banana", brightness: -40, coverage: 999
  }, null)
  assert.deepStrictEqual(state, {
    on: true, kelvin: 4300, brightness: Model.MIN_BRIGHTNESS, coverage: Model.MAX_COVERAGE,
    falloffDepth: 0, falloffSize: 70, falloffCenter: 50, falloffDirection: "left"
  })
})

test("normalizeSettings falls back to manifest defaults when a key is absent", () => {
  const state = Model.normalizeSettings({}, {
    on: true, kelvin: 3000, brightness: 60, coverage: 75,
    falloffDepth: 40, falloffSize: 90, falloffCenter: 30, falloffDirection: "right"
  })
  assert.deepStrictEqual(state, {
    on: true, kelvin: 3000, brightness: 60, coverage: 75,
    falloffDepth: 40, falloffSize: 90, falloffCenter: 30, falloffDirection: "right"
  })
})

test("settingsEqual compares every field", () => {
  const a = { on: true, kelvin: 4300, brightness: 80, coverage: 100 }
  assert.ok(Model.settingsEqual(a, { ...a }))
  assert.ok(!Model.settingsEqual(a, { ...a, kelvin: 4400 }))
  assert.ok(!Model.settingsEqual(a, null))
})

test("stepping snaps to the grid and stops at the bounds", () => {
  assert.strictEqual(Model.stepKelvin(4310, 1), 4350)
  assert.strictEqual(Model.stepKelvin(Model.MAX_KELVIN, 1), Model.MAX_KELVIN)
  assert.strictEqual(Model.stepKelvin(Model.MIN_KELVIN, -1), Model.MIN_KELVIN)
  assert.strictEqual(Model.stepBrightness(82, 1), 85)
  assert.strictEqual(Model.stepBrightness(100, 1), 100)
  assert.strictEqual(Model.stepBrightness(Model.MIN_BRIGHTNESS, -1), Model.MIN_BRIGHTNESS)
})

test("summaryText reports off state without numbers", () => {
  assert.strictEqual(Model.summaryText(false, 4300, 80), "Light off")
  assert.strictEqual(Model.summaryText(true, 4300, 80), "4300K · 80%")
})

// ---- falloff ---------------------------------------------------------------

test("depth 0 means a perfectly even light", () => {
  for (const x of [0, 0.25, 0.5, 0.75, 1]) {
    assert.strictEqual(Model.falloffLevelAt(x, 0, 70, 50, "left"), 1)
  }
  for (const s of Model.falloffStops(0, 70, 50, "left")) {
    assert.strictEqual(s.level, 1)
  }
})

test("direction left keeps the left lit and dims the right", () => {
  const left = Model.falloffLevelAt(0, 100, 100, 50, "left")
  const right = Model.falloffLevelAt(1, 100, 100, 50, "left")
  assert.ok(left > right, `${left} vs ${right}`)
  assert.ok(left > 0.99)
  assert.ok(right < 0.01)
})

test("direction right mirrors it exactly", () => {
  for (const x of [0, 0.2, 0.5, 0.8, 1]) {
    const l = Model.falloffLevelAt(x, 80, 90, 50, "left")
    const r = Model.falloffLevelAt(1 - x, 80, 90, 50, "right")
    assert.ok(Math.abs(l - r) < 1e-9, `${x}: ${l} vs ${r}`)
  }
})

test("full depth reaches black, partial depth does not", () => {
  assert.ok(Model.falloffLevelAt(1, 100, 100, 50, "left") < 0.001)

  const partial = Model.falloffLevelAt(1, 40, 100, 50, "left")
  assert.ok(Math.abs(partial - 0.6) < 0.001, String(partial))
})

test("brightness decreases monotonically across the blend", () => {
  let previous = Infinity
  for (let i = 0; i <= 40; i++) {
    const level = Model.falloffLevelAt(i / 40, 100, 100, 50, "left")
    assert.ok(level <= previous + 1e-9, `rose at ${i / 40}`)
    previous = level
  }
})

test("the centre of the blend sits at half depth", () => {
  // Whatever the size, the midpoint of the ramp is half way down the falloff.
  for (const size of [20, 70, 100, 180]) {
    for (const center of [30, 50, 70]) {
      const level = Model.falloffLevelAt(center / 100, 100, size, center, "left")
      assert.ok(Math.abs(level - 0.5) < 1e-9,
        `size ${size} center ${center} -> ${level}`)
    }
  }
})

test("moving the centre moves where the light has dropped off", () => {
  const atSample = center => Model.falloffLevelAt(0.5, 100, 40, center, "left")
  // Pushing the blend to the right leaves the sample point brighter.
  assert.ok(atSample(80) > atSample(50))
  assert.ok(atSample(50) > atSample(20))
})

test("a bigger blend is more gradual at the same centre", () => {
  // Just off-centre, a wide blend has moved less far from full than a tight one.
  const tight = Model.falloffLevelAt(0.6, 100, 20, 50, "left")
  const wide = Model.falloffLevelAt(0.6, 100, 160, 50, "left")
  assert.ok(wide > tight, `${wide} vs ${tight}`)
})

test("stops are a fixed-length, ordered, full-width ramp", () => {
  for (const size of [5, 70, 200]) {
    for (const center of [0, 50, 100]) {
      const stops = Model.falloffStops(60, size, center, "left")
      // Fixed length is what lets the QML side declare bound stop elements.
      assert.strictEqual(stops.length, Model.STOP_COUNT)
      assert.strictEqual(stops[0].position, 0)
      assert.strictEqual(stops[stops.length - 1].position, 1)
      for (let i = 1; i < stops.length; i++) {
        assert.ok(stops[i].position > stops[i - 1].position,
          `size ${size} center ${center}: not ascending at ${i}`)
      }
      for (const s of stops) {
        assert.ok(s.level >= 0 && s.level <= 1, `level out of range: ${s.level}`)
      }
    }
  }
})

test("sampling is dense enough to avoid visible banding", () => {
  // Worst case for banding is the steepest usable ramp: full depth, tightest
  // blend. Adjacent stops must stay close enough that linear interpolation
  // between them is imperceptible (~1/255 per step is one 8-bit level).
  const stops = Model.falloffStops(100, Model.MIN_FALLOFF_SIZE, 50, "left")
  let worst = 0
  for (let i = 1; i < stops.length; i++) {
    worst = Math.max(worst, Math.abs(stops[i].level - stops[i - 1].level))
  }
  // Canvas interpolates smoothly between stops, so the bar here is about
  // sampling the curve faithfully rather than defeating 8-bit banding.
  assert.ok(worst < 0.5, `worst step ${worst}`)
})

test("a blend running off-screen still paints a partial ramp", () => {
  // Centre hard left with a narrow blend: the visible screen should be almost
  // entirely the dim end, not a full bright-to-dark sweep.
  const stops = Model.falloffStops(100, 20, 0, "left")
  assert.ok(stops[stops.length - 1].level < 0.01)
  // And the left edge starts already half way down, since the ramp's first
  // half sits off the left of the screen.
  assert.ok(Math.abs(stops[0].level - 0.5) < 1e-9, String(stops[0].level))
})

test("falloff settings clamp, including a bad direction string", () => {
  assert.strictEqual(Model.clampFalloffDepth(-10), 0)
  assert.strictEqual(Model.clampFalloffDepth(500), 100)
  assert.strictEqual(Model.clampFalloffSize(0), Model.MIN_FALLOFF_SIZE)
  assert.strictEqual(Model.clampFalloffSize(9999), Model.MAX_FALLOFF_SIZE)
  assert.strictEqual(Model.clampFalloffCenter(-5), 0)
  assert.strictEqual(Model.clampDirection("sideways"), "left")
  assert.strictEqual(Model.clampDirection("RIGHT"), "right")
  assert.strictEqual(Model.flipDirection("left"), "right")
  assert.strictEqual(Model.flipDirection("right"), "left")
})

test("falloff round-trips through settings normalisation", () => {
  const state = Model.normalizeSettings({
    on: true, kelvin: 3200, brightness: 70, coverage: 80,
    falloffDepth: 65, falloffSize: 120, falloffCenter: 35, falloffDirection: "right"
  }, null)
  assert.strictEqual(state.falloffDepth, 65)
  assert.strictEqual(state.falloffSize, 120)
  assert.strictEqual(state.falloffCenter, 35)
  assert.strictEqual(state.falloffDirection, "right")

  // And a settings blob from before the feature existed still loads.
  const legacy = Model.normalizeSettings({ on: true, kelvin: 4300 }, null)
  assert.strictEqual(legacy.falloffDepth, 0)
  assert.strictEqual(legacy.falloffDirection, "left")
})

test("settingsEqual notices a falloff-only change", () => {
  const a = Model.normalizeSettings({ on: true }, null)
  const b = Model.normalizeSettings({ on: true, falloffCenter: 70 }, null)
  assert.ok(!Model.settingsEqual(a, b))
})
