class_name IconBody
## Godot physics for icons: a RigidBody2D whose collision polygons come from
## the icon's alpha (BitMap.opaque_to_polygons), walls around the world so
## things pile up on the floor, one gravity value for every body. Attached
## by the Physics verb, detached when the verb goes; no autoload references
## so the smoke test can load it.

const MAX_PX := 96                    # polygon resolution
const WALL := 200.0

static var gravity := 1.0             # gravity_scale for every body (0 = floating billiards)
static var collisions := 0            # counted since launch (tests, HUD)
static var _cache: Dictionary = {}    # texture rid + scale -> Array[PackedVector2Array]


## Collision polygons in sprite-local pixels for a texture drawn at `scale`.
static func polygons_for(tex: Texture2D, scale: float) -> Array:
	if tex == null:
		return [_box(Vector2(80, 80) * scale)]
	var key := "%d@%.2f" % [tex.get_rid().get_id(), scale]
	if _cache.has(key):
		return _cache[key]
	var size := tex.get_size()
	var img: Image = tex.get_image()
	var out: Array = []
	if img != null and not img.is_empty():
		var small: Image = img.duplicate()
		small.convert(Image.FORMAT_RGBA8)
		var f := minf(1.0, float(MAX_PX) / maxf(size.x, size.y))
		small.resize(maxi(2, int(size.x * f)), maxi(2, int(size.y * f)), Image.INTERPOLATE_BILINEAR)
		var bm := BitMap.new()
		bm.create_from_image_alpha(small, 0.3)
		var ss := Vector2(small.get_width(), small.get_height())
		for poly in bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, Vector2i(ss)), 1.5):
			if poly.size() < 3:
				continue
			var pts := PackedVector2Array()
			for p in poly:
				pts.append((Vector2(p) / ss * size - size * 0.5) * scale)
			out.append(pts)
	if out.is_empty():
		out.append(_box(size * scale * 0.5))
	_cache[key] = out
	return out


static func _box(half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])


## Build the body for an actor (a Node2D with _sprite, position, velocity).
static func attach(a: Node2D) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.top_level = true
	body.global_position = a.position
	body.rotation = a._sprite.rotation
	body.mass = 1.0
	body.linear_damp = 0.15
	body.angular_damp = 0.5
	body.gravity_scale = gravity
	body.contact_monitor = true
	body.max_contacts_reported = 4
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35
	mat.friction = 0.6
	body.physics_material_override = mat
	body.linear_velocity = a.velocity
	for pts in polygons_for(a._sprite.texture, a._sprite.scale.x):
		var cp := CollisionPolygon2D.new()
		cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		cp.polygon = pts
		body.add_child(cp)
	a.add_child(body)
	if a.has_method("_on_body_entered"):
		body.body_entered.connect(a._on_body_entered)
	ensure_walls(a.get_parent(), a.bounds)
	return body


static func detach(a: Node2D) -> void:
	if a.body:
		a.body.queue_free()
		a.body = null


## Four static walls around `bounds`, once per physics world (viewport).
static func ensure_walls(container: Node, bounds: Rect2) -> void:
	if container == null:
		return
	var host: Node = container.get_parent() if container.get_parent() else container
	if host.has_node("IconWalls"):
		return
	var walls := StaticBody2D.new()
	walls.name = "IconWalls"
	var c := bounds.get_center()
	var sz := bounds.size
	for spec in [[Vector2(c.x, bounds.end.y + WALL * 0.5), Vector2(sz.x + WALL * 2, WALL)],
			[Vector2(c.x, bounds.position.y - WALL * 0.5), Vector2(sz.x + WALL * 2, WALL)],
			[Vector2(bounds.position.x - WALL * 0.5, c.y), Vector2(WALL, sz.y)],
			[Vector2(bounds.end.x + WALL * 0.5, c.y), Vector2(WALL, sz.y)]]:
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = spec[1]
		cs.shape = rect
		cs.position = spec[0]
		walls.add_child(cs)
	host.add_child(walls)
