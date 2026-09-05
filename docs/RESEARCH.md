# Research: video toys, effects, and where this goes next

Written 2026-09-05 as the roadmap for Video Toy. The icon core (search → toolbox → verbs
→ palettes → feedback) is built; everything below is what to layer on, roughly in order.

## 1. Existing video toys worth stealing from

| Toy | The one idea to take |
| --- | --- |
| **Lumen** (Mac, Paracosm) | Semi-modular video synth: every parameter is a knob, everything can be patched to an LFO or audio. The "verb" model here is the same idea with fewer wires. |
| **Vsynth** (Max/MSP, Kevin Kripper) | Analog video synth as modules: oscillators (ramps), colourisers, feedback, keyers. The canonical block list for section 3. |
| **LZX / Vidiot** hardware | Video *feedback* and *keying* as the core aesthetic. Also: Knobcon crowd will recognise it. |
| **Hydra** (Olivia Jack, browser) | Live-coded chains: `osc().kaleid().modulate(noise()).out()`. The chain of small functions is a good mental model for stacking verbs and shaders. |
| **Resolume / VDMX / TouchDesigner** | Clip launching + effect stacks + MIDI mapping. For Knobcon the takeaway is MIDI-learn on every parameter (Godot has `InputEventMIDI`). |
| **Milkdrop / projectM** | Per-frame equations driving a feedback warp mesh. Its "warp + decay + zoom" is exactly the feedback loop already in stage_screen.gd. |
| **Electric Sheep**, **Nested** feedback demos | Recursion as content, not as decoration. |
| **Pico-8 / Tweetcarts** | Tiny procedural loops. Good for the raster phase. |
| **Wii Photo Channel, Jackbox, Vib-Ribbon** | Toy-grade UI: one screen, giant type, no menus during play. |

Design takeaways: one screen while playing; every parameter reachable by a key or a knob;
the toy should look good idle (feedback + a few orbiting icons is already a screensaver).

## 2. Feedback recursion ("camera pointed at its own screen")

What's built: two accumulation SubViewports ping-pong. Each frame the active one draws the
*other* one's last frame (zoomed, rotated, faded) and then the live world on top. Because
the world and accumulators are transparent, the trail's alpha decays as `fade^n`.

Extensions, cheapest first:

- **Offset + mirror** — add translation and negative scale on the "prev" sprite. Mirroring
  gives kaleidoscope-ish symmetry for free.
- **Hue drift** — a tiny shader on the prev sprite that rotates hue each pass
  (`hue += 0.01`), the classic rainbow tunnel.
