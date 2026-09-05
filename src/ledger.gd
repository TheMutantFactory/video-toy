extends Node
## Attribution ledger (autoload "Ledger"): every asset ever downloaded, kept
## forever in user://attribution.json even after it leaves the toolbox — a VOD
## may still show it. The Attribution screen paginates this list.

signal changed

const PATH := "user://attribution.json"

var entries: Array = []
var path := PATH


func _ready() -> void:
	load_from_disk()


func record(meta: Dictionary) -> void:
	var id := str(meta.get("id", ""))
	if id == "":
		return
	var creator: Dictionary = meta.get("creator", {}) if meta.get("creator") is Dictionary else {}
	var entry := {
		"id": id,
		"term": str(meta.get("term", "")),
		"attribution": str(meta.get("attribution", "")),
		"license": str(meta.get("license_description", meta.get("license", ""))),
		"permalink": str(meta.get("permalink", "")),
		"creator_name": str(creator.get("name", meta.get("creator_name", ""))),
		"creator_permalink": str(creator.get("permalink", meta.get("creator_permalink", ""))),
		"thumbnail_url": str(meta.get("thumbnail_url", "")),
		"source": str(meta.get("source", "The Noun Project")),
		"downloaded_at": int(Time.get_unix_time_from_system()),
	}
	for i in entries.size():
		if entries[i].get("id") == id:
			entries[i] = entry
			save_to_disk()
			changed.emit()
			return
	entries.append(entry)
	save_to_disk()
	changed.emit()


## A local image: kept in the ledger so the attribution list is complete.
func record_local(slot: Dictionary) -> void:
	record({"id": slot.get("id", ""), "term": slot.get("term", ""), "attribution": slot.get("attribution", ""),
		"license": slot.get("license", "user-supplied"), "source": "text" if slot.get("kind") == "text" else "local file",
		"creator": {"name": "you", "permalink": ""}})


func remove(id: String) -> void:
	for i in entries.size():
		if entries[i].get("id") == id:
			entries.remove_at(i)
			save_to_disk()
			changed.emit()
			return


func count() -> int:
	return entries.size()


func page(index: int, per_page: int) -> Array:
	var start := index * per_page
	if start >= entries.size() or start < 0:
		return []
	return entries.slice(start, mini(start + per_page, entries.size()))


func page_count(per_page: int) -> int:
	return maxi(1, ceili(float(entries.size()) / per_page))


## One credit line with the link: "term by Creator (license) — url".
static func credit_line(e: Dictionary) -> String:
	var line := line_for(e)
	var lic := str(e.get("license", ""))
	if lic != "":
		line += " (%s)" % lic
	var link := str(e.get("permalink", ""))
	if link != "":
		line += " — " + (link if link.begins_with("http") else "https://thenounproject.com" + link)
	return line


## The whole ledger (or just `ids`) as a text block for a VOD description.
func credits_text(ids: Array = []) -> String:
	var noun: Array = []
	var local: Array = []
	for e in entries:
		if not ids.is_empty() and not ids.has(str(e.get("id", ""))):
			continue
		if str(e.get("source", "The Noun Project")) == "The Noun Project":
			noun.append(credit_line(e))
		else:
			local.append(credit_line(e))
	var out: Array = ["Made with Video Toy (github.com/TheMutantFactory/video-toy)"]
	if not noun.is_empty():
		out.append("")
		out.append("Icons from The Noun Project (thenounproject.com):")
		out.append_array(noun)
	if not local.is_empty():
		out.append("")
		out.append("Other assets:")
		out.append_array(local)
	return "\n".join(out) + "\n"


func write_credits(path := "user://credits.txt", ids: Array = []) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(credits_text(ids))
	f.close()
	return path


static func line_for(e: Dictionary) -> String:
	var line := str(e.get("attribution", ""))
	if line == "":
		line = "%s by %s from %s" % [e.get("term", "?"), e.get("creator_name", "?"), e.get("source", "The Noun Project")]
	return line


func save_to_disk() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"entries": entries}, "\t"))
	f.close()


func load_from_disk() -> void:
	entries = []
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("entries") is Array:
		for e in data["entries"]:
			if e is Dictionary:
				entries.append(e)
	changed.emit()
