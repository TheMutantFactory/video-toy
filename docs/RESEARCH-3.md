# Research 3: what to build next

Written 2026-09-05, after everything in [RESEARCH.md](RESEARCH.md) and [RESEARCH-2.md](RESEARCH-2.md)
shipped (see the README for the full control map). The toy now has more features than any one
show will use, so this round is organised by the three real occasions — **the birthday**, **the
Knobcon table**, **streams and VODs** — plus the engineering that makes those safe. Costs as
before: S = an hour, M = a session, L = a couple of sessions.

The honest headline: the biggest risk is no longer missing features, it is that **the mic, the
camera, real MIDI and a real gamepad have only ever been exercised synthetically**. Item 1 is a
play-test, not code.

---

## 1. Before anything else: the hardware play-test (no code)

Plug in a MIDI controller, a gamepad, a microphone or interface, and a camera on a laptop, and
run through this list. Every line is a path the test suite covers with fakes only.

- `;` panel lists the MIDI device and the pad. Learn a knob, a pad, a stick, a button.
- `A` to mic: the HUD meter moves with the room. Pulse follows bass. Beat bursts fire.
- `Z` webcam layer: live, correct colours (RGB vs YCbCr path). Point it at the screen: feedback.
- `S` on the webcam: palette steal from a real frame.
- Player 2 on the gamepad while player 1 is on keyboard and mouse.
- Ten minutes of everything on at once, watching the frame rate (see §2).
- macOS permission prompts for mic and camera appear once and are remembered.

Whatever breaks here outranks everything below.

---

## 2. Show-hardening (Knobcon and streams)

### Performance budget and auto-quality (M)
There is no frame-rate readout. Add one to the HUD, and a **quality ladder**: when the frame
time exceeds 20 ms for a second, step down — particle count 12k → 6k → 3k, reaction-diffusion
every other frame, slit-scan atlas to 4×4, glow taps halved, world viewports to 1600×900 — and
step back up when there is headroom. Godot's `Engine.get_frames_per_second()` and
`Performance.get_monitor()` give the numbers. Also an explicit `--quality low|high` flag.

### Panic and safety keys (S)
One key that returns to a known-good look (all effects off, feedback off, particles off, scene
off, glow soft) without touching the toolbox. Escape is the menu; use `Shift+Esc`. And a
**blackout** key for between songs. Both learnable, both bindable to a pad.

### Set list: preset banks with a crossfade of everything (M)
Presets crossfade feedback numbers only. A set list wants: **12 presets × N banks**, a crossfade
time, and an interpolation of every continuous value (glow, warp, camera, scene knobs, layer
opacity, key threshold) with discrete values switching at the midpoint. Plus **next / previous
preset** actions (a foot switch), and a **preset morph** param: a knob that scrubs between the
current preset and the next one. This is the feature that turns the toy into an instrument for a
set rather than a toy for a table.

### MIDI clock and transport (M)
Evolve and the timeline run on their own clocks. Read MIDI clock (24 ppqn, `MIDI_MESSAGE_TIMING_CLOCK`)
and start/stop, and let evolve mutate on bars, the timeline loop quantise to bars, and the
oscillator scenes' `speed` lock to BPM. Knobcon is a room full of clocks.

### Controller templates (S each)
The param and action tables are data; generate controller layouts from them. **TouchOSC**: a
`.tosc` (zipped XML) with a fader per param and a button per action addressed as `/vt/param/<id>`,
so a phone is a full surface with zero learning. **Launchpad / APC**: a default `midi.json` mapping
the pad grid to slots, verbs and presets. Ship them in `docs/controllers/`.

