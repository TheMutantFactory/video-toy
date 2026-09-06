extends Verb
## Emits small copies of the icon; with audio on, bursts on every beat.

func _init() -> void:
	id = "sparkle"; panel = 6; name = "Sparkle"; key = "Y"; hint = "spawn particles"

func post2d(a, _delta: float) -> void:
	a._particles.emitting = true
	if a.beat_hit:
		a._burst.restart()

func post3d(s, _delta: float) -> void:
	s._particles.emitting = true
