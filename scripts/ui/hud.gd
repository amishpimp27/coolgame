class_name HUD
extends Control
## Heads-up display: the clock, the player's stats, the travel bar and the
## contextual "press E" prompt. Hidden whenever a visual-novel scene is open.

signal travel_requested(area_id: String)
signal action_requested(action: String)

var _day_label: Label
var _area_label: Label
var _desc_label: Label
var _charm_label: Label
var _susp_label: Label
var _susp_bar: ProgressBar
var _mood_label: Label
var _prompt: Label
var _travel: HBoxContainer
var _actions: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


func _build() -> void:
	# Readability washes top and bottom so text survives bright backgrounds.
	for band: Rect2 in [Rect2(0, 0, 1280, 92), Rect2(0, 648, 1280, 72)]:
		var c := ColorRect.new()
		c.position = band.position
		c.size = band.size
		c.color = Color(0.03, 0.02, 0.05, 0.55)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)

	var clock := UIKit.panel(Color(0.07, 0.05, 0.10, 0.86), Color(0.45, 0.33, 0.55, 0.9), 10)
	clock.position = Vector2(16, 14)
	add_child(clock)
	var clock_stack := VBoxContainer.new()
	clock_stack.add_theme_constant_override("separation", 2)
	clock.add_child(clock_stack)
	_day_label = UIKit.label("Day 1", 22, UIKit.INK, true)
	clock_stack.add_child(_day_label)
	_area_label = UIKit.label("", 18, Color("#ffc0dd"))
	clock_stack.add_child(_area_label)
	_desc_label = UIKit.label("", 15, UIKit.INK_DIM)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(360, 0)
	clock_stack.add_child(_desc_label)

	var stats := UIKit.panel(Color(0.07, 0.05, 0.10, 0.86), Color(0.45, 0.33, 0.55, 0.9), 10)
	stats.position = Vector2(884, 14)
	stats.custom_minimum_size = Vector2(380, 0)
	add_child(stats)
	var stat_stack := VBoxContainer.new()
	stat_stack.add_theme_constant_override("separation", 5)
	stats.add_child(stat_stack)
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 18)
	stat_stack.add_child(stat_row)
	_charm_label = UIKit.label("", 18)
	stat_row.add_child(_charm_label)
	_susp_label = UIKit.label("", 18)
	stat_row.add_child(_susp_label)
	_susp_bar = UIKit.hue_bar(0, Game.MAX_SUSPICION, Color("#ffb347"), 340, 13)
	stat_stack.add_child(_susp_bar)
	_mood_label = UIKit.label("", 15, UIKit.INK_DIM)
	stat_stack.add_child(_mood_label)

	_prompt = UIKit.label("", 22, Color("#fff0f8"), true)
	_prompt.position = Vector2(0, 604)
	_prompt.size = Vector2(1280, 34)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)

	_travel = HBoxContainer.new()
	_travel.position = Vector2(20, 664)
	_travel.add_theme_constant_override("separation", 8)
	add_child(_travel)

	_actions = HBoxContainer.new()
	_actions.position = Vector2(884, 122)
	_actions.add_theme_constant_override("separation", 8)
	add_child(_actions)


func refresh() -> void:
	_day_label.text = "Day %d  \u2022  %s" % [Game.day, Game.period_name()]
	_area_label.text = Cast.area_name(Game.area)
	_desc_label.text = str(Cast.area_def(Game.area).get("desc", ""))
	_charm_label.text = "Charm %d" % Game.charm
	_susp_label.text = "Suspicion %d%%" % Game.suspicion
	_mood_label.text = _mood()
	_susp_bar.value = Game.suspicion
	var t := float(Game.suspicion) / float(Game.MAX_SUSPICION)
	_susp_bar.add_theme_stylebox_override("fill",
			_flat_fill(Color("#ffb347").lerp(Color("#ff4030"), t)))
	_rebuild_travel()
	_rebuild_actions()


func _mood() -> String:
	if Game.suspicion >= 90:
		return "(they are closing in)"
	if Game.suspicion >= 65:
		return "(people are whispering)"
	if Game.suspicion >= 35:
		return "(some are suspicious)"
	return "(nobody knows)"


func _flat_fill(colour: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(7)
	return sb


func _rebuild_travel() -> void:
	for c in _travel.get_children():
		c.queue_free()
	for link: Variant in Cast.links_of(Game.area):
		var id := str(link)
		var b := UIKit.button(Cast.area_name(id), Color("#8f7bd6"), 16)
		b.pressed.connect(func() -> void: travel_requested.emit(id))
		_travel.add_child(b)


func _rebuild_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()
	_action_button("Journal [J]", "journal", Color("#8fd0ff"))
	if Game.period == 1:
		_action_button("Attend Class", "class", Color("#9ee37d"))
	_action_button("Pass Time", "wait", Color("#e0c060"))
	if Game.period >= 4:
		_action_button("Go to Sleep", "sleep", Color("#c58fd8"))


func _action_button(label: String, action: String, colour: Color) -> void:
	var b := UIKit.button(label, colour, 17)
	b.pressed.connect(func() -> void: action_requested.emit(action))
	_actions.add_child(b)


func set_prompt(char_id: String) -> void:
	if char_id.is_empty():
		_prompt.text = ""
	else:
		var verb := "Talk to" if Game.has_met(char_id) else "Say something to"
		_prompt.text = "[E]  %s %s  \u2014  %s" % [
			verb, Cast.display_name(char_id), Cast.tier_label(char_id,
					Game.get_affection(char_id))]
