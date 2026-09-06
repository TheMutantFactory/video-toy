class_name ClipExport
## The loop-maker's export: a canvas format (the clip is a centre crop of
## the 1920x1080 picture), an exact-length render of the timeline loop with
## a pre-roll to warm the feedback, and — when ffmpeg is on the machine —
## an mp4, seamless for loops (the loop's first second cross-dissolves from
## the frames that follow its end). Pure parts here; the process handling
## is in main.gd.

const FORMATS := {"16:9": Vector2i(1920, 1080), "9:16": Vector2i(608, 1080), "1:1": Vector2i(1080, 1080)}
const FFMPEG_PATHS := ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg", "C:/ffmpeg/bin/ffmpeg.exe"]

static var _ffmpeg := ""
static var _ffmpeg_checked := false


static func crop(format: String) -> Vector2i:
	return FORMATS.get(format, FORMATS["16:9"])


static func next_format(format: String) -> String:
	var keys: Array = FORMATS.keys()
	var i := keys.find(format)
	return keys[(i + 1) % keys.size()] if i >= 0 else keys[0]


## The child Godot's arguments. Movie Maker sizes the movie from the project's
## viewport setting, not the window, so the crop goes through override.cfg
## (set_window_override) rather than --resolution.
static func child_args(project: String, out: String, total_seconds: float, fps: int, format: String, preroll: float) -> PackedStringArray:
	return PackedStringArray(["--path", project, "--write-movie", out, "--fixed-fps", str(fps),
		"--", "--clip", str(total_seconds), "--format", format, "--preroll", str(preroll)])


## Put the crop into override.cfg's [display] section (merging with whatever
## else is there, e.g. the audio input switch); the full picture removes it.
static func set_window_override(crop_size: Vector2i, path: String, full := Vector2i(1920, 1080)) -> bool:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path):
		cfg.load(path)
	if crop_size == full:
		if cfg.has_section_key("display", "window/size/viewport_width"):
			cfg.erase_section_key("display", "window/size/viewport_width")
		if cfg.has_section_key("display", "window/size/viewport_height"):
			cfg.erase_section_key("display", "window/size/viewport_height")
		if cfg.has_section("display") and cfg.get_section_keys("display").is_empty():
			cfg.erase_section("display")
	else:
		cfg.set_value("display", "window/size/viewport_width", crop_size.x)
		cfg.set_value("display", "window/size/viewport_height", crop_size.y)
	if cfg.get_sections().is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return true
	return cfg.save(path) == OK


static func clear_window_override(path: String) -> bool:
	return set_window_override(Vector2i(1920, 1080), path)


## ffmpeg arguments: trim the pre-roll; for a loop, cross-dissolve the first
## `seam` seconds from the frames after the loop's end so the end meets the start.
static func ffmpeg_args(avi: String, mp4: String, preroll: float, length: float, seam: float, loop: bool) -> PackedStringArray:
	var p := preroll
	var l := length
	if not loop or seam <= 0.0 or seam >= l * 0.5:
		return PackedStringArray(["-y", "-ss", "%.3f" % p, "-i", avi, "-t", "%.3f" % l,
			"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-c:a", "aac", "-movflags", "+faststart", mp4])
	var t := seam
	var graph := ("[0:v]trim=start=%.3f:end=%.3f,setpts=PTS-STARTPTS[loop];" % [p, p + l]
		+ "[0:v]trim=start=%.3f:end=%.3f,setpts=PTS-STARTPTS[tail];" % [p + l, p + l + t]
		+ "[loop]split[l1][l2];[l1]trim=end=%.3f,setpts=PTS-STARTPTS[head];[l2]trim=start=%.3f,setpts=PTS-STARTPTS[rest];" % [t, t]
		+ "[tail][head]xfade=transition=fade:duration=%.3f:offset=0[seam];[seam][rest]concat=n=2:v=1:a=0[v];" % t
		+ "[0:a]atrim=start=%.3f:end=%.3f,asetpts=PTS-STARTPTS[a]" % [p, p + l])
	return PackedStringArray(["-y", "-i", avi, "-filter_complex", graph, "-map", "[v]", "-map", "[a]",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-c:a", "aac", "-movflags", "+faststart", mp4])


## A shell script with the same command, for a machine that has ffmpeg.
static func script(args: PackedStringArray) -> String:
	var quoted: Array = []
	for a in args:
		quoted.append("'" + str(a).replace("'", "'\\''") + "'")
	return "#!/bin/sh\n# Video Toy clip: run where ffmpeg is installed (brew install ffmpeg)\nffmpeg " + " ".join(quoted) + "\n"


static func ffmpeg_path() -> String:
	if _ffmpeg_checked:
		return _ffmpeg
	_ffmpeg_checked = true
	for p in FFMPEG_PATHS:
		if FileAccess.file_exists(p):
			_ffmpeg = p
			return p
	var out := []
	if OS.execute("which" if OS.get_name() != "Windows" else "where", ["ffmpeg"], out) == 0 and not out.is_empty():
		var found := str(out[0]).strip_edges().split("\n")[0]
		if found != "" and FileAccess.file_exists(found):
			_ffmpeg = found
	return _ffmpeg


static func has_ffmpeg() -> bool:
	return ffmpeg_path() != ""
