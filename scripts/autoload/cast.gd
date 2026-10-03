extends Node
## The student body: loads data/cast_*.json and data/areas.json, and answers
## every question the rest of the game has about them.
##
## Autoloaded as `Cast`. Loading is lazy so autoload order never matters.

const CAST_FILES := ["res://data/cast_a.json", "res://data/cast_b.json"]
const AREA_FILE := "res://data/areas.json"

const TIER_LABELS := ["Stranger", "Friend", "Close", "Lover"]

var chars := {}          # id -> Dictionary
var order := []          # ids, stable and in file order
var areas := {}          # id -> Dictionary
var area_order := []
var start_area := "gate"

var _loaded := false
var load_errors := []


func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in CAST_FILES:
		var parsed: Variant = _load_json(path)
		if typeof(parsed) != TYPE_ARRAY:
			load_errors.append("cast file unusable: %s" % path)
			continue
		for entry: Variant in parsed:
			if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
				load_errors.append("bad character entry in %s" % path)
				continue
			var id := str(entry["id"])
			_normalise(entry)
			chars[id] = entry
			order.append(id)
	var area_doc: Variant = _load_json(AREA_FILE)
	if typeof(area_doc) == TYPE_DICTIONARY:
		start_area = str(area_doc.get("start", "gate"))
		for a: Variant in area_doc.get("areas", []):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			areas[str(a["id"])] = a
			area_order.append(str(a["id"]))
	if load_errors.is_empty():
		print("[Cast] loaded %d students across %d areas" % [order.size(), area_order.size()])
	else:
		for e: String in load_errors:
			push_warning("[Cast] %s" % e)


func _load_json(path: String) -> Variant:
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is JSON and res.data != null:
			return res.data
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_error("[Cast] could not parse %s" % path)
	return parsed


## Fills in the fields the UI assumes exist so a sloppy cast file cannot crash
## the game mid-scene.
func _normalise(c: Dictionary) -> void:
	c["name"] = str(c.get("name", c["id"].capitalize()))
	c["species"] = str(c.get("species", "Unknown"))
	c["title"] = str(c.get("title", ""))
	c["color"] = str(c.get("color", "#f0c0d8"))
	c["home_area"] = str(c.get("home_area", "hallway"))
	c["bio"] = str(c.get("bio", ""))
	c["greeting"] = str(c.get("greeting", "She looks at you. Then looks again."))
	c["height_scale"] = float(c.get("height_scale", 1.0))
	c["active_periods"] = c.get("active_periods", [0, 1, 2, 3, 4])
	c["tiers"] = c.get("tiers", [])
	c["events"] = c.get("events", [])
	# The main character's scripted (non-interactive) opening lines, keyed by the
	# dialogue option, per affection tier:
	#   player = [ tier0 = {chat:[], flirt:[], compliment:[], ask:[]}, ... ] (4 tiers)
	c["player"] = c.get("player", [
		{"chat": [], "flirt": [], "compliment": [], "ask": []},
		{"chat": [], "flirt": [], "compliment": [], "ask": []},
		{"chat": [], "flirt": [], "compliment": [], "ask": []},
		{"chat": [], "flirt": [], "compliment": [], "ask": []},
	])
	if not c.has("encounter") or typeof(c["encounter"]) != TYPE_ARRAY:
		c["encounter"] = ["She almost walks straight into you."]
	# Guarantee every conversation bucket exists even if the file was thin.
	# The four base keys are the SUCCESS lines; the _neutral/_fail variants feed
	# the corresponding bad roll outcomes.
	for t: Dictionary in c["tiers"]:
		for key: String in ["idle", "flirt", "compliment", "lore",
				"idle_neutral", "flirt_neutral", "flirt_fail", "compliment_fail"]:
			if typeof(t.get(key, null)) != TYPE_ARRAY or (t[key] as Array).is_empty():
				t[key] = ["..."]


func all_ids() -> Array:
	_ensure()
	return order.duplicate()


func get_char(id: String) -> Dictionary:
	_ensure()
	return chars.get(id, {})


func has_char(id: String) -> bool:
	_ensure()
	return chars.has(id)


func display_name(id: String) -> String:
	return str(get_char(id).get("name", id))


func color_of(id: String) -> Color:
	var c := str(get_char(id).get("color", "#f0c0d8"))
	return Color.from_string(c, Color(0.94, 0.75, 0.85))


## Index into the character's own tier list for a given affection value.
func tier_index(id: String, affection_value: int) -> int:
	var c := get_char(id)
	var tiers: Array = c.get("tiers", [])
	var idx := 0
	for i in tiers.size():
		if affection_value >= int(tiers[i].get("min", 0)):
			idx = i
	return idx


func tier_label(id: String, affection_value: int) -> String:
	var idx := tier_index(id, affection_value)
	var tiers: Array = get_char(id).get("tiers", [])
	if idx < tiers.size():
		return str(tiers[idx].get("label", TIER_LABELS[mini(idx, 3)]))
	return TIER_LABELS[mini(idx, 3)]


