extends Node
## Icon imagery (autoload "IconMedia"):
##  - get_thumbnail(url, cb): async PNG thumbnail fetch, memory + disk cached.
##    Thumbnails are unmetered.
##  - texture_for(svg_path): local SVG -> white ImageTexture (alpha kept), cached.
##    Noun icons are black line art; whitening them lets `modulate` tint them
##    on the GPU for free, which is what palettes and the rainbow verb rely on.

const THUMB_DIR := "user://icons/thumbs"
const SVG_SCALE := 4.0                      # 100pt API canvas -> ~400px texture

var _thumbs := {}                           # url -> ImageTexture
var _svgs := {}                             # path -> ImageTexture


func get_thumbnail(url: String, cb: Callable) -> void:
	if url == "":
		cb.call(null)
		return
	if _thumbs.has(url):
		cb.call(_thumbs[url])
		return
	var disk := _thumb_path(url)
	if FileAccess.file_exists(disk):
		var tex := _png_texture(FileAccess.get_file_as_bytes(disk))
		if tex:
			_thumbs[url] = tex
			cb.call(tex)
			return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code == 200 and body.size() > 0:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THUMB_DIR))
			var f := FileAccess.open(disk, FileAccess.WRITE)
			if f:
				f.store_buffer(body)
				f.close()
			var tex := _png_texture(body)
			if tex:
				_thumbs[url] = tex
			cb.call(tex)
		else:
			cb.call(null))
	if http.request(url) != OK:
		http.queue_free()
		cb.call(null)


func texture_for(svg_path: String) -> ImageTexture:
	if _svgs.has(svg_path):
		return _svgs[svg_path]
	var tex := load_svg_white(svg_path, SVG_SCALE)
	if tex:
		_svgs[svg_path] = tex
	return tex


func _thumb_path(url: String) -> String:
	return "%s/%d.png" % [THUMB_DIR, abs(url.hash())]


func _png_texture(bytes: PackedByteArray) -> ImageTexture:
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Local SVG -> white ImageTexture (alpha preserved).
static func load_svg_white(svg_path: String, scale := 4.0) -> ImageTexture:
	if not FileAccess.file_exists(svg_path):
		return null
	var img := Image.new()
	if img.load_svg_from_buffer(FileAccess.get_file_as_bytes(svg_path), scale) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
