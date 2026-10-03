class_name Dialogue
extends Control
## The visual-novel layer: dimmed backdrop, the girl's sprite, a name plate, a
## typewriter text box, choice buttons and a topic menu.
##
## Scripts are plain arrays of step dictionaries so content stays in JSON:
##   {"text": "...", "id": "vaelira"}          a line, optionally with choices
##   {"text": "...", "choices": [ {...}, ... ]}  a line that then offers choices
##   {"id": "vaelira", "choices": [ ... ]}       choices with no line of text
##   {"menu": "vaelira"}                          the talk-about-things menu
## A choice entry: {"text","reply","affection","charm","suspicion","end"}

signal finished
signal ending_reached(char_id: String, option: Dictionary)

const BOX_RECT := Rect2(56, 486, 1168, 194)
const CHARS_PER_SEC := 62.0
const SKIP_MULTIPLIER := 7.0

var _dim: ColorRect
var _sprite: Sprite2D
var _name_panel: PanelContainer
var _name_label: Label
var _box: PanelContainer
var _text: Label
var _choices: VBoxContainer
var _hint: Label
var _toasts: VBoxContainer

var _steps: Array = []
var _idx := -1
var _typing := false
var _typed := 0.0
var _awaiting_choice := false
var _sprite_id := ""
var _menu_char := ""
var _active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.03, 0.02, 0.06, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)

	_box = UIKit.panel(Color(0.07, 0.05, 0.10, 0.93), Color(0.42, 0.30, 0.52, 0.9), 14)
	_box.position = BOX_RECT.position
	_box.size = BOX_RECT.size
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	_box.add_child(stack)

	_text = UIKit.body_label("", 23)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(_text)

	# Choices live in their own column above the text box. Inside the box they
	# overflowed straight off the bottom of the screen once a menu had five rows.
	_choices = VBoxContainer.new()
	_choices.position = Vector2(330, 182)
	_choices.size = Vector2(620, 0)
	_choices.add_theme_constant_override("separation", 7)
	_choices.visible = false
	add_child(_choices)

	_name_panel = UIKit.panel(Color(0.10, 0.07, 0.14, 0.96), UIKit.ACCENT, 9)
	_name_panel.position = Vector2(BOX_RECT.position.x + 18, BOX_RECT.position.y - 30)
	_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_panel)
	_name_label = UIKit.label("", 22, UIKit.INK, true)
	_name_panel.add_child(_name_label)

	_hint = UIKit.label("\u25bc", 20, Color(1, 1, 1, 0.75))
	_hint.position = Vector2(BOX_RECT.position.x + BOX_RECT.size.x - 40,
			BOX_RECT.position.y + BOX_RECT.size.y - 40)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(950, 76)
	_toasts.size = Vector2(300, 300)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)


# --- public API ------------------------------------------------------------

func is_open() -> bool:
	return _active


## Advance the current line. Public so tests/autoplay can drive a scene.
func advance() -> void:
	if _active:
		_advance()


## Press the nth visible choice, exactly as a click would. Returns false when no
## choice is currently offered (or that choice is disabled). Exists so the game
## can drive itself in tests.
func choose(index: int) -> bool:
	if not _active or not _awaiting_choice:
		return false
	var buttons := _choices.get_children()
	if index < 0 or index >= buttons.size():
		return false
	var b := buttons[index]
	if b is Button:
		var btn := b as Button
		if btn.disabled:
			return false
		btn.pressed.emit()
		return true
	return false


## How many choices are on offer right now.
func choice_count() -> int:
	if not _active or not _awaiting_choice:
		return 0
	return _choices.get_child_count()


func open(steps: Array) -> void:
	if steps.is_empty():
		finished.emit()
		return
	_steps = steps.duplicate()
	_idx = -1
	_active = true
	visible = true
	_sprite_id = ""
	_sprite.texture = null
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 0.55, 0.18)
	_next()


func close() -> void:
	_active = false
	_awaiting_choice = false
	_choices.visible = false
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 0.0, 0.15)
	tw.tween_callback(func() -> void:
		visible = false
		finished.emit())


# --- step machinery --------------------------------------------------------

func _next() -> void:
	_idx += 1
	if _idx >= _steps.size():
		close()
		return
	_show_step(_steps[_idx])


