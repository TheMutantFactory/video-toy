extends Verb
## Metadata only: the actor's SDF path (_tick_sdf) does the work.

func _init() -> void:
	id = "outline"; panel = 16; name = "Outline"; key = "⇧J"; shift = true
	hint = "hollow the icon to a ring that follows its silhouette"
