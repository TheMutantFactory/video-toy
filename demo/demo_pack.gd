class_name DemoPack
## Five built-in shapes so the toy plays before any API key exists. Drawn for
## this project; no attribution needed, but they're recorded in the ledger
## anyway so the Attribution screen is honest about what's on screen.

const SHAPES := [
	["demo-star", "star"], ["demo-heart", "heart"], ["demo-bolt", "bolt"],
	["demo-ring", "ring"], ["demo-knob", "knob"],
]


static func load_into(toolbox: Node, ledger: Node) -> int:
	var added := 0
	for s in SHAPES:
		var meta := {"id": s[0], "term": s[1], "attribution": "%s — built-in demo shape (Video Toy)" % s[1],
			"license_description": "public-domain", "permalink": "", "source": "Video Toy demo pack",
			"creator": {"name": "The Mutant Factory", "permalink": ""}}
		if toolbox.add_from_meta(meta, "res://demo/%s.svg" % s[1]) >= 0:
			added += 1
		ledger.record(meta)
	return added