func _show_step(step: Dictionary) -> void:
	if step.has("close"):
		close()
		return
	if step.has("menu"):
		_menu_char = str(step["menu"])
		_show_menu()
		return
	# A step attributed to the main character shows a name plate (Yuuji) with no
	# sprite; it is not interactive, just his scripted opening line.
	if step.has("speaker"):
		_set_sprite("")
		_set_speaker_named(str(step["speaker"]),
				Color.from_string(str(step.get("colour", "#d9a0ff")), Color(0.85, 0.63, 1.0)))
		var ptext := str(step.get("text", ""))
		if ptext.is_empty():
			_text.text = ""
			_typing = false
			_hint.visible = false
			if step.has("choices"):
				_show_choices(step["choices"])
			else:
				_next()
			return
		_text.text = ptext
		_text.visible_characters = 0
		_typed = 0.0
		_typing = true
		_hint.visible = false
		_choices.visible = false
		_awaiting_choice = false
		_pending_choices = step.get("choices", [])
		return
	var id := str(step.get("id", ""))
	_set_sprite(id)
	if not id.is_empty():
		_set_speaker(id)
	else:
		_name_panel.visible = false
	var text := str(step.get("text", ""))
	if text.is_empty():
		# Choices-only step: no line to type, go straight to the buttons.
		_text.text = ""
		_typing = false
		_hint.visible = false
		if step.has("choices"):
			_show_choices(step["choices"])
		else:
			_next()
		return
	_text.text = text
	_text.visible_characters = 0
	_typed = 0.0
	_typing = true
	_hint.visible = false
	_choices.visible = false
	_awaiting_choice = false
	_pending_choices = step.get("choices", [])


var _pending_choices: Array = []


func _set_sprite(id: String) -> void:
	if id == _sprite_id:
		return
	_sprite_id = id
	if id.is_empty():
		_sprite.texture = null
		return
	var path := "res://assets/sprites/%s.png" % id
	if not ResourceLoader.exists(path):
		_sprite.texture = null
		return
	_sprite.texture = load(path)
	# Fit the sprite to the screen height and anchor its feet near the bottom
	# right, which is the conventional visual-novel staging.
	var size: Vector2 = _sprite.texture.get_size()
	var target_h := 690.0
	var scale := target_h / size.y
	_sprite.scale = Vector2(scale, scale)
	var w := size.x * scale
	_sprite.position = Vector2(1020.0 - w * 0.5, 720.0 - target_h)


func _set_speaker(id: String) -> void:
	var colour := Cast.color_of(id)
	_set_speaker_named(Cast.display_name(id), colour)


func _set_speaker_named(name: String, colour: Color) -> void:
	_name_label.text = "  %s  " % name
	_name_panel.visible = true
	_name_panel.add_theme_stylebox_override("panel",
			UIKit.panel_style(Color(colour.r * 0.22, colour.g * 0.22, colour.b * 0.28, 0.97),
					colour, 9))
	_name_panel.size = Vector2.ZERO
	_name_panel.reset_size()


func _process(delta: float) -> void:
	if not _active:
		return
	if _typing:
		var speed := CHARS_PER_SEC
		if Input.is_key_pressed(KEY_CTRL):
			speed *= SKIP_MULTIPLIER
		_typed += speed * delta
		var total := _text.get_total_character_count()
		_text.visible_characters = int(_typed)
		if int(_typed) >= total:
			_finish_typing()
	_hint.visible = not _typing and not _awaiting_choice and _choices.visible == false


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	if not _pending_choices.is_empty():
		var choices: Array = _pending_choices
		_pending_choices = []
		_show_choices(choices)


func _advance() -> void:
	if _awaiting_choice:
		return
	if _typing:
		_finish_typing()
		return
	_next()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("mg_talk") or event.is_action_pressed("mg_back"):
		_advance()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()


# --- choices ---------------------------------------------------------------

func _show_choices(choices: Array) -> void:
	_awaiting_choice = true
	_clear_choices()
	for entry: Variant in choices:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var opt: Dictionary = entry
		var b := UIKit.button(str(opt.get("text", "...")), UIKit.ACCENT, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_choice.bind(opt))
		_choices.add_child(b)
	_choices.visible = true


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()


func _on_choice(opt: Dictionary) -> void:
	_awaiting_choice = false
	_choices.visible = false
	_clear_choices()
	var id := str(opt.get("char", _menu_char))
	var gains := []
	if int(opt.get("affection", 0)) != 0:
		var delta := Game.add_affection(id, int(opt["affection"]))
		if delta != 0:
			gains.append([("+%d Affection" % delta) if delta > 0 else ("%d Affection" % delta),
					Cast.color_of(id)])
	if int(opt.get("charm", 0)) != 0:
		Game.add_charm(int(opt["charm"]))
		gains.append(["+%d Charm" % int(opt["charm"]), Color("#8fd0ff")])
	if int(opt.get("suspicion", 0)) != 0:
		Game.add_suspicion(int(opt["suspicion"]))
		gains.append(["+%d Suspicion" % int(opt["suspicion"]), Color("#ff8a6a")])
	for g: Array in gains:
		_toast(str(g[0]), g[1])

	var followup := []
	if opt.has("reply") and not str(opt["reply"]).is_empty():
		followup.append({"text": str(opt["reply"]), "id": id})
	if opt.has("then"):
		for s: Variant in opt["then"]:
			followup.append(s)
	if bool(opt.get("end", false)) or bool(opt.get("ending", false)):
		followup.append({"close": true})
	_insert_after_current(followup)
	if bool(opt.get("ending", false)):
		ending_reached.emit(id, opt)
	_next()


func _insert_after_current(extra: Array) -> void:
	if extra.is_empty():
		return
	for i in range(extra.size() - 1, -1, -1):
		_steps.insert(_idx + 1, extra[i])


