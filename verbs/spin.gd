extends Verb

func _init() -> void:
	id = "spin"; panel = 3; name = "Spin"; key = "E"; hint = "rotate in place"; sets_rotation = true

func post2d(a, delta: float) -> void:
	a._sprite.rotation += delta * 2.2

func post3d(s, delta: float) -> void:
	s.rotate(s.spin_axis, delta * 2.05)          # on top of the solid's idle turn

func formation(f, delta: float) -> void:
	f.rotate_y(delta * 1.0)                      # on top of the formation's idle turn