### Output to the video world (M, platform-specific)
OBS window capture works today. For a real rig: **Syphon** on macOS and **Spout** on Windows
share the GPU texture directly; there are GDExtensions for both
([godot-syphon](https://github.com/topics/syphon?o=desc&s=updated),
[spout-gd](https://github.com/you-win/spout-gd), [godot-spout](https://github.com/buresu/godot-spout)),
and [Godot NDI](https://godotengine.org/asset-library/asset/3753) sends the viewport over the
network with an `NDIOutput` node. Native support is a
[proposal](https://github.com/godotengine/godot-proposals/issues/13143), not a feature. Pick
Syphon for the Mac rig; make the composite viewport the source so the HUD never leaks.

### Crash safety (S)
Autosave the stage snapshot every 30 s to `user://autosave.json`; on launch, offer to restore.
The toolbox and bindings already persist; this covers the live state.

---

## 3. For streams and VODs: capture and credits

### Attribution burned in (S)
A `Shift+F12`-style **screenshot** that saves the composite plus a small attribution strip at the
bottom listing every icon on stage (from the ledger). CC BY on a thumbnail, solved.

### Credits export (S)
One button in the Attribution screen: copy the ledger as a text block to the clipboard and write
`user://credits.txt` — the VOD description. Also a **credits roll**: an end-card mode that scrolls
the ledger over the last preset, for the end of a stream.

### Clip export (M)
Godot's **Movie Maker** mode (`--write-movie out.avi` with a fixed frame rate) renders offline
at full quality; wire a "render the timeline loop to a file" action around it so a 20-second loop
becomes a clip. GIF is a stretch (no encoder in core; write frames and shell out to ffmpeg if it
is installed).

### ASCII / text-mode output (S)
Render the composite to a grid of characters (a shader that picks a glyph by luminance from a
small atlas) — a chat-friendly look and a fun stream mode. Pairs with palette quantise.

---

## 4. For the birthday: content and party modes

### Any SVG, any font, emoji (S)
Drop an `.svg` and it is whitened like a Noun icon (the loader already exists); drop a `.ttf` and
text slots use it; the fallback font may not have emoji — bundle an emoji-capable font so "🎂" is
a slot.

### Word lists and countdown (S)
Drop a `.txt` and each line becomes a text slot (up to nine) — or a single **cycling** slot that
changes word on the beat. A **countdown** / **clock** text slot for midnight.

### Video slots (M)
A `.ogv` dropped on the window becomes an animated raster slot: `VideoStreamPlayer` into a small
viewport, its texture as the slot's texture. Godot only decodes Theora; the README can give the
one-line ffmpeg conversion. GIFs likewise via conversion.

### Piñata / burst (S)
Click an icon with the Sparkle verb on and it bursts into confetti of itself and disappears; a
pad does the same to a random one. Bounce + Piñata + a room of kids.

### Guest mode on phones (L, with caveats)
Godot's web export uses only the Compatibility renderer (WebGL 2); Forward+ is not available in
the browser and SubViewport-heavy scenes are known to perform badly there
([docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html),
[forum](https://forum.godotengine.org/t/subviewport-rendering-performances-on-web/101434)). A
phone version would be a cut-down scene (icons, verbs, palettes, one feedback pass, no 3D, no
particles) — and the Noun Project API cannot be called from a browser page without a proxy.
Cheaper: keep the toy on the laptop and let phones drive it over OSC via the TouchOSC template.

---

## 5. Deeper effects (any occasion)

- **Icon SDFs** (M): distance-transform each icon on download. Then: outlines, soft glow that
  follows the shape, and a **Morph** verb that lerps between two slots' SDFs — a star that
  becomes a heart on the beat. The single most "wow" new verb available.
- **Smooth extrusion** (M): marching squares on the alpha → `Geometry2D.triangulate_polygon`
  with holes bridged → real bevelled cookies instead of columns.
- **Halftone / risograph** (S): dot-size-by-luminance on a rotated grid, two-ink misregistration,
  paper grain; pairs with the Cream palette.
- **Motion blur / datamosh** (S): both fall out of the accumulator already present.
- **Shadows and lights** (S): two orbiting `OmniLight3D`s in palette colours over the solids.
- **LED wall** (S): pixelate + a dot mask + bloom = a fake LED wall, very Knobcon.

---

## 6. Engineering (makes the rest cheaper)

- **Split the stage** (M): `stage_screen.gd` is past 2,000 lines. Extract `FxRig` (glow, fx,
  slit, keyers, RD), `Feedback`, `Layers`, `Players`, `Controls` (params/actions tables) as
  child nodes with the stage as coordinator. Same behaviour, testable pieces.
- **Verbs as files** (S): `res://verbs/*.gd` auto-discovered, each with `key`, `hint`, and a
  `step(actor, delta)`; new verbs without touching actor.gd.
- **Rig files** (S): one `.zip` of toolbox + icons + presets + bindings + palettes + timeline —
  a shareable, restorable rig. "Send me your Knobcon rig."
- **Headless render test** (S): `--capture` already proves screens; add a pixel-diff against
  stored reference PNGs for a handful of shots so a shader regression fails CI.

---

## 7. Suggested order

1. **Hardware play-test** (§1) — a day with real gear; fix what it finds.
2. **Show-hardening** (§2): frame-rate + auto-quality, panic/blackout, preset banks with full
   crossfade. These three make a set safe.
3. **Credits export + burned-in attribution** (§3) — small, and it is the CC BY promise kept.
4. **Icon SDFs + Morph** (§5) — the next big visual.
5. **Syphon out + MIDI clock** (§2) once the rig is known.
6. Birthday extras (§4) the week before.
