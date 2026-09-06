extends Verb
## Metadata only: the actor's SDF path (_tick_sdf) does the work.

func _init() -> void:
	id = "morph"; panel = 15; name = "Morph"; key = "⇧M"; shift = true
	hint = "become the next icon, shape to shape (on the beat with audio)"
