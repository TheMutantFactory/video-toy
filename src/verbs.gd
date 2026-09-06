class_name Verbs
## The verb registry: every *.gd in res://verbs/ (or another directory passed
## to load_from) that extends Verb, instantiated once and sorted by `order`
## then id. `all()` gives the metadata list the UI, templates and tests use;
## `instances()` gives the objects the hosts run.

const DIR := "res://verbs"

static var _loaded := false
static var _instances: Array = []


static func load_from(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and (f.ends_with(".gd") or f.ends_with(".gdc")):
			var script = load(dir.path_join(f))
			if script is GDScript and script.can_instantiate():
				var inst = script.new()
				if inst is Verb and inst.id != "":
					out.append(inst)
		f = d.get_next()
	d.list_dir_end()
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.id < b.id)
	return out


static func _ensure() -> void:
	if not _loaded:
		_instances = load_from(DIR)
		_loaded = true


static func instances() -> Array:
	_ensure()
	return _instances


## Metadata in panel order (the keyboard layout), for the UI and templates.
static func all() -> Array:
	_ensure()
	var sorted: Array = _instances.duplicate()
	sorted.sort_custom(func(a, b): return a.panel < b.panel if a.panel != b.panel else a.id < b.id)
	return sorted.map(func(v): return v.meta())


static func ids() -> Array:
	return instances().map(func(v): return v.id)


## The active Verb objects for a slot's id list, in order, group-exclusive.
static func active_for(active_ids: Array) -> Array:
	var out: Array = []
	var groups := {}
	for v in instances():
		if not active_ids.has(v.id):
			continue
		if v.group != "":
			if groups.has(v.group):
				continue
			groups[v.group] = true
		out.append(v)
	return out


static func by_key(keycode: int, shift := false, ctrl := false) -> String:
	var nm := OS.get_keycode_string(keycode).to_upper()
	for v in instances():
		if nm == v.key.trim_prefix("⇧").trim_prefix("^") and shift == v.shift and ctrl == v.ctrl:
			return v.id
	return ""


static func get_instance(id: String) -> Verb:
	for v in instances():
		if v.id == id:
			return v
	return null


static func get_verb(id: String) -> Dictionary:
	for v in instances():
		if v.id == id:
			return v.meta()
	return {}
