extends Node
## Global state: the clock, the player's stats, and every relationship.
##
## Autoloaded as `Game`. Everything that needs to survive an area change lives
## here; everything that is pure presentation lives in the scenes.

signal stats_changed
signal time_changed

const PERIODS := ["Morning", "Class", "Lunch", "Afternoon", "Evening"]
const MAX_SUSPICION := 100
const SAVE_PATH := "user://monster_girl_college_save.json"

## Player-facing knobs.
const FLIRT_SUSPICION := 3
const NIGHT_SUSPICION_DECAY := 14

var player_name := "Yuuji"

var day := 1
var period := 1  # index into PERIODS
var charm := 2
var suspicion := 0
var area := "gate"

var affection := {}       # char_id -> int
var met := {}             # char_id -> true
var events_seen := {}     # "char_id:min" -> true
var confessed := ""       # char_id of whoever the run ended on
var ending_title := ""
var ending_text := ""

var seen_intro := false
var run_started := false


func _ready() -> void:
	_register_input()


## Actions are registered at runtime so the project file stays free of the
## verbose Object(InputEventKey, ...) literals Godot writes into [input].
func _register_input() -> void:
	var binds := {
		"mg_up": [KEY_W, KEY_UP],
		"mg_down": [KEY_S, KEY_DOWN],
		"mg_left": [KEY_A, KEY_LEFT],
		"mg_right": [KEY_D, KEY_RIGHT],
		"mg_talk": [KEY_E, KEY_SPACE, KEY_ENTER],
		"mg_menu": [KEY_J, KEY_TAB],
		"mg_back": [KEY_ESCAPE],
	}
	for action: String in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode: int in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)


func period_name() -> String:
	return PERIODS[clampi(period, 0, PERIODS.size() - 1)]


func reset() -> void:
	day = 1
	period = 1
	charm = 2
	suspicion = 0
	area = "gate"
	affection.clear()
	met.clear()
	events_seen.clear()
	confessed = ""
	ending_title = ""
	ending_text = ""
	seen_intro = false
	stats_changed.emit()
	time_changed.emit()


# --- relationships ---------------------------------------------------------

func get_affection(id: String) -> int:
	return int(affection.get(id, 0))


func add_affection(id: String, amount: int) -> int:
	if id == "" or amount == 0:
		return 0
	var before := get_affection(id)
	var after := clampi(before + amount, 0, 100)
	affection[id] = after
	stats_changed.emit()
	return after - before


func has_met(id: String) -> bool:
	return bool(met.get(id, false))


func mark_met(id: String) -> bool:
	## Returns true the first time only.
	if has_met(id):
		return false
	met[id] = true
	stats_changed.emit()
	return true


func tier_of(id: String) -> int:
	return Cast.tier_index(id, get_affection(id))


func add_charm(amount: int) -> void:
	charm = maxi(0, charm + amount)
	stats_changed.emit()


func add_suspicion(amount: int) -> void:
	suspicion = clampi(suspicion + amount, 0, MAX_SUSPICION)
	stats_changed.emit()


func apply_effects(fx: Dictionary) -> void:
	if fx.is_empty():
		return
	if fx.has("affection"):
		add_affection(str(fx.get("char", "")), int(fx["affection"]))
	if fx.has("charm"):
		add_charm(int(fx["charm"]))
	if fx.has("suspicion"):
		add_suspicion(int(fx["suspicion"]))


# --- clock -----------------------------------------------------------------

func advance_period() -> void:
	period += 1
	if period >= PERIODS.size():
		_next_day()
	time_changed.emit()


func _next_day() -> void:
	day += 1
	period = 0
	# Gossip fades overnight; the crisis of yesterday is old news by breakfast.
	add_suspicion(-NIGHT_SUSPICION_DECAY)


func is_outed() -> bool:
	return suspicion >= MAX_SUSPICION


func end_run(title: String, text: String, char_id: String = "") -> void:
	ending_title = title
	ending_text = text
	confessed = char_id
	stats_changed.emit()


# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"day": day,
		"period": period,
		"charm": charm,
		"suspicion": suspicion,
		"area": area,
		"affection": affection,
		"met": met,
		"events_seen": events_seen,
		"confessed": confessed,
		"ending_title": ending_title,
		"ending_text": ending_text,
		"seen_intro": seen_intro,
	}


func from_dict(d: Dictionary) -> void:
	player_name = str(d.get("player_name", "Yuuji"))
	day = int(d.get("day", 1))
	period = int(d.get("period", 1))
	charm = int(d.get("charm", 2))
	suspicion = int(d.get("suspicion", 0))
	area = str(d.get("area", "gate"))
	affection = d.get("affection", {})
	met = d.get("met", {})
	events_seen = d.get("events_seen", {})
	confessed = str(d.get("confessed", ""))
	ending_title = str(d.get("ending_title", ""))
	ending_text = str(d.get("ending_text", ""))
	seen_intro = bool(d.get("seen_intro", false))
	stats_changed.emit()
	time_changed.emit()


func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not open save file for writing: %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save():
		return false
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save file is not valid JSON.")
		return false
	from_dict(parsed)
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
