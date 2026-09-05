extends Node2D
## A drawn stroke that icons ride. The stroke becomes a Curve2D; N riders
## (ordinary actors with `riding = true`, so motion verbs are ignored but
## spin / pulse / rainbow / sparkle still apply) follow it in a loop. The
## stroke itself is drawn as a soft line in the palette accent.

const SPACING := 14.0          # resample spacing in px
const RIDER_EVERY := 110.0     # one rider per this much stroke length
const SPEED := 170.0           # px/s

var slot_id := ""
var speed := SPEED
var _path: Path2D
var _follows: Array = []
var _line: Line2D


## Static helpers (autoload-free, tested): resample a stroke to even spacing.
static func resample(points: PackedVector2Array, spacing := SPACING) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	out.append(points[0])
	var carry := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		var t := spacing - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += spacing
		carry = seg - (t - spacing)
	if out[out.size() - 1].distance_to(points[points.size() - 1]) > spacing * 0.5:
		out.append(points[points.size() - 1])
	return out


static func length_of(points: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, points.size()):
		l += points[i - 1].distance_to(points[i])
	return l


static func rider_count(length: float) -> int:
	return clampi(int(length / RIDER_EVERY), 2, 24)


## `make_actor` builds an actor at a position (the stage supplies it so this
## script stays free of autoloads).
func setup(points: PackedVector2Array, slot: Dictionary, accent: Color, make_actor: Callable) -> int:
	slot_id = str(slot.get("id", ""))
	var pts := resample(points)
	var closed := pts.size() > 3 and pts[0].distance_to(pts[pts.size() - 1]) < 90.0
	var curve := Curve2D.new()
	for p in pts:
		curve.add_point(p)
	if closed:
		curve.add_point(pts[0])
	_path = Path2D.new()
	_path.curve = curve
	add_child(_path)
	_line = Line2D.new()
	_line.points = pts if not closed else pts + PackedVector2Array([pts[0]])
	_line.width = 5.0
	_line.default_color = Color(accent, 0.45)
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.z_index = -1
	add_child(_line)
	var n := rider_count(curve.get_baked_length())
	for i in n:
		var f := PathFollow2D.new()
		f.loop = true
		f.rotates = false
		_path.add_child(f)                      # must be in the tree before progress is set
		f.progress_ratio = float(i) / n
		var a: Node2D = make_actor.call(f.position)
		a.riding = true
		f.add_child(a)
		a.position = Vector2.ZERO
		_follows.append(f)
	return n


func riders() -> Array:
	var out: Array = []
	for f in _follows:
		for c in f.get_children():
			out.append(c)
	return out


func near(world_pos: Vector2, tolerance := 40.0) -> bool:
	for p in _line.points:
		if p.distance_to(world_pos) < tolerance:
			return true
	return false


func _process(delta: float) -> void:
	var alive := 0
	for f in _follows:
		if f.get_child_count() > 0:
			alive += 1
		f.progress += speed * delta
	if alive == 0:
		queue_free()
