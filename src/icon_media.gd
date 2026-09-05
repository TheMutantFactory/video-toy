extends Node
## Icon imagery (autoload "IconMedia"):
##  - get_thumbnail(url, cb): async PNG thumbnail fetch, memory + disk cached.
##    Thumbnails are unmetered.
##  - texture_for(svg_path): local SVG -> white ImageTexture (alpha kept), cached.
##    Noun icons are black line art; whitening them lets `modulate` tint them
##    on the GPU for free, which is what palettes and the rainbow verb rely on.

const THUMB_DIR := "user://icons/thumbs"
const SVG_SCALE := 4.0                      # 100pt API canvas -> ~400px texture
const RASTER_MAX := 512                     # raster slots are downscaled to this
const RASTER_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

const SDF_DIR := "user://icons/sdf"

var _thumbs := {}                           # url -> ImageTexture
var _svgs := {}                             # path -> ImageTexture
var _sdfs := {}                             # path -> ImageTexture (distance field)


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


## Icon (SVG -> white) or raster (PNG/JPG/... -> full colour, downscaled).
func texture_for(path: String) -> ImageTexture:
	if _svgs.has(path):
		return _svgs[path]
	var tex := load_raster(path, RASTER_MAX) if is_raster(path) else load_svg_white(path, SVG_SCALE)
	if tex:
		_svgs[path] = tex
	return tex


## The icon's signed distance field (see sdf.gd), computed once per icon and
## cached on disk. Any slot works; a photo's field is its alpha rectangle.
func sdf_for(path: String) -> ImageTexture:
	if _sdfs.has(path):
		return _sdfs[path]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SDF_DIR))
	var disk := "%s/%d.png" % [SDF_DIR, absi(path.hash())]
	var img := Image.new()
	if not FileAccess.file_exists(disk) or img.load(ProjectSettings.globalize_path(disk)) != OK:
		var tex := texture_for(path)
		if tex == null:
			return null
		img = Sdf.from_alpha(tex.get_image())
		img.save_png(ProjectSettings.globalize_path(disk))
	var out := ImageTexture.create_from_image(img)
	_sdfs[path] = out
	return out


static func is_raster(path: String) -> bool:
	return path.get_extension().to_lower() in RASTER_EXT


## Raster file -> ImageTexture, longest side capped at `max_side`.
static func load_raster(path: String, max_side := 512) -> ImageTexture:
	var img := Image.new()
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	if img.load(abs) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var longest := maxi(img.get_width(), img.get_height())
	if longest > max_side:
		var f := float(max_side) / longest
		img.resize(maxi(1, int(img.get_width() * f)), maxi(1, int(img.get_height() * f)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


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
