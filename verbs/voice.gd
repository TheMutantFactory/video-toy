extends Verb
## Hear the shape: the icon's silhouette is the waveform. One oscillator per
## icon, pitched by its slot; Morph glides the timbre to the next icon,
## Pulse is loudness, Spin bends the pitch. The actor owns the voice node.

func _init() -> void:
	id = "voice"; panel = 18; name = "Voice"; key = "^V"; ctrl = true
	hint = "hear the outline as a waveform; Morph glides timbre, Pulse loudness, Spin pitch"

func post2d(a, _delta: float) -> void:
	a.voice_wanted = true
