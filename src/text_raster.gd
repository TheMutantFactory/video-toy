class_name TextRaster
## A word as a white-on-alpha Image, rendered through the TextServer's glyph
## atlases on the CPU — no viewport, so it works headless and at add time.
## The result is exactly the shape an icon has, so everything downstream
## (tint, verbs, solids, extrusion, formations) treats it as one.

const PAD := 24


static func render(text: String, size := 160, font: Font = null) -> Image:
	if font == null:
		font = ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	var shaped := ts.create_shaped_text()
	ts.shaped_text_add_string(shaped, text, font.get_rids(), size)
	ts.shaped_text_shape(shaped)
	var glyphs := ts.shaped_text_get_glyphs(shaped)
	var ssize: Vector2 = ts.shaped_text_get_size(shaped)
	var ascent: float = ts.shaped_text_get_ascent(shaped)
	var w := maxi(int(ceil(ssize.x)) + PAD * 2, 8)
	var h := maxi(int(ceil(ssize.y)) + PAD * 2, 8)
	var dst := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pen := Vector2(PAD, PAD + ascent)
	for g in glyphs:
		var frid: RID = g["font_rid"]
		var fsz := Vector2i(int(g["font_size"]), 0)
		var idx: int = g["index"]
		if idx != 0:
			ts.font_render_glyph(frid, fsz, idx)
			var tidx: int = ts.font_get_glyph_texture_idx(frid, fsz, idx)
			if tidx >= 0:
				var uv: Rect2 = ts.font_get_glyph_uv_rect(frid, fsz, idx)
				var off: Vector2 = ts.font_get_glyph_offset(frid, fsz, idx)
				var atlas: Image = ts.font_get_texture_image(frid, fsz, tidx)
				if atlas and atlas.get_format() != Image.FORMAT_RGBA8:
					atlas = atlas.duplicate()
					atlas.convert(Image.FORMAT_RGBA8)
				if atlas:
					dst.blend_rect(atlas, Rect2i(uv), Vector2i(pen + Vector2(g.get("offset", Vector2.ZERO)) + off))
		pen.x += float(g["advance"]) * int(g.get("repeat", 1))
	ts.free_rid(shaped)
	# force pure white, keep coverage as alpha
	for y in h:
		for x in w:
			var a := dst.get_pixel(x, y).a
			if a > 0.0:
				dst.set_pixel(x, y, Color(1, 1, 1, a))
	return dst


static func opaque_count(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n
