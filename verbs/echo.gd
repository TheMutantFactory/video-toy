extends Verb
## Multiplicity: translucent copies of the icon trail a few frames behind
## it, fanning out from the sharp present into fainter pasts. The copies
## live in the actor's verb_state and go when the verb goes (leave()).

const GHOSTS := 7
const STRIDE := 4                # frames between copies

func _init() -> void:
	id = "echo"; panel = 20; name = "Echo"; key = "^K"; ctrl = true; order = 200
	hint = "multiplicity: seven fading copies trail a few frames behind"


func post2d(a, _delta: float) -> void:
	var st: Dictionary = a.verb_state.get("echo", {})
	if st.is_empty():
		st = {"hist": [], "ghosts": []}
		for i in GHOSTS:
			var g := Sprite2D.new()
			g.z_index = -1
			g.visible = false
			a.add_child(g)
			st["ghosts"].append(g)
		a.verb_state["echo"] = st
	var hist: Array = st["hist"]
	hist.push_front(a.position)
	while hist.size() > GHOSTS * STRIDE + 1:
		hist.pop_back()
	for i in GHOSTS:
		var g: Sprite2D = st["ghosts"][i]
		var k := (i + 1) * STRIDE
		if k >= hist.size():
			g.visible = false
			continue
		g.visible = true
		g.texture = a._sprite.texture
		g.material = a._sprite.material
		g.position = hist[k] - a.position
		g.scale = a._sprite.scale
		g.rotation = a._sprite.rotation
		var m: Color = a._sprite.modulate
		m.a = 0.55 * (1.0 - float(i) / GHOSTS)
		g.modulate = m


func leave(a) -> void:
	var st: Dictionary = a.verb_state.get("echo", {})
	for g in st.get("ghosts", []):
		g.queue_free()
	a.verb_state.erase("echo")
