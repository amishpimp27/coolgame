class_name Journal
extends Control
## The student directory: everyone you have met, how far along you are, and how
## much of them you still do not know.

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.03, 0.02, 0.06, 0.94)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var head := UIKit.label("Student Directory", 34, Color("#ffd7ea"), true)
	head.position = Vector2(48, 26)
	add_child(head)

	var summary := UIKit.label("Day %d  \u2022  Tokens %d  \u2022  Suspicion %d%%" % [
			Game.day, Game.tokens, Game.suspicion], 19, UIKit.INK_DIM)
	summary.position = Vector2(50, 68)
	add_child(summary)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(44, 106)
	scroll.size = Vector2(1192, 528)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for id: String in Cast.all_ids():
		grid.add_child(_card(id))

	var close := UIKit.button("  Close  [Esc]  ", UIKit.ACCENT, 20)
	close.position = Vector2(1050, 656)
	close.pressed.connect(_dismiss)
	add_child(close)


func _card(id: String) -> Control:
	var known := Game.has_met(id)
	var colour := Cast.color_of(id)
	var card := UIKit.panel(Color(0.08, 0.06, 0.11, 0.95),
			Color(colour.r, colour.g, colour.b, 0.55), 12)
	card.custom_minimum_size = Vector2(380, 168)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var bust := TextureRect.new()
	bust.custom_minimum_size = Vector2(96, 144)
	bust.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var bust_path := "res://assets/busts/%s.png" % id
	if known and ResourceLoader.exists(bust_path):
		bust.texture = load(bust_path)
	elif known:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(colour)
		bust.texture = ImageTexture.create_from_image(img)
	row.add_child(bust)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	if not known:
		col.add_child(UIKit.label("? ? ?", 22, UIKit.INK_DIM, true))
		col.add_child(UIKit.label("You have not met her yet.", 16, UIKit.INK_DIM))
		return card

	col.add_child(UIKit.label(Cast.display_name(id), 21, colour, true))
	var ch := Cast.get_char(id)
	# Without autowrap a Label's minimum width is its whole text, which pushes
	# the third grid column off the screen.
	var subt := UIKit.body_label("%s \u2014 %s" % [ch.get("species", ""), ch.get("title", "")],
			15, UIKit.INK_DIM)
	subt.custom_minimum_size = Vector2(232, 0)
	col.add_child(subt)
	var aff := Game.get_affection(id)
	var bar := UIKit.hue_bar(aff, 100, colour, 240, 13)
	col.add_child(bar)
	col.add_child(UIKit.label("%s   %d/100" % [Cast.tier_label(id, aff), aff], 16,
			UIKit.INK))
	var bio := UIKit.body_label(str(ch.get("bio", "")), 14, UIKit.INK_DIM)
	bio.custom_minimum_size = Vector2(232, 0)
	col.add_child(bio)
	return card


func _dismiss() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mg_back") or event.is_action_pressed("mg_menu"):
		_dismiss()
		get_viewport().set_input_as_handled()
