# Research 5: the user-research doc, mapped

A reading of *Video Toys: User Research and Product Opportunities* (a qualitative synthesis
of VJ, video-synthesis and creative-coding communities) against what is built. The doc's
product opportunity — a visual groovebox between a preset visualizer and a node environment,
centred on feedback, particles, modulation and audio reactivity, playable with a mouse or
MIDI, taking cameras and user media, recording cleanly, routing natively — is close to a
description of this toy. The gaps are where to go next.

## The ten most-wanted features, scored

| # | Wanted | Have | Gap |
| --- | --- | --- | --- |
| 1 | Immediate payoff: presets, randomize / mutate, undo, panic, no tutorial | banks + crossfade, Surprise me, evolve, undo / redo, panic, tour, demo shapes | lock the parts you like and vary the rest |
| 2 | First-class feedback engine | zoom / twist / fade / drift / warp mesh / stretch, keyers, layer blends, monitor recursion, RD | which layers re-enter the loop, frame-delay taps, blur / sharpen / colour drift inside the loop, displacement |
| 3 | Modulation without patching | learn table: MIDI, pads, OSC, audio bands, gesture loops, clock | **LFO / envelope / random / S&H with a depth beside the control** → built (this research's first item) |
| 4 | Better audio reactivity | bass / mid / high / level bands, beat, MIDI clock | per-band attack / release / smoothing, BPM tracking from audio, Link |
| 5 | Flexible media inputs | camera, images, SVG, ogv video, text, words, sounds | screen capture, mp4 / mov, depth / body tracking |
| 6 | Artist-friendly particles | 12k GPU field, attractors, curl noise, icon-shaped, artist verbs | emitters from an image / the webcam silhouette, audio-reactive forces |
| 7 | Presets and controlled variation | banks, crossfade, morph param, rig files | thumbnails, parameter locks, constrained mutation |
| 8 | Native recording | offline Movie Maker clip (frame-exact, WAV), burned-in screenshots | mp4, canvas formats (9:16, 1:1), seamless exact-length loop, live one-click record |
| 9 | Interoperability | Syphon, MIDI in, OSC in / out, MIDI out via bridge | Spout / NDI (no Windows build), Link, ISF, alpha output |
| 10 | Performance visibility | fps + work, auto quality ladder, panic, blackout, crash logs, safe mode | per-effect cost, frame-time history, warnings before costly settings, a soak test |

## The camps

- **Explorers** (the birthday, guests): served. Surprise me, guest mode, the tour, undo.
- **Performers** (Knobcon): served, with the hardware play-test still owed.
- **Analog-feedback artists**: the loop is real (recursion, warp, RD), but routing is thin — item 2.
- **Loop makers / musicians**: served worst. AVI only, fixed 16:9, no seamless loop — item 8.
- **Modular builders / live coders**: out of scope by design; verbs-as-files and scenes-as-shaders are the escape hatch.

## Build order

1. **Modulators into the learn table** — built: `~` per param row, seven shapes, depth, rate,
   centre from the knob, saved with the map.
2. **Lock and mutate** — built: Ctrl+L panel with eight section locks that Surprise and evolve
   respect, Ctrl+M / a param for the amount (one nearby nudge to six wild changes), persisted,
   in the HUD, as actions.
3. **Feedback routing** — built: per-layer in / out of the loop (out = composited over it), a
   frame-delay tap up to 23 frames through a half-res history ring, blur / sharpen, hue and
   saturation drift and displacement (self / layer 2 / layer 3 / webcam) inside the warp pass;
   Ctrl+F panel, params and actions, snapshot + crossfade, panic.
4. **Loop-maker export** — built: 16:9 / 9:16 / 1:1 as a centre crop with an on-stage guide
   (Ctrl+E), the child renders at the crop's window size, "Render the loop" is the timeline
   loop's exact length after a pre-roll, and with ffmpeg the parent makes an mp4 — seamless
   for loops (xfade of the head from the post-end frames) — or leaves a script otherwise.
5. **Audio shaping**: attack / release / smoothing per band, BPM from audio.
6. **Windows and Linux exports**: cheap in Godot; Syphon needs a Spout twin.
7. Small: preset thumbnails, per-effect cost in the HUD, a soak test in CI, mp4 playback,
   particle emitters from an image.
