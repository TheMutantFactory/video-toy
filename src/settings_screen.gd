extends Control
## Noun Project API key/secret. Saved to user://noun_credentials.cfg (outside
## the repo). Also honours NOUN_KEY/NOUN_SECRET and ~/.config/noun/credentials.cfg.

signal navigate(name: String)

const Creds = preload("res://src/credentials.gd")

var _key: LineEdit
var _secret: LineEdit
var _status: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palettes.bg(0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.custom_minimum_size = Vector2(760, 0)
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	col.add_child(UI.title("Settings", 56))
	col.add_child(UI.label("Noun Project API (thenounproject.com/developers)", 20, UI.DIM))
	col.add_child(UI.vspace(6))
	col.add_child(UI.label("Key"))
	_key = LineEdit.new()
	_key.custom_minimum_size = Vector2(0, 48)
	col.add_child(_key)
	col.add_child(UI.label("Secret"))
	_secret = LineEdit.new()
	_secret.secret = true
	_secret.custom_minimum_size = Vector2(0, 48)
	col.add_child(_secret)
	var existing := Creds.load_creds()
	if not existing.is_empty():
		_key.text = existing["key"]
		_secret.text = existing["secret"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(UI.button("Save", _save, 140))
	row.add_child(UI.button("Test connection", _test, 200))
	row.add_child(UI.button("Clear", func():
		Creds.clear_creds()
		_key.text = ""
		_secret.text = ""
		_status.text = "Cleared the saved key.", 120))
	row.add_child(UI.button("← Back", func(): navigate.emit("start"), 140))

	_status = UI.label("", 18, UI.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var src := Creds.source()
	_status.text = ("Using credentials from %s." % src) if src != "" else \
		"No credentials yet. Paste your key and secret, Save, then Test."
	NounApi.usage_result.connect(_on_usage)


func _save() -> void:
	if _key.text.strip_edges() == "" or _secret.text.strip_edges() == "":
		_status.text = "Both fields are needed."
		return
	Creds.save_creds(_key.text, _secret.text)
	_status.text = "Saved to user://noun_credentials.cfg. Now Test."


func _test() -> void:
	_status.text = "Testing…"
	NounApi.test_connection()


func _on_usage(ok: bool, usage: Dictionary, message: String) -> void:
	if ok:
		_status.text = "Connected. usage: " + JSON.stringify(usage)
	else:
		_status.text = "Failed: " + message

