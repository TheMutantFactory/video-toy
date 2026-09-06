extends RefCounted
## Undo / redo: a short stack of live states taken before spawns, removes,
## clears, mosaics, paths and pinatas (contents only: the look you dialled
## in afterwards stays) and before evolve votes / surprise (the whole look).
## Owned by the stage; `s` is the stage.

const MAX := 12

var s: Stage
var muted := 0                      # > 0 while a restore or a batch runs
var _undo: Array = []               # [{label, full, state}]
var _redo: Array = []


func _init(stage: Stage) -> void:
	s = stage


func push(label: String, full := false) -> void:
	if muted > 0:
		return
	_undo.append({"label": label, "full": full, "state": s.live_state()})
	while _undo.size() > MAX:
		_undo.pop_front()
	_redo.clear()


## Run `what` as one undo step named `label`.
func batch(label: String, what: Callable, full := false) -> Variant:
	push(label, full)
	muted += 1
	var out: Variant = what.call()
	muted -= 1
	return out


func undo() -> bool:
	if _undo.is_empty():
		s._steal_note = "nothing to undo"
		s._update_hud()
		return false
	var e: Dictionary = _undo.pop_back()
	_redo.append({"label": e["label"], "full": e["full"], "state": s.live_state()})
	_apply(e)
	s._steal_note = "undid " + str(e["label"])
	s._update_hud()
	return true


func redo() -> bool:
	if _redo.is_empty():
		s._steal_note = "nothing to redo"
		s._update_hud()
		return false
	var e: Dictionary = _redo.pop_back()
	_undo.append({"label": e["label"], "full": e["full"], "state": s.live_state()})
	_apply(e)
	s._steal_note = "redid " + str(e["label"])
	s._update_hud()
	return true


func _apply(e: Dictionary) -> void:
	muted += 1
	if e["full"]:
		s.restore_live(e["state"])
	else:
		s.restore_contents(e["state"])
	muted -= 1


func depth() -> int:
	return _undo.size()


func labels() -> Array:
	return _undo.map(func(e): return e["label"])


func clear() -> void:
	_undo.clear()
	_redo.clear()
