class_name CrashLog
## Godot's rotated log files (user://logs): godot.log is this run, the
## timestamped ones are earlier runs, newest last by name. After a run that
## did not exit cleanly, the start screen offers the previous run's log.

const DIR := "user://logs"
const CURRENT := "godot.log"


static func current(dir := DIR) -> String:
	return dir.path_join(CURRENT)


## Earlier runs' logs, newest first.
static func files(dir := DIR) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("godot") and f.ends_with(".log") and f != CURRENT:
			out.append(f)
	out.sort()
	out.reverse()
	return out.map(func(f): return dir.path_join(f))


## The previous run's log, or "".
static func previous(dir := DIR) -> String:
	var fs := files(dir)
	return fs[0] if not fs.is_empty() else ""


## Lines that look like trouble, oldest first, at most `limit` (the last ones).
static func errors(text: String, limit := 6) -> Array:
	var out: Array = []
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("ERROR") or l.begins_with("SCRIPT ERROR") or l.begins_with("USER ERROR") or l.contains("handle_crash") or l.contains("Fatal") or l.begins_with("Dumping the backtrace"):
			if out.is_empty() or out[-1] != l:
				out.append(l)
	if out.size() > limit:
		out = out.slice(out.size() - limit)
	return out


static func tail(text: String, lines := 12) -> String:
	var all := text.strip_edges().split("\n")
	if all.size() > lines:
		all = all.slice(all.size() - lines)
	return "\n".join(all)


## What the start screen shows: the file, its error lines and its tail.
static func report(path: String) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return "no log from the last run"
	var text := FileAccess.get_file_as_string(path)
	var errs := errors(text)
	var out := "%s  (%d lines)\n" % [ProjectSettings.globalize_path(path), text.count("\n")]
	if errs.is_empty():
		out += "no error lines — the run was probably killed (power, Force Quit, the watchdog)\n"
	else:
		out += "%d error line%s, last ones:\n  %s\n" % [errs.size(), "" if errs.size() == 1 else "s", "\n  ".join(errs)]
	out += "tail:\n  " + tail(text).replace("\n", "\n  ")
	return out
