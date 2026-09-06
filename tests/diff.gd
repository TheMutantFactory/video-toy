extends SceneTree
## Compare out/<shot>.png against tests/reference/<shot>.png for every
## reference that exists. Exit 1 on any regression.
##   godot --headless --path . -s tests/diff.gd


func _init() -> void:
	var refdir := "res://tests/reference"
	var d := DirAccess.open(refdir)
	var fails := 0
	var n := 0
	if d:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".png"):
				n += 1
				var out_path := ProjectSettings.globalize_path("res://out").path_join(f)
				var a := Image.new()
				var b := Image.new()
				if a.load(ProjectSettings.globalize_path(refdir.path_join(f))) != OK:
					print("FAIL  cannot read reference ", f)
					fails += 1
				elif b.load(out_path) != OK:
					print("FAIL  no capture for ", f, " (run ./run.sh capture <shot> first)")
					fails += 1
				else:
					var r := ImageDiff.compare(a, b)
					print("%s  %s  mean %.4f  worst block %.3f" % ["PASS" if r["pass"] else "FAIL", f, r["mean"], r["worst_block"]])
					if not r["pass"]:
						fails += 1
			f = d.get_next()
	print("\n%d/%d reference shots match" % [n - fails, n])
	quit(1 if fails > 0 else 0)
