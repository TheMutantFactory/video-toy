extends "res://verbs/clifford.gd"

func _init() -> void:
	id = "dejong"; panel = 13; name = "de Jong"; key = "⇧U"; shift = true; hint = "fly between points of the de Jong map"
	order = 53; group = "attractor"

func step(p: Vector2) -> Vector2:
	return Attractors.dejong(p)
