extends Node3D
## Hundreds of copies of one shape wearing one icon, in a formation, drawn as
## one MultiMesh with per-instance palette colours. Reads the slot's verbs live
## like solid.gd: Spin turns the whole formation, Pulse breathes it, Rainbow
## cycles the ring, Orbit swings it around the origin.

const KINDS := ["helix", "lattice", "shell", "ring", "procession"]
const PROCESSION_N := 7

var slot_id := ""
var kind := "helix"
var count := 0
var t := 0.0
var angle := 0.0
var _mm: MultiMeshInstance3D
var _pal := 0
var _color_index := 0


## Instance transforms for a formation. Static and autoload-free (tested).
static func transforms(kind_: String, n: int, spread := 3.2) -> Array:
	var out: Array = []
	match kind_:
		"lattice":
			var side := maxi(2, int(ceil(pow(n, 1.0 / 3.0))))
			var i := 0
			for z in side:
				for y in side:
					for x in side:
						if i >= n:
							break
						var p := (Vector3(x, y, z) / (side - 1) - Vector3(0.5, 0.5, 0.5)) * spread
						out.append(Transform3D(Basis.from_euler(Vector3(0, 0, 0)).scaled(Vector3.ONE * 0.28), p))
						i += 1
		"shell":
			var golden := PI * (3.0 - sqrt(5.0))
			for i in n:
				var y := 1.0 - (i / float(n - 1)) * 2.0
				var r := sqrt(1.0 - y * y)
				var th := golden * i
				var p := Vector3(cos(th) * r, y, sin(th) * r) * spread * 0.55
				var dir := -p.normalized() if p.length() > 0.001 else Vector3.FORWARD
				var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP     # poles: avoid colinear up
				var b := Basis.looking_at(dir, up).scaled(Vector3.ONE * 0.3)
				out.append(Transform3D(b, p))
		"procession":
			for i in n:
				var f := (i + 0.5) / n - 0.5
				var p := Vector3(f * spread * 1.9, sin(f * PI * 2.0) * 0.15, 0.0)
				var b := Basis(Vector3.UP, f * 0.6).scaled(Vector3.ONE * 0.5)
				out.append(Transform3D(b, p))
		"ring":
			for i in n:
				var th := TAU * i / n
				var p := Vector3(cos(th), 0.0, sin(th)) * spread * 0.6
				var b := Basis(Vector3.UP, -th).scaled(Vector3.ONE * 0.3)
				out.append(Transform3D(b, p))
		_:   # helix
			for i in n:
				var f := i / float(n)
				var th := f * TAU * 4.0
				var p := Vector3(cos(th), (f - 0.5) * spread * 1.4, sin(th)) * Vector3(spread * 0.45, 1.0, spread * 0.45)
				var b := Basis(Vector3.UP, -th).scaled(Vector3.ONE * 0.28)
				out.append(Transform3D(b, p))
	return out


func setup(slot: Dictionary, kind_: String, mesh: Mesh, materials: Array, n: int, pal: int) -> void:
	slot_id = str(slot.get("id", ""))
	kind = kind_
	count = n
	_pal = pal
	_color_index = int(slot.get("color_index", 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	var xf := transforms(kind_, n)
	for i in n:
		mm.set_instance_transform(i, xf[i])
	# MultiMeshInstance3D has no per-surface overrides; the mesh is ours, so
	# the materials go on its surfaces.
	for i in mini(materials.size(), mesh.get_surface_count()):
		mesh.surface_set_material(i, materials[i])
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	add_child(_mm)
	recolor(pal, _color_index)
	rotation = Vector3(0.3, randf() * TAU, 0.0)


## Per-instance colours walk the palette ring from the slot's colour.
func recolor(pal: int, color_index: int, hue_shift := 0.0) -> void:
	_pal = pal
	_color_index = color_index
	var ring := Palettes.ring(pal)
	for i in count:
		_mm.multimesh.set_instance_color(i, instance_color(kind, i, count, ring, color_index, hue_shift))


## Pure: a procession marches red to violet in hard steps; the rest walk the palette ring.
static func instance_color(kind_: String, i: int, n: int, ring: Array, color_index: int, hue_shift := 0.0) -> Color:
	if kind_ == "procession":
		return Color.from_hsv(fmod(float(i) / maxi(n, 1) * 0.85 + hue_shift, 1.0), 0.9, 1.0)
	var c: Color = ring[posmod(color_index + (i * ring.size()) / maxi(n, 1), ring.size())]
	if hue_shift != 0.0:
		c.h = fmod(c.h + hue_shift, 1.0)
	return c


func _verbs() -> Array:
	var i := Toolbox.index_of(slot_id)
	if i < 0:
		queue_free()
		return []
	return Toolbox.slots[i].get("verbs", [])


var frame_scale := 1.0


func audio_active() -> bool:
	return AudioReact.active()


func audio_bass() -> float:
	return AudioReact.bass


func _process(delta: float) -> void:
	var verbs := _verbs()
	if not is_inside_tree():
		return
	t += delta
	rotate_y(delta * 0.2)                      # idle turn; Spin adds to it
	frame_scale = 1.0
	for v in Verbs.active_for(verbs):
		v.formation(self, delta)
	if AudioReact.active():
		frame_scale *= 1.0 + 0.15 * AudioReact.beat_env
	scale = Vector3.ONE * frame_scale
