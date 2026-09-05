# Research 2: more modes, particles, geometry

Written 2026-09-05, after everything in [RESEARCH.md](RESEARCH.md) shipped. Scoped against what
the toy already has: a 1920×1080 world with 2D actors, a 3D solids viewport, ping-pong
feedback, a post-process shader chain, the in-scene monitor, MIDI-learn with audio bands as
virtual controllers, raster slots, webcam, palettes. "Cost" is a gut estimate in the same
units as the phases already built (S = an hour, M = a session, L = a couple of sessions).

Each idea says what it plugs into, because the toy's strength is that everything composes:
anything drawn into the world gets feedback, effects, the monitor and MIDI for free.

---

## 1. More toys to steal from

| Toy | The one idea to take | Where it lands here |
| --- | --- | --- |
| [Synesthesia](https://synesthesia.live/) | *Scenes*: a scene is a shader + a fixed set of named controls, audio-mapped by default. Browsable, switchable live. | §2 Scenes mode |
| [VS – Visual Synthesizer 2](https://apps.apple.com/us/app/-/id6749264228) | Layers with *blend modes* and per-layer MIDI/audio; a "playable" visual instrument. | §2 Layers, §6 blend modes |
| [Lumen](https://lumen-app.com/) | Everything is an oscillator: ramps, sines and noise as *sources*, colourised through the palette. Syphon/camera as input. | §2 Oscillator sources |
| Vsynth (Max) | Video *keyers* beyond chroma: luma key, difference key, edge key. | §6 Keyers |
| [Electric Sheep](https://electricsheep.org/) | Fractal flames as evolving content; *voting* as the interaction. | §5 Flames, §2 Evolve mode |
| Milkdrop / projectM | Per-frame equations on a *warp mesh* under feedback; presets crossfade. | §6 Warp mesh, §2 Presets |
| Jeff Minter (Llamasoft) | Overdriven particle *everything*, tunnel and grid geometry, camera that never stops moving. | §3, §4 |
| Wii Photo Channel "Fun!" | Mosaic, puzzle, doodle *on the photo*. Toy-grade; kids get it instantly. | §2 Mosaic |
| Boids / flocks ([topic](https://github.com/topics/boids?l=javascript)) | Separation, alignment, cohesion; click attracts, right-click scatters. | §3 Flock verb |
| Reaction–diffusion, flow fields | Continuous fields the icons ride on. | §4 Fields |
| [Google Experiments](https://experiments.withgoogle.com/search?q=webgl) | One-mechanic toys: draw a line, it becomes a thing. | §2 Draw mode |

---

## 2. Modes (start-screen or stage-level)

The start screen is a mode picker already. These are the modes worth adding, best first.

### Scenes (M)
A **scene** = shader source + named uniforms + default audio/MIDI map, in `res://scenes/*.gdshader`
with a sidecar JSON. Browsable from a Scenes screen (thumbnails rendered once at startup into a
grid), switched live with a key, crossfaded (two ColorRects, lerp alpha). Plugs into the world as a
layer behind actors (like the webcam), so icons still fly over it and feedback still wraps it.
First five scenes: plasma (exists in fx as the chroma fallback), domain-warped fbm, truchet
tiles, Voronoi cells, raymarched SDF blob. Each ~40 lines of shader.

### Layers (M)
Right now there is one world. A **layer stack** is the VS/Resolume model: N worlds, each with
its own actors, blend mode (add / multiply / screen / difference) and opacity, composited in
order. Costs one SubViewport per layer plus a compositing shader. Payoff: difference-blend of a
layer against itself one frame late is a motion detector; add-blend of two feedback worlds with
opposite twist is the classic two-oscillator video synth look. Keys: Tab cycles the active layer.

### Draw (S–M)
Left-drag paints a **polyline** in the world; the selected icon then *rides* it (a Path2D +
PathFollow2D per drawn line, actors attached). Draw a circle, get an orbit you designed. Draw a
zigzag, get a bouncing marquee. Clear with C like everything else. The line itself can render
(palette accent, 4 px) or stay invisible.

### Mosaic (S)
Tile the selected raster with the toolbox icons: quantise the image to a coarse grid (say 48×27),
place the icon whose slot colour is nearest each cell's colour, scaled by cell luminance. One pass
of CPU code at "steal" time, then ordinary actors. It reads as a photo made of the toolbox, and
verbs still apply, so the mosaic can explode (Bounce) and reform (Orbit around home).

### Text (S)
A toolbox slot that is a **word**. Rasterise with `Font.draw_string` into an ImageTexture at add
time (white on alpha, exactly like an icon) and everything else already works: verbs, palettes,
solids (a spinning cube of your name), MIDI. Birthday use is obvious. Input: a LineEdit in the
search screen's inspect panel, "Add text".

### Evolve (M)
Electric-Sheep interaction: the toy mutates the current setup every N beats (random verb toggles,
palette drift, fx step ±1, feedback twist nudge) and the audience votes with two keys/pads: keep
or discard. Keep = commit the mutation; discard = revert. Over a stream this converges on what
the room likes. Implementation is a Dictionary snapshot of stage state and a mutate() that touches
one field.

### Presets / Snapshots (S)
Save the entire stage state (toolbox verbs, palette, fx, feedback, monitor, layers) as a numbered
preset; keys F1–F12 recall, Shift+F saves. Crossfade feedback params over a second. This is the
one that makes a live set possible and should probably come first.

### Oscillator sources (S)
Lumen's primitives as world layers: horizontal/vertical/radial **ramps**, sines and noise,
colourised through the palette ring (`ring_color(t)` already exists in fx.gdshader). Speed and
frequency as learnable params. On their own they are boring; under feedback + kaleido they are
the entire genre.

### Attract (S)
An **idle mode** that runs when nothing has been touched for 60 s: random preset every 20 s,
palette drift, slow camera orbit on solids, monitor on. It is a screensaver, and it is also the
demo that runs on the Knobcon table when you step away.

---

## 3. Particle effects

Godot 4's GPUParticles2D/3D got attractors, collision and sub-emitters in 4.0
([release notes](https://godotengine.org/article/improvements-gpuparticles-godot-40/),
[sub-emitters doc](https://docs.godotengine.org/en/4.4/tutorials/3d/particles/subemitters.html)).
The current Sparkle verb is a CPUParticles2D puff. Everything below is GPU.

### Icon-shaped particles (S)
The particle texture is the *icon itself*. `GPUParticles2D.texture = IconMedia.texture_for(...)`,
tinted by the palette, 200–2000 of them. A Sparkle that emits tiny copies of the icon is
immediately better than dots. Sub-verb of Sparkle, or a new verb **Confetti**.

### Trails (S)
`ParticleProcessMaterial` with `trail_enabled` and a `RibbonTrailMesh`/`TubeTrailMesh` in 3D, or
in 2D simply a long lifetime with `scale` curve to zero: comet tails behind Bounce and Orbit
actors. Colour ramp = palette ring. Under feedback the tails of tails happen for free.

### Attractors (M)
`GPUParticlesAttractorSphere2D`/`3D` at the **mouse** (swarm the cursor) and at every **actor**
(particles orbit the icons). Negative strength = repel: a pad bound to "scatter" flips the sign
for a beat. This is where audio-reactive strength shines: bind attractor strength to bass.

### Collision (M)
`GPUParticlesCollisionSphere2D` on actors so a particle field *splashes* off bouncing icons. In 3D,
`GPUParticlesCollisionSDF3D` baked once around the solids for particles that pour over cubes.

### Sub-emitters: fireworks (S)
Particle A rises, dies, spawns particle B burst (icon-shaped, palette-coloured). Bind "fire" to a
pad or the beat. It is a birthday feature; it's also the demo of sub-emitters.

### Particle field as a *source* (M)
A GPUParticles2D with 20k tiny dots on a slow noise field (`ParticleProcessMaterial.turbulence`),
as a world layer behind actors. Turbulence is built in since 4.0. With feedback on, this is the
"stars" / "snow" / "plankton" background every VJ set has.

### Audio-driven emission (S)
`amount_ratio` (4.2+) bound to level; `explosiveness` on beat. Emission that *breathes* with the
music without any binding UI: default when audio is on.

### Fluid-ish (L)
Not true fluid, but a 2D **curl-noise velocity field** in a texture, updated in a shader each
frame, that particles sample (`ParticleProcessMaterial` can't read a custom texture, so this uses a
custom particle shader — Godot 4 supports `shader_type particles`). Icons could ride the same
field (§4). This is the one L-sized particle item and it unlocks the "smoke" look.

---

## 4. Geometry and motion (2D)

### Flock verb (S)
Boids: separation, alignment, cohesion over all actors from the same slot (there are never more
than a few hundred; O(n²) is fine at that size). Click attracts, right-click scatters — the
established interaction. Reuses `mouse_world` from Swarm.

### Fields (M)
A **flow field** (Perlin/curl noise, or the reaction–diffusion output below) that Wander samples
instead of picking random targets. Visualise it optionally as short palette-coloured strokes
(one `MultiMeshInstance2D`, 60×34 quads rotated to the field). Time-varying noise makes the whole
stage slosh.

### Reaction–diffusion (M)
Gray–Scott in a ping-pong SubViewport pair (the same trick as feedback, two 480×270 buffers, one
15-line shader). Feed the icons in as the seed (draw the world texture into the U channel at low
alpha) and the pattern grows out of the icons. Output as a world layer, palette-mapped through
`ring_color`. It is the most "alive" texture available for the cost.

### Tunnels and grids (S–M)
Llamasoft geometry: a **polar grid** (concentric rings + spokes) and a **perspective floor grid**
drawn with `draw_line` in a Node2D, scrolling with time, colour from the palette. Under CRT and
feedback it is the '80s look. Icons can be placed *on* the grid (Orbit around the vanishing point).

### Mirrors / tiling (S)
The kaleidoscope is post-process. A **tiled world** is different: render the world into an N×M
grid of Sprite2Ds with alternate flips. Cheap (it is N×M draws of one texture), and it makes one
bouncing icon into a wallpaper. Key: T is taken (Pulse); use Shift+O.

### Strange attractors (S)
Lorenz / Rössler / Clifford / de Jong as **verbs**: the actor integrates the ODE each frame and
its position is the projected state. Clifford and de Jong are 2D and gorgeous with trails on.
Four lines of math each; the whole set is one afternoon.

### Springs and ropes (S)
Verlet chain between successive spawns of the same slot: spawn six hearts, they hang from each
other, Bounce shakes the chain. Pairs with Draw mode (attach the chain to a drawn line).

---

## 5. Geometry (3D)

### More primitives and extrusions (S)
`TextMesh` (a 3D word, see Text mode), `CapsuleMesh`, `PlaneMesh` billboards, and an **extruded
icon**: trace the icon's alpha with `Image` marching squares → `Geometry2D.triangulate_polygon` →
`SurfaceTool` extrude. The icon becomes a thick 3D cookie. M-sized, but it is the strongest 3D
item: it turns the Noun Project into a 3D asset library.

### Instancing (S)
`MultiMeshInstance3D` for 500 copies of a solid in a lattice / helix / sphere shell, all wearing
the icon; a spinning helix of hearts is one MultiMesh and one loop. Per-instance colour from the
palette ring.

### Camera as a verb target (S)
The 3D camera on a slow orbit, dolly, or roll, bindable to MIDI (`cam_orbit`, `cam_dolly`,
`cam_roll` params). Right now the camera is static; a moving camera is most of what makes 3D
read as 3D on video.

### Fractal flames (L)
Electric Sheep's engine: iterated function systems with nonlinear variations, accumulated into a
histogram, log-density tone mapped. A compute shader (Godot 4 supports `RenderingDevice`
compute) with 1M points per frame is feasible; 64k points per frame in a `shader_type particles`
that never dies is the cheap version and already looks like flames. Palette = the flame palette.

### Environment (S)
A `WorldEnvironment` with glow and a subtle fog on the solids viewport; glow on the *composite*
(a second post-process pass) is the single most flattering effect for icons on a dark bg and is
about six lines (`Environment.glow_enabled` on the composite SubViewport with a 2D-capable
environment, or a bloom pass in fx.gdshader).

### Lighting rig (S)
Two coloured `OmniLight3D`s from the palette ring, orbiting the solids. The body meshes are lit
already; coloured lights make the palette show up in the shading, not just the skin.

---

## 6. Post-process additions

- **Keyers** (S): luma key (key on brightness), difference key (against the previous frame,
  available from the accumulator), edge key (Sobel then threshold). Each is ~10 lines next to
  chroma in `chain()`.
- **Blend modes for the feedback "prev" sprite** (S): `CanvasItemMaterial.blend_mode` ADD /
  SUB / MUL on the accumulator's prev sprite. Additive feedback bloom is a one-line change and a
  whole new look.
- **Warp mesh** (M): replace the prev sprite with a `MeshInstance2D` 32×18 grid whose UVs are
  displaced per vertex each frame by an equation (Milkdrop's `zoom`, `rot`, `dx`, `dy`, `warp`
  per-vertex). Learnable params. This is the *actual* Milkdrop feedback and it composes with
  everything.
- **Slit-scan** (M): a ring buffer of the last 64 composite frames in a `Texture2DArray`
  (copy each frame with `RenderingDevice.texture_copy`), sample row y from frame `y % 64`.
  Time-smear on video is the effect nothing else here does.
- **Datamosh-lite** (S): only update pixels whose difference from prev exceeds a threshold;
  otherwise keep prev. Blocky, sticky motion. Uses the accumulator already present.
- **Glow / bloom** (S): see §5 Environment; threshold + blur + add, in the fx shader.
- **Halftone / Ben-Day dots** (S): dot size from luminance on a rotated grid; pairs with Cream
  palette and quantise for a print look.
- **Wobble / VHS tracking** (S): per-line horizontal offset from noise, chroma bleed (blur only
  the IQ channels). The CRT pass has the frame; this is the tape.

---

## 7. Interaction and performance

- **Presets first** (§2) — nothing else here is usable in a set without recall.
- **Gamepad**: `InputEventJoypad*` into the same learn table as MIDI (sticks = params, buttons =
  actions). Cheap, and the Knobcon crowd has controllers too.
- **OSC** over UDP (`PacketPeerUDP`, OSC is a trivial binary format): TouchOSC / Max / Bitwig
  drive params by name. M-sized and worth it for the stream rig.
- **NDI / Syphon out**: not in Godot core. The practical route is OBS window capture (works
  today) or a `Spout`/`Syphon` GDExtension if one exists for 4.7 — check before promising.
- **Timeline** (M): record param changes for 60 s and loop them (a LFO you performed). Godot's
  `AnimationPlayer` can hold it: record into an Animation, play it back looped.
- **Two-player**: a second toolbox/hotbar on keys F1–F9 vs 1–9; two people at one keyboard at
  the table. Mostly UI.

---

## 8. Suggested next three phases

1. **Presets + Glow + Icon-shaped particles** (all S) — the biggest visual and practical
   upgrade for the least work, and each is independent.
2. **Scenes mode + Oscillator sources + Warp mesh** — turns the toy into a proper video synth.
3. **Extruded icons + Camera verbs + Instancing** — the 3D half grows into an asset library.

Text slots and Flock are S-sized "when there's an hour" items that both pay off at a birthday.
