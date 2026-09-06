extends Verb
## Metadata only: the actor's SDF path (_tick_sdf) does the work in 2D; a
## knot solid reads the verb itself and ties into its next family.

func _init() -> void:
	id = "morph"; panel = 15; name = "Morph"; key = "⇧M"; shift = true
	hint = "become the next icon, shape to shape (on the beat with audio); a knot ties into the next knot"
