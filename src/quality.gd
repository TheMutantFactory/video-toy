class_name Quality
## The quality ladder and the monitor that walks it. Level 0 is full quality;
## higher levels shed load. Pure logic, tested; the stage applies the levels.

const LEVELS := [
	{"name": "full",   "particles": 12000, "rd_every": 1, "slit_stride": 2, "glow_taps": 16, "msaa": true},
	{"name": "high",   "particles": 6000,  "rd_every": 2, "slit_stride": 2, "glow_taps": 12, "msaa": false},
	{"name": "medium", "particles": 3000,  "rd_every": 3, "slit_stride": 4, "glow_taps": 8,  "msaa": false},
	{"name": "low",    "particles": 1500,  "rd_every": 4, "slit_stride": 6, "glow_taps": 6,  "msaa": false},
]
const STEP_DOWN_MS := 20.0        # sustained frame time that triggers a step down
const STEP_UP_MS := 12.0          # sustained frame time that allows a step up
const DOWN_AFTER := 1.0           # seconds over the limit before stepping down
const UP_AFTER := 5.0             # seconds under the limit before stepping up
const COOLDOWN := 3.0             # seconds between steps

var level := 0
var locked := -1                  # -1 = auto, else a fixed level
var avg_ms := 16.7
var _over := 0.0
var _under := 0.0
var _cooldown := 0.0


static func count() -> int:
	return LEVELS.size()


static func get_level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


func effective() -> int:
	return locked if locked >= 0 else level


## Feed one frame. Returns true when the effective level changed.
func update(frame_ms: float, delta: float) -> bool:
	avg_ms = lerpf(avg_ms, frame_ms, minf(1.0, delta * 4.0))
	_cooldown = maxf(0.0, _cooldown - delta)
	if locked >= 0:
		return false
	var before := level
	if avg_ms > STEP_DOWN_MS:
		_over += delta
		_under = 0.0
	elif avg_ms < STEP_UP_MS:
		_under += delta
		_over = 0.0
	else:
		_over = 0.0
		_under = 0.0
	if _cooldown <= 0.0:
		if _over >= DOWN_AFTER and level < LEVELS.size() - 1:
			level += 1
			_over = 0.0
			_cooldown = COOLDOWN
		elif _under >= UP_AFTER and level > 0:
			level -= 1
			_under = 0.0
			_cooldown = COOLDOWN
	return level != before


## Cycle the lock: auto -> 0 -> 1 -> 2 -> 3 -> auto.
func cycle_lock() -> void:
	locked = -1 if locked >= LEVELS.size() - 1 else locked + 1


func describe() -> String:
	var l: Dictionary = get_level(effective())
	return "%s%s" % [l["name"], "" if locked >= 0 else " (auto)"]
