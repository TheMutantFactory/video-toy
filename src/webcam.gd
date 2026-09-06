extends Node2D
## Webcam feed as a world layer. Wraps Godot's CameraServer: activates the
## first feed, waits for its datatype (macOS reports it on the first frame),
## and builds either a plain RGBA CameraTexture or a YCbCr pair with a
## conversion shader. Fills a 16:9 box centred on `position`.
##
## No autoload dependencies; safe to instantiate anywhere. `status` is for the
## HUD: "no camera", "starting…", "live (Name)".

const YCBCR_SHADER := """
shader_type canvas_item;
uniform sampler2D y_tex : filter_linear;
uniform sampler2D cbcr_tex : filter_linear;
void fragment() {
	float y = texture(y_tex, UV).r;
	vec2 cbcr = texture(cbcr_tex, UV).rg - 0.5;
	COLOR = vec4(y + 1.402 * cbcr.y, y - 0.344 * cbcr.x - 0.714 * cbcr.y, y + 1.772 * cbcr.x, 1.0);
}
"""

var status := "no camera"
var box := Vector2(1920, 1080)
var feed: CameraFeed
var _sprite: Sprite2D
var _built := false


func _ready() -> void:
	if "monitoring_feeds" in CameraServer and not Safe.active():   # this is what asks macOS for the camera
		CameraServer.monitoring_feeds = true
	_sprite = Sprite2D.new()
	add_child(_sprite)
	start()


func start() -> void:
	if Safe.active():
		status = "safe mode: camera off"
		return
	if CameraServer.get_feed_count() == 0:
		status = "no camera"
		return
	feed = CameraServer.get_feed(0)
	feed.feed_is_active = true
	status = "starting…"


func stop() -> void:
	if feed:
		feed.feed_is_active = false
	feed = null
	_built = false
	_sprite.texture = null
	_sprite.material = null
	status = "no camera" if CameraServer.get_feed_count() == 0 else "off"


func is_live() -> bool:
	return _built


func _process(_delta: float) -> void:
	if feed == null:
		if CameraServer.get_feed_count() > 0 and status == "no camera":
			start()
		return
	if not _built and feed.get_datatype() != CameraFeed.FEED_NOIMAGE:
		_build()
	if _built and _sprite.texture:
		var size := _sprite.texture.get_size()
		if size.x > 0 and size.y > 0:
			var s := maxf(box.x / size.x, box.y / size.y)          # cover the box
			_sprite.scale = Vector2(s, s)


func _build() -> void:
	var t := CameraTexture.new()
	t.camera_feed_id = feed.get_id()
	t.camera_is_active = true
	match feed.get_datatype():
		CameraFeed.FEED_RGB:
			t.which_feed = CameraServer.FEED_RGBA_IMAGE
			_sprite.texture = t
		CameraFeed.FEED_YCBCR:
			t.which_feed = CameraServer.FEED_YCBCR_IMAGE
			_sprite.texture = t
		CameraFeed.FEED_YCBCR_SEP:
			t.which_feed = CameraServer.FEED_Y_IMAGE
			var c := CameraTexture.new()
			c.camera_feed_id = feed.get_id()
			c.camera_is_active = true
			c.which_feed = CameraServer.FEED_CBCR_IMAGE
			var sh := Shader.new()
			sh.code = YCBCR_SHADER
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("y_tex", t)
			m.set_shader_parameter("cbcr_tex", c)
			_sprite.texture = t
			_sprite.material = m
	_built = true
	status = "live (%s)" % feed.get_name()
