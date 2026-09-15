# omakeylight

Turns the desktop behind your windows into a soft key light for video calls.

Your webcam sits above the monitor, so the monitor is the biggest light source
pointed at your face. This plugin paints a full-screen warm-white layer that
sits **above the wallpaper and below every window** — you get lit, and your
browser, terminal, and call window all stay usable on top of it. The light
fills whatever part of the screen you are not currently covering.

The surface has an empty input region, so clicks, scrolls, and drags pass
straight through to whatever is underneath. It is only ever something to look
at, never something to hit.

## Install

```bash
omarchy plugin add https://github.com/edmooredop/omakeylight.git
omarchy plugin enable io.github.edmooredop.omakeylight
```

Plugins land disabled so you can read the code before enabling it. The bulb
appears on the right of the bar; click it to open the panel.

No external dependencies, no installer, no system packages, no sudo. The
plugin is QML and runs inside the Omarchy shell that is already running.

## Remove

```bash
omarchy plugin remove io.github.edmooredop.omakeylight
```

That removes the plugin and its bar entry. Settings live inside the widget's
own entry in `~/.config/omarchy/shell.json` and go with it; nothing else in
your configuration is touched.

## Using it

Click the bulb in the bar to open the panel:

| Control | Range | What it does |
| --- | --- | --- |
| Toggle | on/off | Light on or off |
| Temperature | 2000–6500K | Candlelight through to daylight |
| Brightness | 5–100% | How hard it drives |
| Coverage | 25–100% | How far down the screen it reaches, from the top |
| Falloff | 0–100% | How far the dim side drops. 0 is an even panel; 100 fades to black |
| Blend size | 5–200% | How much screen width the transition takes |
| Blend centre | 0–100% | Where the middle of the transition sits |
| Light from | left/right | Which side stays bright |
| Treat all monitors as one source | on/off | Multi-monitor only. Run the falloff once across the whole arrangement (on) or once per monitor (off) |

Coverage measures **down from the top of the screen**, because a camera above
the monitor wants light on your face rather than on your desk. Drop it to
60–70% and you get a light bar across the top with the rest of the screen
left alone.

### Shaping the light

A flat panel of white lights your face evenly and reads as flat. Real light
comes from somewhere and falls away, which is what gives a face depth. The
falloff controls simulate that across the width of the screen.

- **Falloff** is how deep the shadow side goes. Around 40–60% gives you
  noticeable modelling while keeping detail on the dim side; 100% takes it all
  the way to black for a hard key-and-shadow look.
- **Blend size** is how abruptly it happens. Small values give a defined edge
  (harder, more dramatic); large values give a long gentle wash, which is
  usually what flatters a face.
- **Blend centre** slides the transition left or right, so you can put the
  bright half where your face actually sits rather than always at the middle.
- **Light from** flips which side is lit.

A reasonable starting point for a soft key: falloff ~50%, blend size ~120%,
centre ~50%, lit from whichever side your room's real light comes from — the
two agreeing looks natural, fighting each other does not.

The curve is a smoothstep rather than a straight line, so there is no visible
start or stop to the blend, just light falling away.

### More than one monitor

With two or more monitors attached the plugin treats them as **one light**
by default: the falloff runs once across the whole arrangement, and each
monitor paints its own slice of it. Put the bright side on the left, and the
left monitor is lit while the right one falls away — a continuous ramp across
the bezel, rather than two copies of the same gradient side by side.

The slice is worked out from the compositor's layout, so it follows whatever
`hyprctl monitors` says: unequal widths, an ultrawide beside a laptop panel,
a monitor to the left of the primary at negative x. Monitors stacked
vertically share the same horizontal slice. Plugging a monitor in or out
re-splits the light live.

The falloff preview in the panel becomes the whole arrangement when this is
on, with a dark line marking each bezel, so "blend centre 50%" can be read
against the real hardware.

Switch it off with **Treat all monitors as one source** at the bottom of the panel
(only shown when there is more than one), or `omarchy-shell keylight
setSpanMonitors false`, and each monitor gets the full ramp independently.

Shortcuts on the bar icon itself:

- **Left click** — open the panel
- **Right click** — toggle the light without opening anything
- **Scroll** — warmer / cooler on the fly, mid-call

### Starting points

- **4300K at 80%** — neutral, the default. Good on most skin tones.
- **3000–3500K at 70%** — warmer, flattering, pairs well with a warm room lamp.
- **5000K+** — matches daylight from a window so your face isn't two colours.

Brightness is applied in linear light rather than straight sRGB, so 50% looks
like half as bright instead of the much darker result you get from halving the
raw byte value.

