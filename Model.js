// Pure helpers for the key light. No QML types in here so the same functions
// can be exercised by `node --test tests/model.test.js`.

// Bounds. The low end stops at candlelight and the high end at overcast
// daylight; past ~6500K a black-body emitter is blue enough to look sickly on
// skin, which is the opposite of what a key light is for.
var MIN_KELVIN = 2000
var MAX_KELVIN = 6500
var KELVIN_STEP = 50

var MIN_BRIGHTNESS = 5
var MAX_BRIGHTNESS = 100

var MIN_COVERAGE = 25
var MAX_COVERAGE = 100

// Falloff. `depth` is how far the dim end drops (100 = all the way to black),
// `size` is how much of the screen width the blend occupies, and `center` is
// where the middle of that blend sits across the screen.
//
// Size has a floor rather than allowing 0: a hard light/dark edge down the
// middle of a monitor reads as a rendering fault, not as lighting.
var MIN_FALLOFF_DEPTH = 0
var MAX_FALLOFF_DEPTH = 100

var MIN_FALLOFF_SIZE = 5
var MAX_FALLOFF_SIZE = 200

var MIN_FALLOFF_CENTER = 0
var MAX_FALLOFF_CENTER = 100

// How many stops the gradient is sampled into.
//
// The smoothstep curve has to be approximated by straight segments between
// stops, so this trades fidelity against work per repaint. 64 keeps the
// steepest usable setting (full depth at the tightest blend) well inside a
// perceptual step, and is cheap to rebuild when a slider moves.
var STOP_COUNT = 64