- **Warp mesh** — replace the prev sprite with a `MeshInstance2D` grid whose UVs are
  displaced per vertex each frame (Milkdrop's trick). Sine-based UV displacement in a
  canvas shader does the same with less code.
- **Virtual monitor in the scene** — put a Sprite2D *inside the world* whose texture is the
  accumulator, framed as a TV. Icons fly across the TV that shows the TV. This is the
  literal "point the camera at the screen" recursion and needs no new machinery: the
  ping-pong already breaks the same-frame cycle.
- **3D monitor** — same sprite as a texture on a quad in a 3D SubViewport with a camera
  you can orbit. The recursion tilts and perspective-shrinks like a real camera.
- **Decay per channel** — different fade for R, G, B gives coloured ghosting.

Watch for: fade ≥ 0.99 saturates to solid colour; clamp it. Zoom < 1 pulls trails inward
(tunnel), > 1 pushes outward (explosion). Rotation near 0.02 rad with zoom 1.04 is the
sweet spot that already ships as default.

## 3. Video effects algorithms (the shader phase)

All of these are canvas_item shaders on a full-screen `ColorRect` or on the accumulator
sprite, so they compose with feedback.

**Colour**
- Palette quantisation: nearest colour in the active `Palettes` ring (send the ring as a
  uniform array). Turns any frame into the palette. Also solves "palette sets" for raster.
- Posterise, threshold, invert, hue rotate, channel swap.
- Chroma key: `distance(color.rgb, key.rgb) < tol → alpha 0`. The Chroma Green/Blue palettes
  exist so OBS can key the toy; doing it in-shader lets the toy key *itself* over a feed.

**Space**
- Kaleidoscope: polar coords, `angle = mod(angle, 2π/n)`, mirror every other wedge.
- Tunnel / zoom blur: sample along the ray to centre.
- Pixelate: `floor(uv * n) / n`. The bridge to the raster phase.
- Displacement: offset uv by a noise texture; drive the noise offset with time.
- Slit-scan: keep the last N frames in a texture array and read row `y` from frame `y % N`.

**Analog-video look**
- Scanlines + barrel distortion (CRT).
- Chromatic aberration: sample R, G, B at slightly different uv offsets.
- VHS: horizontal jitter per line from noise, colour bleed via a small horizontal blur on
  chroma only (convert to YIQ, blur I and Q).
- Sync roll: `uv.y += fract(time * speed)`.

**Time**
- Frame difference (`abs(cur - prev)`) — with the accumulator already holding `prev`, this
  is one line and gives motion-only outlines.
- Datamosh-lite: only update pixels where the difference exceeds a threshold.

**Implementation order:** pixelate → palette quantise → kaleidoscope → chroma key → CRT.
Each is under 30 lines and each shows up on stream immediately.

## 4. Shader art

Shadertoy-style fragment shaders as *sources* rather than filters: plasma
(`sin(x + t) + sin(y + t) + sin(x + y + t)`), domain-warped fbm noise, raymarched SDF
scenes, truchet tiles, Voronoi. In Godot: `ColorRect` + `shader_type canvas_item`, uniforms
for time, palette ring, and one or two knobs. A "Shader" slot type in the toolbox could hold
a shader instead of an icon — then verbs like Pulse and Rainbow map onto its uniforms.

Icons as inputs to shader art: the white SVG texture is a perfect **mask** / SDF seed.
Distance-transform the icon once (CPU, on download) and shaders can outline, glow, wobble
the edge, or morph between two icons by lerping SDFs.

## 5. 3D shapes with icons as textures

Godot 3D is available in the same SubViewport pipeline (`disable_3d = false` on a second
world viewport, composite it over the 2D world):

- `MeshInstance3D` with `BoxMesh` / `SphereMesh` / `TorusMesh` / `PrismMesh` /
  `CylinderMesh`, `StandardMaterial3D` with the icon texture in `albedo_texture` and
  `transparency = ALPHA`, `cull_mode = DISABLED` so the back face shows through.
- Unlit (`shading_mode = UNSHADED`) keeps the flat-icon look; lit gives cheap depth.
- Verbs map straight across: Spin → `rotate_y`, Orbit → around the origin, Pulse → scale,
  Bounce → box bounds in 3D.
- A **cube with six different toolbox icons** is a strong birthday/stream visual.
- Camera: `Camera3D` on a slow orbit; the feedback accumulator then feeds back the 3D
  render too, which is where it starts looking like a real video synth.

Texture note: use `IconMedia.texture_for` output (white on alpha) and set the material's
`albedo_color` from the palette, so palettes keep working in 3D.

## 6. Raster (later)

- Load PNG/JPG/GIF frames from `user://raster/` and from drag-and-drop
  (`get_window().files_dropped`).
- Camera in: Godot 4 has `CameraServer` on macOS; feeding a webcam frame into the world
  makes the feedback loop a *real* camera-at-monitor loop, which was the original ask.
- Pixel-art mode: pixelate shader + palette quantise + nearest filtering, plus a small
  fixed canvas (320×180) rendered up to 1080p.
- Palette extraction from an image (k-means on a downscaled copy) to make a palette set
  from any raster asset, so the palette list can grow from content.

## 7. Palette sets

Built: seven named sets in `src/palettes.gd` (Knobcon, Birthday, VHS, Cream, Mono, Chroma
Green, Chroma Blue). Next: a `user://palettes.json` so sets are editable in-app; a palette
picker in the menu; the quantise shader above; extraction from raster.

## 8. Streaming / Knobcon specifics

- **H** hides the HUD for a clean capture; **Chroma** palettes exist for OBS keying.
- Window at 1920×1080 with `canvas_items` stretch; go borderless fullscreen with
  `DisplayServer.window_set_mode` for a projector.
- MIDI: `InputEventMIDI` in `_input`; map CC to fade/zoom/twist and notes to spawn. A
  MIDI-learn ("press knob, wiggle control") is ~40 lines and is the Knobcon feature.
- Audio-reactive: `AudioEffectSpectrumAnalyzer` on the mic bus; drive Pulse from bass.
- Attribution: the ledger + Attribution screen covers CC BY on stream; also export
  `user://attribution.json` as a text block for the VOD description (one button).