## Keybindings

The service exposes an IPC target, so anything can be bound in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "L", "exec", "omarchy-shell keylight toggle")
o.bind("SUPER SHIFT", "bracketleft",  "exec", "omarchy-shell keylight warmer")
o.bind("SUPER SHIFT", "bracketright", "exec", "omarchy-shell keylight cooler")
```

Full method list:

| Call | Effect |
| --- | --- |
| `omarchy-shell keylight toggle` | Flip on/off |
| `omarchy-shell keylight on` / `off` | Explicit state |
| `omarchy-shell keylight warmer` / `cooler` | Step temperature by 50K |
| `omarchy-shell keylight brighter` / `dimmer` | Step brightness by 5% |
| `omarchy-shell keylight setTemperature 3200` | Set kelvin directly |
| `omarchy-shell keylight setBrightness 75` | Set brightness directly |
| `omarchy-shell keylight setCoverage 60` | Set coverage directly |
| `omarchy-shell keylight setFalloff 50` | Set falloff depth (0 disables it) |
| `omarchy-shell keylight setFalloffSize 120` | Set blend size |
| `omarchy-shell keylight setFalloffCenter 40` | Set blend centre |
| `omarchy-shell keylight setFalloffDirection right` | Set the bright side |
| `omarchy-shell keylight flipFalloff` | Swap which side is lit |
| `omarchy-shell keylight setSpanMonitors false` | Each monitor gets its own full ramp (default `true`: one light across all) |
| `omarchy-shell keylight toggleSpanMonitors` | Flip the above |
| `omarchy-shell keylight status` | Current state as JSON |

Every route clamps to the supported range, so a bad value is corrected rather
than rejected.

## Settings

State lives in the widget's `shell.json` entry and survives restarts:

```json
{
  "id": "io.github.edmooredop.omakeylight",
  "on": true,
  "kelvin": 4300,
  "brightness": 80,
  "coverage": 100,
  "falloffDepth": 50,
  "falloffSize": 120,
  "falloffCenter": 50,
  "falloffDirection": "left",
  "spanMonitors": true
}
```

Hand edits are picked up live. Anything out of range or malformed is clamped
to a sane value on read.

## Layout

| File | Role |
| --- | --- |
| `Service.qml` | The light: one layer-shell surface per monitor, plus IPC |
| `BarWidget.qml` | Bar button; owns the `shell.json` entry |
| `Panel.qml` | The dropdown: swatch, switch, three sliders |
| `Model.js` | Colour maths and settings normalisation, no QML types |

The service owns live values and pixels; the widget owns persistence. Anything
that mutates the light — panel slider or keybinding over IPC — funnels through
the widget's `persist()`, so what you leave it on is what you get back.

## Development

```sh
node --test tests/model.test.js
omarchy plugin validate .
```

`Model.js` is deliberately free of QML imports so the colour maths is testable
under plain Node. Saving any file here hot-reloads the plugin; if a change
doesn't land, force it with `omarchy-shell shell rescanPlugins`.

## Changelog

### 1.1.1

- Panel: the multi-monitor switch is now labelled **Treat all monitors as one
  source**. No behaviour change.

### 1.1.0

- **Multi-monitor: one light across all screens.** The falloff now runs once
  across the whole monitor arrangement by default, each monitor painting its
  own slice, so a left-lit key is bright on the left screen and falls away
  across the right one instead of every screen showing the same gradient.
  Follows the compositor layout (unequal widths, negative origins, stacked
  monitors) and re-splits live on hotplug. New `spanMonitors` setting,
  panel switch (hidden on single-monitor), and IPC `setSpanMonitors` /
  `toggleSpanMonitors`. The panel's falloff preview shows bezel markers.

### 1.0.1

- **Fix: settings reverted to their previous value on multi-monitor setups.**
  The bar mounts one widget per monitor and each one writes settings back.
  The second monitor's widget compared against a stale copy of `shell.json`,
  concluded the new value was wrong, and wrote the old one back — so a toggle
  would switch itself off again, and slider changes would not stick.
  Single-monitor machines were unaffected, which is how it shipped.
- **Perf: settings writes are now deferred and coalesced.** Each write to
  `shell.json` costs the shell a noticeable slice of GUI-thread time (every
  bar widget on every monitor re-reads its config). It used to happen
  synchronously before the light could repaint, so toggling felt laggy and
  scrolling the bar icon stuttered. Writes now trail the last change by
  300ms and a burst becomes one write. The light itself updates immediately.

### 1.0.0

- Initial release.
