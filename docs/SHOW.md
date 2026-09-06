# Running a show

The night-before and day-of checklist for Knobcon, a stream or a party. The keys are on the
[key card](key-card.png) ([text version](KEYS.md)); tape it to the laptop.

## The week before

- **Build the app**: `./run.sh export` → `out/Video Toy.app`. It runs the self-test from inside
  the bundle; it must end with `PASS blocks: 24`. Copy the app to the show machine.
- **First launch on the show machine**: macOS asks for the microphone and camera the first time
  **A** (mic) and **Z** (webcam) are pressed. Say yes. If you said no, System Settings →
  Privacy & Security → Microphone / Camera → Video Toy.
- **Microphone input**: the app only listens if Settings → **Microphone input** is on. On a
  machine with **no** audio input at all, that same switch must be **off** or every sound goes
  silent (CoreAudio fails and Godot falls back to a dummy driver). Either way it takes effect on
  the next launch, so relaunch and check the HUD's audio line.
- **Rig**: build the toolbox (Find Icons or Load demo shapes, words, dropped SVGs), give the
  slots their verbs and colours, then Esc → **Export rig (zip)**. Keep that zip: it is the whole
  show — icons, ledger, presets, banks, controller bindings, palettes, the timeline loop, the font.
  Drop it on Play (or Esc → Import rig…) on any other machine.
- **Set list**: save looks with **Shift+F1..F12**; eight banks with **Shift+,** / **Shift+.**.
  Bank 1 preset 1 should be the safe opener. **Shift+-** / **Shift+=** walk the filled presets in
  order — bind them to a foot switch or two pads. **Shift+;** sets the crossfade time; 2 s reads
  as a cut on a beat, 4 s as a scene change.
- **Controllers**: **;** opens the panel. Plug in, **Rescan**, click a row, move the knob. Or load
  the **Launchpad map** / **APC mini map** buttons (`docs/controllers/`), or send
  `docs/controllers/video-toy.tosc` to a phone running TouchOSC (host = the toy's IP, port 9000).
  Test **panic** and **blackout** from the surface, not just the keyboard.
- **Quality**: watch the HUD's `work` figure with the heaviest preset up. If it steps down on its
  own, that is the ladder doing its job; lock it with **Shift+F** (or `./run.sh play medium`) if
  the flicker between levels shows.

## Setup at the venue (20 minutes)

1. Power, display, audio interface in, **then** launch. Godot lists audio and MIDI devices at
   start; a device plugged in later needs **Rescan** (MIDI) or a relaunch (audio interface).
2. Fullscreen: the window's green button or **⌃⌘F**. The picture is 1920×1080 scaled to the
   display; on a 4K TV at 30 Hz everything still runs at 30 fps and the HUD says so.
3. **Video out**: HDMI straight to the projector, or **Shift+Z** to publish the picture (no HUD)
   as the Syphon server "Video Toy" — in OBS add a *Syphon Client* source and pick it; Resolume
   and VDMX list it under Syphon. The HUD shows `syphon on` while it publishes.
4. **Audio in**: **A** until the HUD says `mic`; clap and watch the beat dot. No input device?
   **A** again for the built-in test groove, or a dropped mp3 / ogg / wav, or the internal clock
   (**;** panel, BPM learnable) for beat-driven verbs without any audio.
5. **Camera** (if used): **Z** once for a layer behind everything, twice for the chroma backdrop.
6. Recall bank 1 preset 1 (**F1**), check the toolbox slots, press **H** to hide the HUD for the
   audience feed, keep it on the operator screen if you have two.
7. Leave it in **attract mode** (**Shift+A**, or wait 60 s) while people wander in; any input
   ends it.

## During

- **Shift+Esc** is **panic**: every effect, feedback, particles, scene, monitor, webcam, layer
  blend, camera, draw / evolve / attract / timeline off, glow soft. Toolbox and actors stay.
  It is also in the Esc menu and is a learnable action — put it on a pad.
- **Shift+H** is **blackout**, a half-second fade to black; press again to come back.
- **Shift+F** locks the quality level if the auto ladder is hunting.
- **Shift+R** records controller gestures, **Shift+P** loops them (bar-quantised when a clock
  runs) — a knob sweep becomes an LFO while you do something else.
- Let guests play: **Shift+2** hides player 2's cursor when nobody is on the keypad / gamepad.
  A Sparkle icon clicked is a pinata.
- **Shift+V** saves a screenshot of the picture with the credits strip burned in
  (`~/Library/Application Support/Video Toy/shots/` in the exported app).

## If it crashes

The live state (every icon and solid on stage plus the whole look) is autosaved every 30 s. On
relaunch the start screen offers **Restore last session** — take it, then **F1** if the look was
the problem. The toolbox, presets and bindings are on disk regardless.

## After

- Esc → **Attribution** → **Copy credits** puts the whole ledger on the clipboard for the VOD
  description; **Save credits.txt** writes it next to the presets. The Noun Project licenses want
  the creator named; this is that.
- **Shift+C** runs the credits roll over the picture as an end card; **Shift+L** shows the
  one-line ticker of what is on screen right now.
- **Render 20 s clip** (Esc menu) writes an AVI at a fixed 60 fps offline — a clean loop for
  the socials even if the show machine was dropping frames.
- **Export rig** again so the night's tweaks travel home.

## Where things live (exported app)

`~/Library/Application Support/Video Toy/`: `toolbox.json`, `presets/`, `banks/`, `midi.json`,
`ledger.json`, `autosave.json`, `rigs/`, `shots/`, `clips/`, `credits.txt`,
`noun_credentials.cfg`. `override.cfg` (the microphone switch) sits beside the executable in
`Video Toy.app/Contents/MacOS/`. The version is on the start screen and in Settings.
