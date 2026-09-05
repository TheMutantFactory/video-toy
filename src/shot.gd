class_name Shot
## A screenshot with the attribution burned in: the picture plus a dark strip
## listing the credit lines, rendered through TextRaster (CPU, headless-safe).

const LINE_PX := 22
const PAD := 12
const SHOT_DIR := "user://shots"


static func compose(picture: Image, lines: Array, bg := Color(0.04, 0.04, 0.06)) -> Image:
	var w := picture.get_width()
	var h := picture.get_height()
	var strip_h := PAD * 2 + LINE_PX * maxi(lines.size(), 1)
	var out := Image.create(w, h + strip_h, false, Image.FORMAT_RGBA8)
	out.fill(bg)
	var pic := picture.duplicate()
	pic.convert(Image.FORMAT_RGBA8)
	out.blit_rect(pic, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var y := h + PAD
	var rows: Array = lines if not lines.is_empty() else ["Made with Video Toy"]
	for line in rows:
		var img := TextRaster.render(str(line), 16)
		var col := Color(0.92, 0.92, 0.95, 1.0)
		var dst_y := y + (LINE_PX - img.get_height()) / 2
		for yy in img.get_height():
			for xx in mini(img.get_width(), w - PAD):
				var a := img.get_pixel(xx, yy).a
				if a > 0.02:
					var px := Vector2i(PAD + xx, dst_y + yy)
					if px.y >= 0 and px.y < out.get_height():
						out.set_pixelv(px, bg.lerp(col, a))
		y += LINE_PX
	return out


static func filename() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "shot-%04d%02d%02d-%02d%02d%02d.png" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


static func save(img: Image, dir := SHOT_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join(filename())
	return path if img.save_png(ProjectSettings.globalize_path(path)) == OK else ""
