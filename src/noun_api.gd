extends Node
## 2-legged OAuth 1.0a (HMAC-SHA1) client for the Noun Project API v2.
## Ported from dopaminer-iconoclast/noun_api.gd; the signing core is pinned to
## the RFC 5849 reference vector in tests/smoke.gd, same as noun-project-utils.
##
## Cost: search and usage are free. download_icon() is METERED — one charge per
## call against the monthly quota — so it only runs on an explicit pick.

const BASE := "https://api.thenounproject.com"
const ICON_DIR := "user://icons"
const Creds = preload("res://src/credentials.gd")

signal usage_result(ok: bool, usage: Dictionary, message: String)
signal search_result(ok: bool, data: Dictionary, message: String)
signal download_result(ok: bool, meta: Dictionary, svg_path: String, message: String)

var last_usage := {}


func has_creds() -> bool:
	return Creds.has_creds()


## Free. Emits usage_result with the usage_limits dict.
func test_connection() -> void:
	_api_get("/v2/client/usage", {}, func(code: int, body: PackedByteArray):
		if code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			var usage := {}
			if data is Dictionary and data.get("usage_limits") is Dictionary:
				usage = data["usage_limits"]
				last_usage = usage
			usage_result.emit(true, usage, "Connected.")
		else:
			usage_result.emit(false, {}, _err(code)))


## Free, paginated. `cursor` is the next_page token from a prior result.
func search(query: String, limit := 24, cursor := "") -> void:
	var qp := {"query": query, "limit": str(limit), "thumbnail_size": "200"}
	if cursor != "":
		qp["next_page"] = cursor
	_api_get("/v2/icon", qp, func(code: int, body: PackedByteArray):
		if code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if data is Dictionary and data.get("usage_limits") is Dictionary:
				last_usage = data["usage_limits"]
			search_result.emit(true, data if data is Dictionary else {}, "")
		else:
			search_result.emit(false, {}, _err(code)))


## METERED. Fetches metadata with include_svg=1, saves the SVG to
## user://icons/{id}.svg, emits download_result(ok, meta, path, message).
func download_icon(id: String) -> void:
	_api_get("/v2/icon/%s" % id, {"include_svg": "1"}, func(code: int, body: PackedByteArray):
		if code != 200:
			download_result.emit(false, {}, "", "Metadata: " + _err(code))
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		var icon: Dictionary = data.get("icon", {}) if data is Dictionary else {}
		if data is Dictionary and data.get("usage_limits") is Dictionary:
			last_usage = data["usage_limits"]
		var inline: String = str(icon.get("svg", ""))
		if inline.strip_edges().begins_with("<"):
			var path := _save_svg(id, inline.to_utf8_buffer())
			download_result.emit(path != "", icon, path, "" if path != "" else "Could not write SVG.")
			return
		var url: String = str(icon.get("icon_url", ""))
		if url == "":
			download_result.emit(false, icon, "", "No SVG in response (not licensed for SVG?).")
			return
		_fetch_svg(id, url, icon))


func _err(code: int) -> String:
	match code:
		-1: return "No API credentials — open Settings."
		-2: return "Request failed to start."
		401, 403: return "Auth rejected (HTTP %d) — check key/secret." % code
		429: return "Rate limited or quota exhausted (HTTP 429)."
		_: return "HTTP %d." % code


func _save_svg(id: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ICON_DIR))
	var path := "%s/%s.svg" % [ICON_DIR, id]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	f.close()
	return path


func _fetch_svg(id: String, url: String, meta: Dictionary) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code == 200 and body.size() > 0:
			var path := _save_svg(id, body)
			download_result.emit(path != "", meta, path, "" if path != "" else "Could not write SVG.")
		else:
			download_result.emit(false, meta, "", "SVG fetch HTTP %d." % code))
	if http.request(url) != OK:
		http.queue_free()
		download_result.emit(false, meta, "", "SVG request failed to start.")


## Signed GET. cb(code, body). -1 = no creds, -2 = request failed to start.
func _api_get(path: String, qp: Dictionary, cb: Callable) -> void:
	var creds := Creds.load_creds()
	if creds.is_empty():
		cb.call(-1, PackedByteArray())
		return
	var signed := _sign_request("GET", BASE + path, qp, creds)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		cb.call(code, body))
	if http.request(signed[0], ["Authorization: " + signed[1]], HTTPClient.METHOD_GET) != OK:
		http.queue_free()
		cb.call(-2, PackedByteArray())


# ---------------- OAuth 1.0a signing ----------------
func _sign_request(method: String, base_url: String, qp: Dictionary, creds: Dictionary) -> Array:
	var oauth := {
		"oauth_consumer_key": creds["key"],
		"oauth_nonce": _nonce(),
		"oauth_signature_method": "HMAC-SHA1",
		"oauth_timestamp": str(int(Time.get_unix_time_from_system())),
		"oauth_version": "1.0",
	}
	var all := {}
	for k in qp:
		all[k] = qp[k]
	for k in oauth:
		all[k] = oauth[k]
	var names := all.keys()
	names.sort()
	var parts: Array = []
	for k in names:
		parts.append("%s=%s" % [_pe(k), _pe(str(all[k]))])
	var base := "%s&%s&%s" % [method, _pe(base_url), _pe("&".join(parts))]
	oauth["oauth_signature"] = _sign(base, _pe(str(creds["secret"])) + "&")
	var hp: Array = []
	for k in oauth:
		hp.append('%s="%s"' % [_pe(k), _pe(str(oauth[k]))])
	var q: Array = []
	for k in qp:
		q.append("%s=%s" % [_pe(k), _pe(str(qp[k]))])
	var url := base_url + ("?" + "&".join(q) if not q.is_empty() else "")
	return [url, "OAuth " + ", ".join(hp)]


func _sign(base: String, signing_key: String) -> String:
	var ctx := HMACContext.new()
	ctx.start(HashingContext.HASH_SHA1, signing_key.to_utf8_buffer())
	ctx.update(base.to_utf8_buffer())
	return Marshalls.raw_to_base64(ctx.finish())


## RFC 3986 percent-encoding (unreserved kept; everything else %XX, UTF-8).
func _pe(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		if (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9") \
				or c == "-" or c == "." or c == "_" or c == "~":
			out += c
		else:
			for b in c.to_utf8_buffer():
				out += "%%%02X" % b
	return out


func _nonce() -> String:
	var s := ""
	for i in 24:
		s += "%x" % (randi() % 16)
	return s