func tier_bucket(id: String, affection_value: int) -> Dictionary:
	var tiers: Array = get_char(id).get("tiers", [])
	if tiers.is_empty():
		return {"idle": ["..."], "flirt": ["..."], "compliment": ["..."], "lore": ["..."]}
	return tiers[clampi(tier_index(id, affection_value), 0, tiers.size() - 1)]


func pick_line(id: String, category: String, affection_value: int) -> String:
	var bucket := tier_bucket(id, affection_value)
	var pool: Array = bucket.get(category, [])
	if pool.is_empty():
		pool = bucket.get("idle", [])
	if pool.is_empty():
		return "..."
	return str(pool[randi() % pool.size()])


func pick_encounter(id: String) -> String:
	var pool: Array = get_char(id).get("encounter", [])
	if pool.is_empty():
		return "She nearly walks straight into you."
	return str(pool[randi() % pool.size()])


## Maps a chat option + roll outcome to the tier's line bucket and returns a
## random line from it. Fallback chain protects against a thin file.
func pick_outcome(id: String, category: String, outcome: String, affection_value: int) -> String:
	var key: String
	match category:
		"chat":
			key = "idle" if outcome == "success" else "idle_neutral"
		"flirt":
			match outcome:
				"success":
					key = "flirt"
				"neutral":
					key = "flirt_neutral"
				_:
					key = "flirt_fail"
		"compliment":
			key = "compliment" if outcome == "success" else "compliment_fail"
		"ask":
			key = "lore"
		_:
			key = "idle"
	var bucket := tier_bucket(id, affection_value)
	var pool: Array = bucket.get(key, [])
	if pool.is_empty():
		# Fall back to the success flavour, then to anything.
		for alt: String in [key, "idle", "flirt", "compliment", "lore"]:
			pool = bucket.get(alt, [])
			if not pool.is_empty():
				break
	if pool.is_empty():
		return "..."
	return str(pool[randi() % pool.size()])


## A scripted (non-interactive) line from the main character toward this girl at
## the given tier, for the given dialogue option. This is Yuuji's opening line of
## a chat exchange, chosen to pair with the girl's response in that category.
func player_line(id: String, tier_index: int, category: String) -> String:
	var tiers: Array = get_char(id).get("player", [])
	if tiers.is_empty():
		return ""
	var bucket: Variant = tiers[clampi(tier_index, 0, tiers.size() - 1)]
	var pool: Array = []
	if typeof(bucket) == TYPE_DICTIONARY:
		pool = bucket.get(category, [])
		if pool.is_empty():
			for alt: String in ["chat", "flirt", "compliment", "ask"]:
				pool = bucket.get(alt, [])
				if not pool.is_empty():
					break
	elif typeof(bucket) == TYPE_ARRAY:
		pool = bucket  # legacy flat list
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])


## Characters who are in `area_id` right now, in stable cast order.
func present_in(area_id: String, period_index: int) -> Array:
	_ensure()
	var out := []
	for id: String in order:
		var c: Dictionary = chars[id]
		if str(c["home_area"]) != area_id:
			continue
		if not _has_period(c["active_periods"], period_index):
			continue
		out.append(id)
	return out


func anyone_present(period_index: int) -> Array:
	_ensure()
	var out := []
	for id: String in order:
		var c: Dictionary = chars[id]
		if _has_period(c["active_periods"], period_index):
			out.append(id)
	return out


## JSON has no integer type, so Godot parses active_periods as floats and a
## plain Array.has() against an int silently returns false. Compare as ints.
func _has_period(periods: Variant, period_index: int) -> bool:
	if typeof(periods) != TYPE_ARRAY:
		return false
	for p: Variant in periods:
		if int(p) == period_index:
			return true
	return false


# --- areas -----------------------------------------------------------------

func area_def(area_id: String) -> Dictionary:
	_ensure()
	return areas.get(area_id, {})


func area_name(area_id: String) -> String:
	return str(area_def(area_id).get("name", area_id.capitalize()))


func area_bg(area_id: String) -> String:
	return str(area_def(area_id).get("bg", area_id))


func links_of(area_id: String) -> Array:
	return area_def(area_id).get("links", [])


func slots_of(area_id: String) -> Array:
	return area_def(area_id).get("slots", [[300, 470], [700, 450], [1000, 495]])


func spawn_of(area_id: String) -> Vector2:
	var s: Array = area_def(area_id).get("spawn", [640, 600])
	return Vector2(float(s[0]), float(s[1]))


# --- events ----------------------------------------------------------------

## The next unplayed milestone event for this character, or {} if none.
func pending_event(id: String) -> Dictionary:
	var aff := Game.get_affection(id)
	var events: Array = get_char(id).get("events", [])
	var best := {}
	for e: Variant in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var key := "%s:%d" % [id, int(e.get("min", 0))]
		if Game.events_seen.has(key):
			continue
		if aff >= int(e.get("min", 0)):
			if best.is_empty() or int(e["min"]) < int(best.get("min", 0)):
				best = e
	# Already-seen higher tiers should not block; lowest unseen milestone wins.
	return best


func event_key(id: String, e: Dictionary) -> String:
	return "%s:%d" % [id, int(e.get("min", 0))]
