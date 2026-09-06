# Research 6: the Ware Tetralogy grimoire, mapped

A reading of *The Ware Tetralogy as a Video-Effects Grimoire* (Rudy Rucker's twist-box,
philtres, Perplexing Poultry, TonKnoT, flickercladding, gnarl) against what is built. Its final
thesis — feedback remembers, cellular rules repair, particles embody attention, audio supplies
energy, attractors give motion a personality, homeostasis keeps the result near the edge of
interestingness, history and locks keep discoveries — is a description of this stage. The gaps
are the twist-box's missing stages, the regulator, and two philtres.

## Already here, under other names

| Grimoire | Toy |
| --- | --- |
| Twist, Memory | the feedback loop: zoom / twist / fade / warp / drift / stretch, the delay tap, in-loop blur, hue and saturation drift, displacement |
| Attractor clothing | Lorenz / Rössler / Clifford / de Jong verbs, the particle field with attractors and curl noise |
| Boids, worms | Flock, Swarm, Field |
| Cellular imagery | reaction-diffusion under the world, ASCII, mosaic |
| Audio / MIDI modulation | the learn table, audio bands with shaping, modulators, tempo tracking, the clock |
| State locks, constrained mutation, snapshot morphing | locks, the mutation amount, banks with crossfade, evolve, Surprise me |
| Recording, Syphon, preset packaging | clips and loops, Syphon, rigs |
| Beauty as a stability sink (partly) | the quality ladder sheds load; it does not yet add spectacle back |

## Build order

1. **The literal twist-box** — the three stages the loop lacks, all inside the warp pass:
   - **Cleanup** — built: a cellular-automaton step per pass (majority grow, Life, erode) that
     grows coherent regions out of the smear; amount and rule in the routing panel, a param and
     an action, snapshotted, crossfaded, cleared by panic.
   - **Cutup**: the slit-scan history atlas already holds 36 time slices; rearrange them
     spatially by motion and salience (a shader over the atlas, driven by the difference key).
   - **Jagged trails**: quantise the feedback drift to an angular lattice per region so trails
     turn angular instead of smooth; a "trail shape" control (smooth / angular / branching).
   - **Time zones**: several delay taps at once, chosen per pixel by a slow noise field, so
     parts of the picture run slow and fast (the ring already holds 24 frames).
   - **Fluxdots**: particle emitters from an image or the webcam's bright regions
     (salience-driven reconstruction), feeding the existing field.
2. **The Gnarl regulator**: read the composite back at 240×135 every few frames, measure edge
   density and frame-to-frame difference, and steer fade / warp / cleanup toward a complexity
   target (homeostasis speed, order / noise bias). The **beauty outlet** pairs with the quality
   ladder: when it sheds load, raise glow and trails so the picture stays rich.
3. **Two philtres**: **Poultry** — a quasicrystal tessellation as an fx pass with the toolbox
   icons as the glyph cells, pecking at neighbours on the beat (de Bruijn / Voronoi in a
   shader); **TonKnoT** — parametric torus knots as a new 3D solid, tube thickness and (p, q)
   as params, Morph gliding between knots.
4. **Small verbs and scenes**: Shimmer (thirty-colour flicker within a palette family), Echo
   (translucent delayed copies — multiplicity), Wake (sparks along the cursor's movement), a
   spectrum procession formation, a purple-static-rain scene.
5. **Vocabulary**: name the loop's controls Twist, Memory, Cutup, Cleanup on the panel and the
   key card, so the loop reads as an instrument rather than a filter.

## Not worth it here

Face and body tracking, semantic segmentation, hyperspherical projections and the
"philtre as ontology" in full: they need models the toy does not carry, and the payoff is
narrative. Flickercladding on a tracked body waits on a silhouette we do not have; on the
3D solids it is a texture idea for later.
