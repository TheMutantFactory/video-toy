class_name Locks
## Lock and mutate: the sections of the look a user can pin so Surprise and
## evolve vary everything else, and the "nearby" amount that scales how far
## a mutation reaches. Pure; the stage keeps the chosen locks in settings.

const SECTIONS := ["palette", "verbs", "feedback", "fx", "glow", "scene", "layers", "camera"]
const KIND_SECTION := {"verb": "verbs", "palette": "palette", "fx": "fx", "feedback": "feedback", "glow": "glow",
	"scene": "scene", "key": "fx", "slit": "fx", "layer": "layers", "camera": "camera"}
const SNAPSHOT_KEYS := {"palette": ["palette"], "verbs": ["slots", "selected"], "feedback": ["feedback", "warp"],
	"fx": ["fx", "ascii"], "glow": ["glow"], "scene": ["scene"], "layers": ["layers", "active_layer"], "camera": ["camera"]}
const AMOUNTS := [0.25, 0.5, 1.0]


static func allowed(kind: String, locked: Array) -> bool:
	return not locked.has(str(KIND_SECTION.get(kind, "")))


## The locked sections of a snapshot, as a partial snapshot to re-apply.
static func keep(snapshot: Dictionary, locked: Array) -> Dictionary:
	var out := {}
	for section in locked:
		for key in SNAPSHOT_KEYS.get(section, []):
			if snapshot.has(key):
				out[key] = snapshot[key]
	return out


## How many mutations a surprise makes at this amount (1 nearby .. 6 wild).
static func mutation_count(amount: float) -> int:
	return clampi(roundi(lerpf(1.0, 6.0, clampf(amount, 0.0, 1.0))), 1, 6)


static func next_amount(amount: float) -> float:
	var i := AMOUNTS.find(amount)
	return AMOUNTS[(i + 1) % AMOUNTS.size()] if i >= 0 else 1.0


static func describe(locked: Array, amount: float) -> String:
	var parts: Array = []
	if not locked.is_empty():
		parts.append("locks: " + ", ".join(locked))
	if amount < 1.0:
		parts.append("nearby %.2f" % amount)
	return "   ·   ".join(parts)