function clampNumber(value, min, max, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

function clampKelvin(value, fallback) {
  return Math.round(clampNumber(value, MIN_KELVIN, MAX_KELVIN,
    fallback === undefined ? 4300 : fallback))
}

function clampBrightness(value, fallback) {
  return Math.round(clampNumber(value, MIN_BRIGHTNESS, MAX_BRIGHTNESS,
    fallback === undefined ? 80 : fallback))
}

function clampCoverage(value, fallback) {
  return Math.round(clampNumber(value, MIN_COVERAGE, MAX_COVERAGE,
    fallback === undefined ? 100 : fallback))
}

function clampFalloffDepth(value, fallback) {
  return Math.round(clampNumber(value, MIN_FALLOFF_DEPTH, MAX_FALLOFF_DEPTH,
    fallback === undefined ? 0 : fallback))
}

function clampFalloffSize(value, fallback) {
  return Math.round(clampNumber(value, MIN_FALLOFF_SIZE, MAX_FALLOFF_SIZE,
    fallback === undefined ? 70 : fallback))
}

function clampFalloffCenter(value, fallback) {
  return Math.round(clampNumber(value, MIN_FALLOFF_CENTER, MAX_FALLOFF_CENTER,
    fallback === undefined ? 50 : fallback))
}

// Which end of the screen keeps full brightness. "left" means the light source
// reads as sitting off the left of the monitor, so the right side falls away.
function clampDirection(value, fallback) {
  var v = String(value === undefined || value === null ? "" : value).toLowerCase()
  if (v === "left" || v === "right") return v
  return fallback === "right" ? "right" : "left"
}

function flipDirection(direction) {
  return clampDirection(direction) === "left" ? "right" : "left"
}

// Black-body colour for a given temperature, after Tanner Helland's
// approximation of the Planckian locus. Returns 0-255 channels.
//
// The curve is normalised so the brightest channel is always 255 — it
// describes the *hue* of the light, not its intensity. Intensity is applied
// separately by `lightColor` so brightness and temperature stay independent
// controls rather than one washing the other out.
function kelvinToRgb(kelvin) {
  var t = clampKelvin(kelvin) / 100
  var r, g, b

  if (t <= 66) {
    r = 255
    g = 99.4708025861 * Math.log(t) - 161.1195681661
    b = t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307
  } else {
    r = 329.698727446 * Math.pow(t - 60, -0.1332047592)
    g = 288.1221695283 * Math.pow(t - 60, -0.0755148492)
    b = 255
  }

  return {
    r: Math.round(clampNumber(r, 0, 255, 0)),
    g: Math.round(clampNumber(g, 0, 255, 0)),
    b: Math.round(clampNumber(b, 0, 255, 0))
  }
}

function toHexByte(value) {
  var hex = Math.round(clampNumber(value, 0, 255, 0)).toString(16)
  return hex.length === 1 ? "0" + hex : hex
}

// Final surface colour: the temperature's hue scaled by brightness.
//
// Scaling in linear light rather than straight sRGB bytes: halving the byte
// value of white looks far darker than half as bright, because sRGB is
// gamma-encoded. Decode, scale, re-encode, and the slider tracks perceived
// output closely enough that the midpoint reads as a midpoint.
function lightColor(kelvin, brightness) {
  var rgb = kelvinToRgb(kelvin)
  var scale = clampBrightness(brightness) / 100
  return "#" + toHexByte(scaleChannel(rgb.r, scale))
    + toHexByte(scaleChannel(rgb.g, scale))
    + toHexByte(scaleChannel(rgb.b, scale))
}

function scaleChannel(byteValue, scale) {
  var linear = srgbToLinear(clampNumber(byteValue, 0, 255, 0) / 255)
  return linearToSrgb(linear * clampNumber(scale, 0, 1, 1)) * 255
}

function srgbToLinear(channel) {
  return channel <= 0.04045
    ? channel / 12.92
    : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function linearToSrgb(channel) {
  return channel <= 0.0031308
    ? channel * 12.92
    : 1.055 * Math.pow(channel, 1 / 2.4) - 0.055
}

// Smooth S-curve. Real light falls off gradually and has no hard start or
// stop, so a linear ramp between two stops gives away its endpoints as faint
// banding edges. Smoothstep eases in and out at both ends instead.
function smoothstep(t) {
  var x = clampNumber(t, 0, 1, 0)
  return x * x * (3 - 2 * x)
}

// Brightness multiplier at a normalised horizontal position (0 = screen left,
// 1 = screen right), given the falloff settings.
//
// `direction` names the side that stays lit: "left" keeps the left of the
// screen at full brightness and lets the right fall away, which is what you
// want when your key light should read as coming from the left.
function falloffLevelAt(position, depth, size, center, direction) {
  var d = clampFalloffDepth(depth) / 100
  if (d <= 0) return 1

  var half = clampFalloffSize(size) / 200
  var mid = clampFalloffCenter(center) / 100
  var start = mid - half
  var end = mid + half

  var x = clampNumber(position, 0, 1, 0)
  // Mirroring the sample point rather than the ramp keeps `center` meaning the
  // same thing on screen in both directions: the midpoint of the visible blend
  // stays put when you flip the light over.
  if (clampDirection(direction) === "right") x = 1 - x

  var span = end - start
  var t = span <= 0 ? (x < start ? 0 : 1) : (x - start) / span
  return 1 - d * smoothstep(t)
}

// The gradient as QML-ready stops: `{ position, level }`, position 0-1 across
// the screen and level a 0-1 brightness multiplier.
//
// Always returns exactly `sampleCount` stops at uniform positions. A fixed
// length matters for the QML side: gradient stops have to be declared as real
// elements with bound properties to stay reactive, so the count cannot depend
// on the settings. Uniform spacing also keeps positions strictly ascending for
// any combination of size and centre, including a ramp pushed off either edge.
//
// QML interpolates linearly between stops, so enough of them are emitted that
// the straight segments are far shorter than the eye can pick out as banding.
function falloffStops(depth, size, center, direction, sampleCount) {
  var samples = Math.max(2, Math.round(Number(sampleCount) || STOP_COUNT))
  var stops = []
  for (var i = 0; i < samples; i++) {
    var position = i / (samples - 1)
    stops.push({
      position: position,
      level: falloffLevelAt(position, depth, size, center, direction)
    })
  }
  return stops
}

// Plain-language name for a temperature, so the panel says something more
// useful than a bare number while you are dragging the slider.
function kelvinLabel(kelvin) {
  var k = clampKelvin(kelvin)
  if (k < 2500) return "Candle"
  if (k < 3200) return "Warm"
  if (k < 4000) return "Soft white"
  if (k < 5000) return "Neutral"
  if (k < 5800) return "Cool white"
  return "Daylight"
}

function coverageLabel(coverage) {
  var c = clampCoverage(coverage)
  if (c >= 100) return "Full screen"
  return c + "% from the top"
}

function falloffDepthLabel(depth) {
  var d = clampFalloffDepth(depth)
  if (d <= 0) return "Off · even light"
  if (d >= 100) return "To black"
  return d + "% dimmer"
}

function falloffSizeLabel(size) {
  var s = clampFalloffSize(size)
  if (s <= 15) return "Hard edge"
  if (s >= 150) return "Very gradual"
  if (s >= 100) return "Gradual"
  return s + "% of width"
}

function falloffCenterLabel(center) {
  var c = clampFalloffCenter(center)
  if (c <= 2) return "Far left"
  if (c >= 98) return "Far right"
  if (c === 50) return "Middle"
  return c + "% across"
}

function directionLabel(direction) {
  return clampDirection(direction) === "left"
    ? "Bright left · dim right"
    : "Bright right · dim left"
}

function summaryText(on, kelvin, brightness) {
  if (!on) return "Light off"
  return clampKelvin(kelvin) + "K · " + clampBrightness(brightness) + "%"
}

// Settings arrive from shell.json, where a hand edit can put anything at all
// in any field. Normalise once, here, so nothing downstream has to re-check.
function normalizeSettings(settings, defaults) {
  var base = defaults || {}
  var raw = settings || {}
  return {
    on: raw.on === undefined || raw.on === null
      ? (base.on === true) : (raw.on === true || raw.on === "true"),
    kelvin: clampKelvin(raw.kelvin, clampKelvin(base.kelvin, 4300)),
    brightness: clampBrightness(raw.brightness, clampBrightness(base.brightness, 80)),
    coverage: clampCoverage(raw.coverage, clampCoverage(base.coverage, 100)),
    falloffDepth: clampFalloffDepth(raw.falloffDepth, clampFalloffDepth(base.falloffDepth, 0)),
    falloffSize: clampFalloffSize(raw.falloffSize, clampFalloffSize(base.falloffSize, 70)),
    falloffCenter: clampFalloffCenter(raw.falloffCenter, clampFalloffCenter(base.falloffCenter, 50)),
    falloffDirection: clampDirection(raw.falloffDirection, clampDirection(base.falloffDirection, "left"))
  }
}

function settingsEqual(a, b) {
  if (!a || !b) return false
  return a.on === b.on && a.kelvin === b.kelvin
    && a.brightness === b.brightness && a.coverage === b.coverage
    && a.falloffDepth === b.falloffDepth && a.falloffSize === b.falloffSize
    && a.falloffCenter === b.falloffCenter
    && a.falloffDirection === b.falloffDirection
}

// Step a value by whole notches, snapped to the step grid so repeated
// keybinding presses land on round numbers instead of drifting.
function stepValue(current, delta, step, min, max) {
  var snapped = Math.round(clampNumber(current, min, max, min) / step) * step
  return Math.round(clampNumber(snapped + delta * step, min, max, min))
}

function stepKelvin(current, delta) {
  return stepValue(current, delta, KELVIN_STEP, MIN_KELVIN, MAX_KELVIN)
}

function stepBrightness(current, delta) {
  return stepValue(current, delta, 5, MIN_BRIGHTNESS, MAX_BRIGHTNESS)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MIN_KELVIN: MIN_KELVIN,
    MAX_KELVIN: MAX_KELVIN,
    KELVIN_STEP: KELVIN_STEP,
    MIN_BRIGHTNESS: MIN_BRIGHTNESS,
    MAX_BRIGHTNESS: MAX_BRIGHTNESS,
    MIN_COVERAGE: MIN_COVERAGE,
    MAX_COVERAGE: MAX_COVERAGE,
    MIN_FALLOFF_DEPTH: MIN_FALLOFF_DEPTH,
    MAX_FALLOFF_DEPTH: MAX_FALLOFF_DEPTH,
    MIN_FALLOFF_SIZE: MIN_FALLOFF_SIZE,
    MAX_FALLOFF_SIZE: MAX_FALLOFF_SIZE,
    MIN_FALLOFF_CENTER: MIN_FALLOFF_CENTER,
    MAX_FALLOFF_CENTER: MAX_FALLOFF_CENTER,
    STOP_COUNT: STOP_COUNT,
    clampKelvin: clampKelvin,
    clampBrightness: clampBrightness,
    clampCoverage: clampCoverage,
    clampFalloffDepth: clampFalloffDepth,
    clampFalloffSize: clampFalloffSize,
    clampFalloffCenter: clampFalloffCenter,
    clampDirection: clampDirection,
    flipDirection: flipDirection,
    smoothstep: smoothstep,
    falloffLevelAt: falloffLevelAt,
    falloffStops: falloffStops,
    falloffDepthLabel: falloffDepthLabel,
    falloffSizeLabel: falloffSizeLabel,
    falloffCenterLabel: falloffCenterLabel,
    directionLabel: directionLabel,
    kelvinToRgb: kelvinToRgb,
    lightColor: lightColor,
    kelvinLabel: kelvinLabel,
    coverageLabel: coverageLabel,
    summaryText: summaryText,
    normalizeSettings: normalizeSettings,
    settingsEqual: settingsEqual,
    stepKelvin: stepKelvin,
    stepBrightness: stepBrightness
  }
}
