class_name TitleScreen
extends Control
## Front end: key art, title, and the three buttons that matter.

signal new_game_pressed
signal continue_pressed

const BLURB := ("Monster Girl College has three thousand students, one thousand "
		+ "bathrooms, and exactly one boy.\n"
		+ "You are that boy. The paperwork says otherwise.\n\n"
		+ "Talk to the girls. Learn what they are. Do not get caught.")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var bg := Sprite2D.new()
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg.centered = false
	var path := "res://assets/backgrounds/gate.png"
	if ResourceLoader.exists(path):
		bg.texture = load(path)
	add_child(bg)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.04, 0.02, 0.08, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var card := UIKit.panel(Color(0.06, 0.04, 0.09, 0.92), UIKit.ACCENT, 16)
	card.position = Vector2(74, 92)
	card.custom_minimum_size = Vector2(560, 0)
	add_child(card)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	card.add_child(stack)

	var title := UIKit.label("MONSTER GIRL COLLEGE", 46, Color("#ffd7ea"), true)
	stack.add_child(title)
	var sub := UIKit.label("\"the paperwork says you are a girl. the paperwork is wrong.\"",
			19, Color("#ff9ecb"))
	stack.add_child(sub)
	stack.add_child(UIKit.hsep(10))
	var blurb := UIKit.body_label(BLURB, 19, UIKit.INK)
	blurb.custom_minimum_size = Vector2(500, 0)
	stack.add_child(blurb)
	stack.add_child(UIKit.hsep(6))

	var new_b := UIKit.button("  New Game  ", UIKit.ACCENT, 21)
	new_b.pressed.connect(func() -> void: new_game_pressed.emit())
	stack.add_child(new_b)

	if Game.has_save():
		var cont := UIKit.button("  Continue  (Day %d)" % Game.day, Color("#8fd0ff"), 21)
		cont.pressed.connect(func() -> void: continue_pressed.emit())
		stack.add_child(cont)

	var quit := UIKit.button("  Quit  ", Color("#8a8aa0"), 21)
	quit.pressed.connect(func() -> void: get_tree().quit())
	stack.add_child(quit)

	var credit := UIKit.label("Hermes \u00b7 Godot 4.7 \u00b7 sprites generated locally with NoobAI-XL",
			15, UIKit.INK_DIM)
	credit.position = Vector2(80, 678)
	add_child(credit)
