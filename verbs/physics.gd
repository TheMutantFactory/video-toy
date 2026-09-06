extends Verb
## The icon becomes a rigid body with its own outline: it falls, bounces,
## piles up on the floor and can be thrown with the mouse. Other motion
## verbs step aside (exclusive); post verbs (Pulse, Rainbow, Sparkle) still
## run, and collisions burst and play the slot's sound. Ctrl+G toggles
## gravity for every body.

func _init() -> void:
	id = "physics"; panel = 17; name = "Physics"; key = "^P"; ctrl = true; exclusive = true; order = 0
	hint = "a rigid body with the icon's outline: falls, piles up, drag to throw (Ctrl+G gravity)"
	sets_rotation = true

func has_motion2d() -> bool: return true

func move2d(a, _delta: float) -> bool:
	if a.body == null:
		a.body = IconBody.attach(a)
	a.body.gravity_scale = IconBody.gravity
	a.position = a.body.global_position
	a.home = a.position
	a._sprite.rotation = a.body.rotation
	a.velocity = a.body.linear_velocity
	return true
