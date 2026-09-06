extends Verb
## Breathes on a sine; with audio on, follows the bass instead.

func _init() -> void:
	id = "pulse"; panel = 5; name = "Pulse"; key = "T"; hint = "breathe in and out"

func post2d(a, _delta: float) -> void:
	a.frame_scale *= (1.0 + 0.7 * a.audio_bass()) if a.audio_active() else (1.0 + 0.25 * sin(a.t * 4.0))

func post3d(s, _delta: float) -> void:
	s.frame_scale *= (1.0 + 0.7 * s.audio_bass()) if s.audio_active() else (1.0 + 0.25 * sin(s.t * 4.0))

func formation(f, _delta: float) -> void:
	f.frame_scale *= (1.0 + 0.5 * f.audio_bass()) if f.audio_active() else (1.0 + 0.2 * sin(f.t * 4.0))
