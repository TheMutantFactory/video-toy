# Video Toy

A Godot 4.7 toy for streams, VODs and Knobcon: search [The Noun Project](https://thenounproject.com)
for icons, drop them into a Minecraft-style hotbar, give them **verbs** (wander, orbit, spin,
bounce, pulse, sparkle, rainbow, swarm), pick a **palette**, and turn on **video feedback**.

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
X            recolor slot             C      clear stage
Del          remove slot              H      hide HUD (clean capture)
Esc / ☰      menu + attribution
```

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
src/actor.gd                one icon on stage; verbs read live from Toolbox
src/hotbar.gd               the 9-slot bar
src/toolbox.gd   (autoload) slots + verbs, user://toolbox.json
src/ledger.gd    (autoload) attribution ledger, user://attribution.json
src/noun_api.gd  (autoload) OAuth 1.0a client (pinned to RFC 5849 vector)
src/icon_media.gd(autoload) thumbnails + white SVG rasteriser
src/palettes.gd             named colour sets
src/verbs.gd                verb table
demo/                       built-in shapes
docs/RESEARCH.md            video toys, feedback, shader art, 3D, raster — the roadmap
```

## Licensing

Most Noun Project icons are CC BY. The ledger keeps the attribution string and license for every
download, and the Attribution screen shows it in-app. Keep it visible in anything you publish.
