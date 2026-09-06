class_name LiveText
## Words that change by themselves: a countdown to a time of day, or the clock.
## Pure helpers; the stage re-renders the slot when the text changes.


## "clock" -> {"live": "clock"}; "countdown 23:59" (or "countdown 0:00") ->
## {"live": "countdown", "target": unix seconds of the next such time}; else {}.
static func parse(word: String, now_unix := -1) -> Dictionary:
	var w := word.strip_edges().to_lower()
	if w == "clock":
		return {"live": "clock"}
	if w.begins_with("countdown"):
		var rest := w.trim_prefix("countdown").strip_edges()
		var hm := rest.split(":")
		if hm.size() >= 2 and hm[0].is_valid_int() and hm[1].is_valid_int():
			var now := int(Time.get_unix_time_from_system()) if now_unix < 0 else now_unix
			var d := Time.get_datetime_dict_from_unix_time(now)
			d["hour"] = int(hm[0])
			d["minute"] = int(hm[1])
			d["second"] = int(hm[2]) if hm.size() > 2 and hm[2].is_valid_int() else 0
			var target := Time.get_unix_time_from_datetime_dict(d)
			if target <= now:
				target += 86400
			return {"live": "countdown", "target": target}
	return {}


static func text_for(live: String, target: int, now_unix: int) -> String:
	match live:
		"clock":
			var d := Time.get_datetime_dict_from_unix_time(now_unix)
			return "%02d:%02d:%02d" % [d["hour"], d["minute"], d["second"]]
		"countdown":
			var left := maxi(0, target - now_unix)
			if left == 0:
				return "🎉"
			var h := left / 3600
			var m := (left % 3600) / 60
			var s := left % 60
			return ("%d:%02d:%02d" % [h, m, s]) if h > 0 else ("%d:%02d" % [m, s])
	return ""