# --- the talk menu ---------------------------------------------------------

func _show_menu() -> void:
	var id := _menu_char
	var aff := Game.get_affection(id)
	_awaiting_choice = true
	_clear_choices()

	_text.text = "%s is waiting for you to say something.%s  [Tokens: %d]" % [
		Cast.display_name(id), _menu_note(aff), Game.tokens]
	_text.visible_characters = -1
	_typing = false
	_hint.visible = false
	_name_panel.visible = false

	var token_colour := Color("#ffd24a")
	_add_topic_button("Just chat" + _cost_suffix(Game.COST_CHAT), id, "chat", Game.COST_CHAT, token_colour)
	_add_topic_button("Flirt with her  \u2665 (risky)" + _cost_suffix(Game.COST_FLIRT), id, "flirt", Game.COST_FLIRT, token_colour)
	_add_topic_button("Compliment her" + _cost_suffix(Game.COST_COMPLIMENT), id, "compliment", Game.COST_COMPLIMENT, token_colour)
	# Ask about herself is free but limited to once per day.
	var ask_avail := Game.ask_available(id)
	var ask_label := "Ask about herself" if ask_avail else "Ask about herself (used today)"
	_add_topic_button(ask_label + _cost_suffix(Game.COST_ASK), id, "ask", Game.COST_ASK, token_colour, ask_avail)

	var leave := UIKit.button("Leave", Color("#8a8aa0"), 18)
	leave.alignment = HORIZONTAL_ALIGNMENT_LEFT
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.pressed.connect(_on_leave)
	_choices.add_child(leave)
	_choices.visible = true


func _cost_suffix(cost: int) -> String:
	if cost <= 0:
		return "   (free)"
	return "   (%d token%s)" % [cost, "s" if cost > 1 else ""]


func _menu_note(aff: int) -> String:
	if aff >= 85:
		return "  She has stopped pretending she is not staring."
	if aff >= 60:
		return "  She stands a little closer than she needs to."
	if aff >= 30:
		return "  She seems genuinely pleased to see you."
	return "  She is very aware that you are the only boy here."


func _add_topic_button(label: String, id: String, category: String, cost: int,
		accent: Color, enabled := true) -> void:
	var b := UIKit.button(label, UIKit.ACCENT, 18)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not (enabled and Game.can_pay(cost))
	b.pressed.connect(_on_topic.bind(id, category, cost))
	_choices.add_child(b)


func _on_topic(id: String, category: String, cost: int) -> void:
	if not Game.can_pay(cost):
		_toast("Not enough tokens", Color("#ff8a6a"))
		return
	if cost > 0:
		if not Game.spend_tokens(cost):
			return
		_toast("- %d Tokens" % cost, Color("#ffd24a"))
	var tier := Game.tier_of(id)
	var outcome: String
	if category == "ask":
		if not Game.ask_available(id):
			return
		Game.mark_asked(id)
		outcome = "success"
	else:
		match category:
			"chat":
				outcome = Rolls.roll_chat(tier)
			"flirt":
				outcome = Rolls.roll_flirt(tier)
			"compliment":
				outcome = Rolls.roll_compliment(tier)
			_:
				outcome = "success"
	_play_topic_exchange(id, category, outcome, tier)


func _play_topic_exchange(id: String, category: String, outcome: String, tier: int) -> void:
	var aff := 0
	var susp := 0
	match category:
		"chat":
			if outcome == "success":
				aff = 1
		"flirt":
			match outcome:
				"success":
					aff = 3
				"neutral":
					aff = 2
					susp = 1
				_:
					susp = 2
		"compliment":
			if outcome == "success":
				aff = 2
			else:
				susp = 1
		"ask":
			aff = 2
	_awaiting_choice = false
	_choices.visible = false
	_clear_choices()
	var gains := []
	if aff != 0:
		var delta := Game.add_affection(id, aff)
		if delta != 0:
			gains.append(["+%d Affection" % delta, Cast.color_of(id)])
	if susp != 0:
		Game.add_suspicion(susp)
		gains.append(["+%d Suspicion" % susp, Color("#ff8a6a")])
	for g: Array in gains:
		_toast(str(g[0]), g[1])
	# Yuuji opens with an option-appropriate line, then the girl reacts to it.
	var follow := []
	var mc := Cast.player_line(id, tier, category)
	if not mc.is_empty():
		follow.append({"text": mc, "speaker": Game.player_name, "colour": "#d9a0ff"})
	follow.append({"text": Cast.pick_outcome(id, category, outcome, Game.get_affection(id)),
			"id": id})
	# Keep the conversation open while the player still has budget; Leave is
	# always offered so nobody is trapped.
	follow.append({"menu": id})
	_insert_after_current(follow)
	_next()


func _on_leave() -> void:
	_awaiting_choice = false
	_choices.visible = false
	_clear_choices()
	close()


# --- feedback --------------------------------------------------------------

func _toast(text: String, colour: Color) -> void:
	var l := UIKit.label(text, 19, colour, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toasts.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
