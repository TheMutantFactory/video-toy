class_name Safe
## Safe mode: no MIDI, OSC, camera or microphone, for a machine that
## misbehaves. On with `--safe` (./run.sh safe, or `open -a "Video Toy"
## --args --safe`) or the Settings switch. Decided once, at first use; the
## autoloads ask before touching hardware.

static var _active := -1


static func active() -> bool:
	if _active < 0:
		_active = 1 if from(OS.get_cmdline_user_args(), bool(Settings.get_value("safe_mode"))) else 0
	return _active == 1


## Pure: the flag or the setting.
static func from(args: PackedStringArray, setting: bool) -> bool:
	return args.has("--safe") or setting


static func describe() -> String:
	return "SAFE MODE: no MIDI, OSC, camera or microphone"
