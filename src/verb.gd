class_name Verb
extends RefCounted
## A verb is one file in res://verbs/: metadata plus behaviour hooks for the
## three hosts. Hooks receive the host and `delta`; they reach host state
## directly (position, velocity, sprite, audio helpers, active_ids...).
##
##   move2d / move3d  run in `order` while the host is mobile; return true if
##                    the base position moved (Orbit shrinks its radius then).
##                    Only the first active verb of a `group` runs.
##   post2d / post3d  run after motion: rotation, scale (frame_scale), colour,
##                    particles. Set sets_rotation when you steer the sprite.
##   formation        runs on a 200-instance formation.
## Verb files must not reference autoloads: the hosts wrap what they need
## (audio_active(), audio_bass(), beat_env(), beat_hit) so the smoke test can
## load every verb without the game running.

var id := ""
var name := ""
var key := ""            # "Q" or "⇧Q"
var hint := ""
var shift := false
var ctrl := false        # key is "^P": Ctrl+P
var exclusive := false   # while active, no other motion verb runs (Physics)
var order := 100         # motion order; lower first
var panel := 100         # position in the verb panel / templates (keyboard order)
var group := ""          # exclusive group for motion (e.g. "attractor")
var sets_rotation := false


func meta() -> Dictionary:
	return {"id": id, "name": name, "key": key, "hint": hint, "shift": shift, "ctrl": ctrl}


func has_motion2d() -> bool:
	return false


func has_motion3d() -> bool:
	return false


func move2d(_a, _delta: float) -> bool:
	return false


func post2d(_a, _delta: float) -> void:
	pass


func move3d(_s, _delta: float) -> bool:
	return false


func post3d(_s, _delta: float) -> void:
	pass


func formation(_f, _delta: float) -> void:
	pass


## Called once on a host when the verb stops being active there (Echo frees its ghosts).
func leave(_host) -> void:
	pass
