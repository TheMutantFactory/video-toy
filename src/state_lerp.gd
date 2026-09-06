class_name StateLerp
## Interpolates two stage snapshots: continuous fields lerp, everything else
## switches at the midpoint. Pure; the stage applies the result each frame.

## Paths of continuous fields in a snapshot (section, key).
const CONTINUOUS := {
	"feedback": ["zoom", "rot", "fade", "blur", "hue", "sat", "displace", "cleanup", "jag", "zones"],
	"warp": ["amount", "speed", "dx", "dy", "sx", "sy"],
	"scene": ["speed", "scale", "bias"],
	"camera": ["orbit", "dolly", "roll", "height"],
	"particles": ["flow", "attract", "flux"],
	"rd": ["feed", "kill"],
	"monitor": ["x", "y"],
	"fx": ["key_threshold"],
	"physics": ["gravity"],
}


static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	var out: Dictionary = (b if t >= 0.5 else a).duplicate(true)
	for section in CONTINUOUS:
		var sa = a.get(section)
		var sb = b.get(section)
		if not (sa is Dictionary and sb is Dictionary):
			continue
		if not out.has(section):
			out[section] = {}
		for key in CONTINUOUS[section]:
			if sa.has(key) and sb.has(key):
				out[section][key] = lerpf(float(sa[key]), float(sb[key]), t)
	# layer opacities live in an array
	var la = a.get("layers")
	var lb = b.get("layers")
	if la is Array and lb is Array and out.get("layers") is Array:
		for i in mini(la.size(), mini(lb.size(), out["layers"].size())):
			if la[i] is Dictionary and lb[i] is Dictionary and la[i].has("opacity") and lb[i].has("opacity"):
				out["layers"][i]["opacity"] = lerpf(float(la[i]["opacity"]), float(lb[i]["opacity"]), t)
	return out
