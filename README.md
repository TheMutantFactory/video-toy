# Video Toy

A Godot 4.7 toy for streams, VODs and Knobcon: search [The Noun Project](https://thenounproject.com)
for icons, drop them into a Minecraft-style hotbar, give them **verbs** (wander, orbit, spin,
bounce, pulse, sparkle, rainbow, swarm), pick a **palette**, turn on **video feedback**, and post-process with **kaleidoscope**, **chroma key**,
**pixelate**, **palette quantise** and a **CRT** pass. Press **M** for a monitor inside the scene
that shows the scene, and watch it recurse. Press **B** for 3D solids wearing the icons.

```bash
./run.sh            # play
./run.sh test       # headless smoke tests + screen self-test (no network, no quota)
./run.sh capture    # screenshot every screen into out/
```

Needs Godot 4.7 (`GODOT=/path/to/godot` if it isn't on PATH or in /Applications).

## Modes (start screen)

| Mode | What it does |
| --- | --- |
| Find Icons | Type a word, browse free thumbnails, click to inspect the license, **Add to toolbox** (one metered download). Keep exploring: more pages, new words. |
| Play | Click to spawn the selected icon. Verbs are toggles per slot and apply live to every actor from that slot. |
| Settings | Noun Project API key/secret, saved to `user://noun_credentials.cfg` (outside the repo). |
| Attribution | Paginated list of every asset ever downloaded, with icon and creator links. Also on **Esc** / **☰** from any screen. |
| Load demo shapes | Five built-in shapes so the toy plays with no API key. |

### Play keys

```
click        spawn selected icon      P      next palette
right-click  remove nearest           F      feedback on/off
Space        spawn somewhere          [ ]    feedback zoom
1-9          select slot              , .    feedback twist
Q W E R T Y U I   toggle verbs        - =    feedback fade
X            recolor slot             O      kaleidoscope (off/3/4/6/8/12)
                                      G      chroma key: drop an image on the
                                             window for the backdrop, plasma otherwise
                                      K      pixelate size (off/4/8/12/20/32)
                                      L      palette quantise
                                      J      dither (with quantise)
                                      V      CRT off / soft / heavy
                                      M      monitor inside the scene (recursion)
                                      N      monitor size; drag it to move
                                      B      3D solid of the selected icon at the mouse
                                      Shift+B next shape (cube/sphere/torus/cylinder/prism)
                                      ;      MIDI + audio panel
                                      A      audio source: off / mic / test / file
                                      Z      webcam: off / layer behind everything / chroma backdrop
                                      S      steal a palette from the selected raster or the webcam
drop an image on the window   →  a raster toolbox slot (Shift+drop → chroma backdrop)
                                      C      clear stage
Del          remove slot              H      hide HUD (clean capture)
Esc / ☰      menu + attribution
```

## MIDI-learn (Knobcon)

Press **;** in Play. Every MIDI input is opened on launch (Rescan after plugging in). Click a
row, then move a knob or hit a pad: that message is bound to it. Right-click a row to unbind.

- **Params** (knobs, faders, velocity-sensitive pads, pitch bend, 0..1): feedback zoom /
  twist / fade, pixelate size, kaleidoscope, CRT, monitor size, palette, toolbox slot.
- **Actions** (pads, buttons, or a CC crossing 64): spawn icon, spawn 3D solid, clear,
  feedback, next palette, chroma, quantise, dither, monitor, next shape, recolor, select
  slot 1-9, toggle each verb on the selected slot.

Bindings live in `user://midi.json`. The HUD shows the last message received.

## Audio reactivity

Press **A** to cycle the source: **mic**, a built-in **test** groove (120 BPM, no input
needed), or a **file** (drop an mp3/ogg/wav on the window; it plays and loops). Four bands
(bass, mid, high, level) and a beat detector come out of it:

- With audio on, the **Pulse** verb follows the bass and everything jumps a little on the beat.
- In the **;** panel, the **♪** button on any row binds it to a band: params follow
  bass/mid/high/level, actions fire on the beat. Feedback zoom on bass and Spawn on beat is
  the obvious first patch.
- **Audio gain** is itself a param, so a knob can set the sensitivity.

The mic is analysed on a silent bus and never played back. macOS asks for microphone
permission the first time you switch to mic.

**No input device?** Godot 4.7 needs `audio/driver/enable_input` for the mic, and on a machine
with no input device at all that setting makes CoreAudio fail and *all* audio goes silent.
`./run.sh play` checks for an input device on macOS and writes a gitignored `override.cfg`
that turns input off when there is none (the HUD says so; test groove and file still work).
Plug in an interface and run again to get the mic back.

## Raster and webcam

Drop a PNG / JPG / WebP on the window and it becomes a toolbox slot: verbs, spawning and 3D
solids all work on it, and it keeps its own colours (Rainbow still shifts them). The file is
copied to `user://raster/` and listed in Attribution as a local image. **Shift+drop** makes
it the chroma-key backdrop instead.

**Z** cycles the webcam: as a *layer* it sits behind everything in the world, so it goes
through feedback, effects and the monitor — point the camera at the screen and you have a
real feedback loop; as a *backdrop* it shows through the chroma key. Godot's CameraServer
handles RGB and YCbCr feeds; macOS asks for camera permission the first time. The HUD says
"no camera" if there is none.

**S** steals a palette: k-means over the selected raster (or the live webcam frame), darkest
cluster as background, the rest as the ring sorted by hue. Stolen palettes join the P cycle
and persist in `user://palettes.json`.

## Credentials

Resolved in this order (same as [noun-project-utils](https://github.com/TheMutantFactory/noun-project-utils)):

1. `NOUN_KEY` / `NOUN_SECRET` environment variables
2. `user://noun_credentials.cfg` (the Settings screen writes this)
3. `~/.config/noun/credentials.cfg` — plain INI, `[noun]` section with `key=` and `secret=`

Search and quota checks are free. Adding an icon to the toolbox is the only metered call.

## Layout

```
main.tscn / src/main.gd     screen router, --selftest, --capture
src/menu_overlay.gd         ☰ / Esc menu + paginated Attribution
src/start_screen.gd         modes
src/search_screen.gd        Noun Project search → inspect → add
src/stage_screen.gd         play: SubViewport world + ping-pong feedback
src/fx.gd + fx.gdshader     post-process: CRT, kaleidoscope, pixelate, chroma key, quantise, dither
src/monitor.gd              the TV inside the world that shows the final composite
src/solid.gd                a 3D shape wearing an icon; lives in a 3D viewport composited into the world
src/actor.gd                one icon on stage; verbs read live from Toolbox
src/hotbar.gd               the 9-slot bar
src/toolbox.gd   (autoload) slots + verbs, user://toolbox.json
src/ledger.gd    (autoload) attribution ledger, user://attribution.json
src/noun_api.gd  (autoload) OAuth 1.0a client (pinned to RFC 5849 vector)
src/icon_media.gd(autoload) thumbnails + white SVG rasteriser
src/palettes.gd             named colour sets
src/verbs.gd                verb table
src/midi_map.gd  (autoload) MIDI-learn: opens inputs, binds messages to params/actions, user://midi.json
src/midi_panel.gd           the MIDI + audio panel on the stage
src/audio_react.gd (autoload) mic / file / test groove -> bass, mid, high, level, beat
src/webcam.gd               CameraServer feed (RGB or YCbCr) as a sprite; rendered to a viewport on the stage
demo/                       built-in shapes
docs/RESEARCH.md            video toys, feedback, shader art, 3D, raster — the roadmap
```

## Licensing

Most Noun Project icons are CC BY. The ledger keeps the attribution string and license for every
download, and the Attribution screen shows it in-app. Keep it visible in anything you publish.
