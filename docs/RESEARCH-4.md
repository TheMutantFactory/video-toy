# Research 4: what to build next

Written 2026-09-06. Everything in [RESEARCH.md](RESEARCH.md), [RESEARCH-2.md](RESEARCH-2.md) and
[RESEARCH-3.md](RESEARCH-3.md) is built, including the engineering items. The suite is 166 smoke
checks, 24 self-test blocks on the real stage, 36 captures and 6 pixel-diffed references.

Two honest facts shape this round. **The toy has never been exported**: it has only ever run from
the editor binary through `run.sh`. And **every hardware path is still synthetic** (mic, camera,
MIDI, gamepad). Both matter more than any new effect. Costs as before (S hour, M session, L days).

---

## 1. Ship it: an exported app (M)

Running from `run.sh` is fine on this desk and wrong for a table at Knobcon or a laptop at a party.

- **macOS export** with `export_presets.cfg` and a `./run.sh export` target. Godot's macOS
  export has the privacy options the OS needs before it will even *ask* — the microphone and
  camera usage descriptions — and without them the prompts never appear in an exported app
  (they do from the editor binary, which is why it has never come up)
  ([EditorExportPlatformMacOS](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformmacos.html)).
- **Keep the App Sandbox off.** Sandboxed apps cannot run `OS.create_process` (the clip render),
  cannot use custom file dialogs, and Syphon and the OSC socket are happier outside it
  ([exporting for macOS](https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_macos.html)).
  Ad-hoc signing is enough for a machine you own; notarization is only for handing the app to
  strangers, and it requires the debugging entitlement off.
- The vendored Syphon framework rides along through the gdextension's dependency entry; check
  it lands in `Contents/Frameworks` and loads from the bundle.
- **Windows**: export templates plus Spout in place of Syphon ([spout-gd](https://github.com/you-win/spout-gd));
  `override.cfg` logic in `run.sh` needs an in-app equivalent (a setting) once there is no shell.
- A **version stamp** in the HUD (git hash baked at export) so a bug report says which build.

## 2. The play-test (no code; still first)

The checklist in RESEARCH-3 §1 stands. Do it with the exported app, not the editor binary, so
the permission prompts and the bundle are tested too. Whatever it finds outranks everything below.

## 3. The show manual and the key card (S–M)

- `docs/SHOW.md`: setup checklist (audio interface in, Syphon into OBS, TouchOSC IP, which bank),
  the panic and blackout keys, the restore-after-crash flow, credits export at the end.
- A **printable key card**: the README's key table is 80 lines; generate a one-page PNG/PDF from
  the live tables (Shot.compose already draws text), grouped Basics / Verbs / Effects / Show /
  Controllers. Tape it to the laptop.
- The in-app help card is the same wall of text; see §4.

## 4. UX (M)

- **Help redesign**: tabs (Basics, Verbs, Effects, Show, Controllers, Player 2) and a search box,
  as a proper overlay like the control panel; H toggles a *compact* HUD instead.
- **Settings screen**: quality lock, OSC port, Syphon server name, autosave interval, clock source,
  audio input enable (replaces `override.cfg`), reference-diff thresholds. Persist in
  `user://settings.cfg`; the export removes the shell, so these need a home.
- **Undo** (Ctrl+Z) for the last spawn, clear, remove, mosaic: a small stack of live states.
- **Surprise me**: a random-preset generator — N mutations from a known-good base plus a random
  palette and scene — as an action and a start-screen button. It is what a guest presses first.
- **Guest mode**: mouse-only operation (a right-click radial menu for slot, verb, palette,
  spawn-solid; long-press to remove) so someone with no keyboard knowledge can play at a party.
- **First-run tour**: five captions over the stage on the first launch.

## 5. Fun (the birthday and Knobcon pile)

- **Physics verb** (M): icons as `RigidBody2D` with a collision polygon from the alpha
  (`BitMap.opaque_to_polygons`), a floor, gravity toggle, throw with the mouse, pile-ups, and
  collisions that fire sparkle and sound. The single most playful thing left.
- **Sounds** (M): a `.wav` dropped *on a slot* becomes its sound, triggered on spawn, beat,
  pinata and (with physics) collision. Nine slots, nine samples: a drum kit you can see.
- **Icon as oscillator** (M, Knobcon bait): read the icon's distance field around a ring into an
  `AudioStreamGenerator` wavetable — the shape you see is the wave you hear; Morph glides between
  timbres, Pulse is amplitude, Spin is pitch. This is the one that gets people to lean in.
- **MIDI out** is a gap: Godot has no MIDI output. Notes on spawn / collision would go over OSC to
  a bridge, or via a small GDExtension later.
- **Long exposure** (S): feedback with no decay and no zoom, plus a clear key — light painting
  with Draw mode and the attractor verbs.
- **Image sequences** (S): a folder of PNGs dropped on Play becomes an animated slot without
  ffmpeg; the video-slot machinery already exists.
- **Optical-flow-lite** (M): the difference between webcam frames as a displacement field the
  particles and the Field verb ride — the room moves the picture.
- **Drop shadows / parallax** (S): a shadow pass under actors; layers 2 and 3 at slight offsets
  driven by the mouse for depth.

## 6. Health (S each, L together)

- **CI**: a GitHub Actions workflow with a headless Godot
  ([chickensoft setup-godot](https://github.com/chickensoft-games/setup-godot)) running
  `./run.sh test`; captures and pixel diffs stay local (they need the GPU and the window).
- More **reference shots** among the deterministic ones (attribution, scenes tiles are animated;
  the Find Icons screen and the control panel are not).
- A `--safe` launch flag: no MIDI, OSC, camera or audio input, for a machine that misbehaves.
- **Crash logs**: launch with `--log-file user://logs/last.txt` from the app bundle wrapper and
  offer the log next to the restore button.
- The stage is 1,600 lines after the split; layers, drawing and input are the next candidates
  for modules, and `_unhandled_key_input` (200 lines) wants a key table.

## 7. Suggested order

1. **Export + privacy strings + version stamp** (§1) — nothing else can be play-tested honestly.
2. **The play-test** (§2) with the exported app; fix what it finds.
3. **Show manual + key card** (§3) — the week before Knobcon.
4. **Help redesign + settings screen** (§4) — removes the shell dependency and the key wall.
5. **Physics verb + sounds** (§5) — the party.
6. **CI** (§6) — once the suite is what protects the show.
