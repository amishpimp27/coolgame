extends Node
## Monster Girl College -- top-level orchestrator.
##
## Owns the layers, routes world events into visual-novel scenes, decides what
## happens when a scene ends, and handles the day clock. All UI is built in code
## so the project has no fragile hand-authored .tscn scene trees.

const INTRO := [
	{"text": "Monster Girl College. An institution of higher learning for the "
		+ "daughters of every myth that was ever told."},
	{"text": "You are not a daughter."},
	{"text": "Your acceptance letter arrived addressed to \"Miss Yuuji\", because the "
		+ "interviewer took one look at your face, ticked a box, and stopped reading "
		+ "the form."},
	{"text": "That was two weeks ago. You have been living in the girls' dormitory "
		+ "ever since, wearing the uniform, keeping your voice up, and doing an "
		+ "amount of laundry that has begun to attract comment."},
	{"text": "Then, this morning, something changed. The girls have started "
		+ "*looking* at you. Noticing you. Sniffing, occasionally."},
	{"text": "Try to survive the term. And try not to get caught."},
]

const CLASS_FLAVOUR := [
	"Advanced Hexonomics. Today's topic: the economics of soul-debt.",
	"Introduction to Applied Curses. You are told to pair up. Everybody turns around.",
	"Monstrous Biology. The diagram on the board is anatomically detailed and you "
		+ "spend the entire hour looking at the ceiling.",
	"History of the Blood Wars. Half the class falls asleep. The other half watches you.",
	"Practical Shapeshifting. You are the only student who cannot demonstrate.",
]

var world: World
var hud: HUD
var vn: Dialogue

var _world_layer: CanvasLayer
var _overlay: CanvasLayer
var _fade: ColorRect
var _title: Control
var _journal: Control

var _pending_ending := ""
var _last_day := 1
var _intro_done := false

# Headless-ish verification hooks: --shot=path --shot-delay=3 --auto=new --scene=talk:vilma
var _shot_path := ""
var _shot_delay := 3.0
var _auto := ""
var _scene := ""
var _shot_taken := false
var _autoplay := 0.0
var _autoplay_clock := 0.0
var _selftest := false
var _playtest := false
var _failures := 0
var _checks := 0


func _ready() -> void:
	get_tree().root.theme = UIKit.theme()
	_parse_test_args()
	if _selftest:
		_run_selftest()
		return
	_build_layers()
	if _playtest:
		_run_playtest()
		return
	Game.stats_changed.connect(_refresh)
	Game.time_changed.connect(_on_time_changed)
	_last_day = Game.day
	if _auto == "new":
		_start_new_game()
	elif _auto == "world":
		# Straight into the walk-around, skipping the intro dialogue.
		Game.reset()
		Game.seen_intro = true
		_last_day = Game.day
		_enter_world()
	elif _auto == "continue":
		_continue_game()
	else:
		_show_title()


func _parse_test_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-delay="):
			_shot_delay = float(a.substr(13))
		elif a.begins_with("--auto="):
			_auto = a.substr(7)
		elif a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--autoplay="):
			_autoplay = float(a.substr(11))
		elif a == "--selftest":
			_selftest = true
		elif a == "--playtest":
			_playtest = true


func _build_layers() -> void:
	_world_layer = CanvasLayer.new()
	_world_layer.layer = 0
	add_child(_world_layer)
	world = World.new()
	_world_layer.add_child(world)
	world.talk_requested.connect(_on_talk)
	world.bump_requested.connect(_on_bump)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	hud = HUD.new()
	ui_layer.add_child(hud)
	hud.travel_requested.connect(_travel)
	hud.action_requested.connect(_action)

	var vn_layer := CanvasLayer.new()
	vn_layer.layer = 10
	add_child(vn_layer)
	vn = Dialogue.new()
	vn_layer.add_child(vn)
	vn.finished.connect(_on_dialogue_finished)
	vn.ending_reached.connect(_on_ending)

	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)


# --- front end -------------------------------------------------------------

func _show_title() -> void:
	hud.visible = false
	world.set_locked(true)
	world.visible = false
	_title = TitleScreen.new()
	_title.new_game_pressed.connect(_start_new_game)
	_title.continue_pressed.connect(_continue_game)
	_overlay.add_child(_title)


func _start_new_game() -> void:
	Game.reset()
	_last_day = Game.day
	_enter_world()
	if not Game.seen_intro:
		Game.seen_intro = true
		_gameplay_pause()
		vn.open(INTRO)


func _continue_game() -> void:
	if not Game.load_game():
		_start_new_game()
		return
	_last_day = Game.day
	_enter_world()


func _enter_world() -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	world.visible = true
	world.build(Game.area)
	world.set_locked(false)
	hud.visible = true
	_refresh()
	if not _scene.is_empty():
		_run_scene_arg()


## Test hook so a screenshot can be taken of a specific in-game moment.
func _run_scene_arg() -> void:
	var parts := _scene.split(":")
	if parts.size() < 2:
		return
	var who := parts[1]
	match parts[0]:
		"talk":
			_on_talk(who)
		"meet":
			_on_bump(who)
		"menu":
			Game.mark_met(who)
			Game.add_affection(who, 62)
			_gameplay_pause()
			vn.open([{"menu": who}])
		"journal":
			if who == "demo":
				_demo_populate()
			_action("journal")
		"class":
			_action("class")
		"area":
			Game.area = who
			world.build(who)
			_refresh()
		"ending":
			_demo_populate()
			_show_ending(who)
		"gameover":
			_demo_populate()
			_show_game_over()
		_:
			pass


# --- world routing ---------------------------------------------------------

func _gameplay_pause() -> void:
	world.set_locked(true)
	hud.visible = false


func _refresh() -> void:
	if hud.visible:
		hud.refresh()


func _on_time_changed() -> void:
	if hud.visible:
		hud.refresh()
	if Game.day != _last_day:
		_last_day = Game.day
		_show_day_card()


func _demo_populate() -> void:
	## Screenshot helper: gives the directory something to show.
	var ids := Cast.all_ids()
	for i in ids.size():
		if i < 7:
			Game.mark_met(ids[i])
			Game.add_affection(ids[i], [92, 71, 58, 44, 33, 21, 8][i])


func _travel(area_id: String) -> void:
	if vn.is_open():
		return
	Game.area = area_id
	Game.save_game()
	world.build(area_id)
	_refresh()
	_maybe_encounter(area_id)


## Walking into a new area is how the school ambushes you.
func _maybe_encounter(area_id: String) -> void:
	var present := Cast.present_in(area_id, Game.period)
	var known := []
	for id: String in present:
		if Game.has_met(id):
			known.append(id)
	if known.is_empty() or randf() > 0.3:
		return
	var who: String = known[randi() % known.size()]
	_gameplay_pause()
	vn.open([
		{"text": "You step into the %s. %s" % [Cast.area_name(area_id),
			Cast.pick_encounter(who)], "id": who},
		{"id": who, "choices": [
			{"text": "Talk to her", "then": [{"menu": who}]},
			{"text": "Wave and move on",
				"reply": "You nod at %s and keep walking. She watches you go."
					% Cast.display_name(who), "affection": 1},
		]},
	])


func _on_talk(char_id: String) -> void:
	if vn.is_open() or char_id.is_empty():
		return
	_gameplay_pause()
	if not Game.has_met(char_id):
		_meet(char_id)
		return
	var ev := Cast.pending_event(char_id)
	if not ev.is_empty():
		_play_event(char_id, ev)
		return
	vn.open([{"menu": char_id}])


## The first time you come near somebody, she notices what you are. That is the
## hook of the game, so it happens by proximity rather than by menu.
func _on_bump(char_id: String) -> void:
	if vn.is_open():
		return
	_gameplay_pause()
	_meet(char_id)


func _meet(char_id: String) -> void:
	Game.mark_met(char_id)
	Game.add_affection(char_id, 5)
	Game.save_game()
	var ch := Cast.get_char(char_id)
	var species := str(ch.get("species", "student")).to_lower()
	var notice := ("She stops dead. Her eyes go from your face, to your shoulders, "
		+ "to your shoes, and back to your face. %s is a %s, and she has just "
		+ "worked something out.") % [Cast.display_name(char_id), species]
	vn.open([
		{"text": notice},
		{"text": str(ch.get("greeting", "")), "id": char_id},
		{"menu": char_id},
	])


# --- milestone events ------------------------------------------------------

func _play_event(char_id: String, ev: Dictionary) -> void:
	Game.events_seen[Cast.event_key(char_id, ev)] = true
	Game.save_game()
	var opts := []
	for c: Variant in ev.get("choices", []):
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = (c as Dictionary).duplicate()
		entry["char"] = char_id
		entry["end"] = true
		entry["ending"] = bool(ev.get("ending", false))
		opts.append(entry)
	var steps := [{"text": str(ev.get("title", "")) + "\n\n" + str(ev.get("text", "")),
			"id": char_id}]
	if opts.is_empty():
		steps.append({"text": "You say nothing. The moment passes.", "id": char_id})
	else:
		steps.append({"id": char_id, "choices": opts})
	vn.open(steps)


func _on_ending(char_id: String, _option: Dictionary) -> void:
	_pending_ending = char_id


func _on_dialogue_finished() -> void:
	if not _pending_ending.is_empty():
		_show_ending(_pending_ending)
		_pending_ending = ""
		return
	if Game.is_outed():
		_show_game_over()
		return
	world.set_locked(false)
	hud.visible = true
	_refresh()


# --- actions ---------------------------------------------------------------

func _action(action: String) -> void:
	if vn.is_open():
		return
	match action:
		"journal":
			_open_journal()
		"class":
			_attend_class()
		"wait":
			_pass_time()
		"sleep":
			_sleep()


func _open_journal() -> void:
	if _journal != null:
		return
	_gameplay_pause()
	_journal = Journal.new()
	_journal.closed.connect(func() -> void:
		_journal = null
		if not vn.is_open():
			world.set_locked(false)
			hud.visible = true
	)
	_overlay.add_child(_journal)


func _attend_class() -> void:
	if Game.period != 1:
		return
	_gameplay_pause()
	Game.add_charm(1)
	# Nobody lives in the classroom, so draw the cameo from whoever is on campus
	# during a class period rather than from the room's own roster.
	var present := Cast.anyone_present(1)
	var steps := [{"text": CLASS_FLAVOUR[randi() % CLASS_FLAVOUR.size()]}]
	if not present.is_empty():
		var who: String = present[randi() % present.size()]
		steps.append({"text": "%s leans over. \"%s\"" % [Cast.display_name(who),
				Cast.pick_dialogue(who, Game.tier_of(who), "chat", "success")
						.get("reply", "...")], "id": who})
	steps.append({"text": "You survive the lesson. (+1 Charm)"})
	Game.advance_period()
	vn.open(steps)


func _pass_time() -> void:
	Game.advance_period()
	_refresh()


func _sleep() -> void:
	if Game.period < 4:
		return
	Game.advance_period()
	Game.save_game()


# --- interstitials ---------------------------------------------------------

func _show_day_card() -> void:
	var card := Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.02, 0.06, 0.80)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)
	var label := UIKit.label("Day %d" % Game.day, 54, Color("#ffd7ea"), true)
	label.position = Vector2(0, 300)
	label.size = Vector2(1280, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(label)
	var sub := UIKit.label(_day_flavour(), 22, UIKit.INK_DIM)
	sub.position = Vector2(0, 372)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(sub)
	_overlay.add_child(card)
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.6)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)


func _day_flavour() -> String:
	var met := Game.met.size()
	if met == 0:
		return "You have spoken to nobody yet. The girls are starting to wonder."
	if met < 4:
		return "%d of %d girls have worked out what you are." % [met, Cast.all_ids().size()]
	return "%d of %d girls know. The rumour has legs." % [met, Cast.all_ids().size()]


func _show_ending(char_id: String) -> void:
	var name := Cast.display_name(char_id)
	var text := ("%s takes your hand and does not let go of it for the rest of the "
		% name) + "evening.\n\nShe still does not know how the enrolment paperwork " \
		+ "got that way, and you have decided that this is not the moment to bring " \
		+ "it up.\n\nNobody else found out. For now, that is enough.\n\n" \
		+ "-- END OF ROUTE --"
	_show_fullscreen("ROUTE COMPLETE\n%s" % name, text, Cast.color_of(char_id), char_id)


func _show_game_over() -> void:
	var text := ("Someone finally read the enrolment form out loud in the staff "
		+ "room.\n\nThe student council has questions. The headmistress has more. "
		+ "Your roommate has the most, and she is asking them from very close "
		+ "range.\n\nYou lasted %d days and got to know %d of the %d girls at this "
		+ "school.\n\n-- THE END OF YOUR COVER --") % [Game.day, Game.met.size(),
			Cast.all_ids().size()]
	_show_fullscreen("OUTED", text, Color("#ff6a5c"), "")


func _show_fullscreen(heading: String, body: String, colour: Color,
		char_id: String) -> void:
	_gameplay_pause()
	world.visible = false
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.02, 0.06, 0.95)
	screen.add_child(bg)

	if not char_id.is_empty():
		var bust := TextureRect.new()
		bust.position = Vector2(840, 60)
		bust.custom_minimum_size = Vector2(400, 600)
		bust.size = Vector2(400, 600)
		bust.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path := "res://assets/sprites/%s.png" % char_id
		if ResourceLoader.exists(path):
			bust.texture = load(path)
		screen.add_child(bust)

	var card := UIKit.panel(Color(0.07, 0.05, 0.10, 0.96), colour, 16)
	card.position = Vector2(70, 120)
	card.custom_minimum_size = Vector2(700, 0)
	screen.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	card.add_child(stack)
	stack.add_child(UIKit.label(heading, 38, colour, true))
	var body_label := UIKit.body_label(body, 21)
	body_label.custom_minimum_size = Vector2(650, 0)
	stack.add_child(body_label)
	stack.add_child(UIKit.hsep(6))
	var again := UIKit.button("  Back to the title  ", UIKit.ACCENT, 20)
	again.pressed.connect(func() -> void:
		screen.queue_free()
		world.visible = false
		_show_title()
	)
	stack.add_child(again)

	_overlay.add_child(screen)


# --- per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if hud == null or world == null or vn == null:
		return  # self-test mode tears the scene down before the first frame
	if hud.visible and not vn.is_open() and world.visible:
		hud.set_prompt(world.nearest_npc())
	if _autoplay > 0.0 and vn.is_open():
		_autoplay_clock += delta
		if _autoplay_clock >= _autoplay:
			_autoplay_clock = 0.0
			vn.advance()
	if not _shot_path.is_empty() and not _shot_taken:
		_shot_delay -= delta
		if _shot_delay <= 0.0:
			_shot_taken = true
			_capture_and_quit()


## F11 (or Alt+Enter) toggles fullscreen, the way every other game does it.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey
	if key.echo:
		return
	var wants := key.keycode == KEY_F11 or (key.alt_pressed and key.keycode == KEY_ENTER)
	if not wants:
		return
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
			else DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_viewport().set_input_as_handled()


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("[shot] %s -> %s" % ["saved" if err == OK else "FAILED", _shot_path])
	get_tree().quit()


# --- self test -------------------------------------------------------------

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s" % label)


## Exercises the data + progression rules without rendering anything, so a
## balance or schema mistake surfaces here rather than three hours into a
## playthrough. Run with: godot --headless -- --selftest
func _run_selftest() -> void:
	print("\n=== Monster Girl College self test ===")
	var ids := Cast.all_ids()
	_check(Cast.load_errors.is_empty(), "cast/area JSON parsed with no errors %s"
			% str(Cast.load_errors))
	_check(ids.size() == 12, "12 students loaded (got %d)" % ids.size())
	_check(Cast.area_order.size() == 12, "12 areas loaded (got %d)"
			% Cast.area_order.size())

	# Every character must be fully playable: art, four tiers, four topics.
	for id: String in ids:
		var c := Cast.get_char(id)
		_check(ResourceLoader.exists("res://assets/sprites/%s.png" % id),
				"%s has a sprite" % id)
		_check(ResourceLoader.exists("res://assets/busts/%s.png" % id),
				"%s has a bust" % id)
		var tiers: Array = c.get("tiers", [])
		_check(tiers.size() == 4, "%s has 4 affection tiers" % id)
		var mins := []
		for t: Dictionary in tiers:
			mins.append(int(t.get("min", -1)))
		_check(mins == [0, 30, 60, 85], "%s tier thresholds %s" % [id, str(mins)])
		for cat: String in ["idle", "flirt", "compliment", "lore"]:
			var total := 0
			for t: Dictionary in tiers:
				total += (t.get(cat, []) as Array).size()
			_check(total >= 8, "%s has %s success lines in all tiers (%d)" % [id, cat, total])
		# Roll-outcome lines: each tier needs its neutral/fail variants.
		for cat: String in ["idle_neutral", "flirt_neutral", "flirt_fail", "compliment_fail"]:
			var total2 := 0
			for t: Dictionary in tiers:
				total2 += (t.get(cat, []) as Array).size()
			_check(total2 >= 8, "%s has %s outcome lines in all tiers (%d)" % [id, cat, total2])
		# Exact interaction counts per dialogue option per tier:
		# Just Chat: 4 success + 4 neutral; Flirt: 3/3/3; Compliment: 4/4; Ask: 2.
		var spec := {"idle": 4, "flirt": 3, "compliment": 4, "lore": 2,
				"idle_neutral": 4, "flirt_neutral": 3, "flirt_fail": 3, "compliment_fail": 4}
		for t: Dictionary in tiers:
			for key: String in spec:
				var n := (t.get(key, []) as Array).size()
				_check(n == spec[key], "%s tier %d: %s == %d (got %d)" % [id, int(t.get("min", 0)), key, spec[key], n])
		# The main character's scripted lines: a dict of option pools per tier.
		var player: Array = c.get("player", [])
		_check(player.size() == 4, "%s has 4 player-line tiers (%d)" % [id, player.size()])
		var mc_spec := {"chat": 4, "flirt": 3, "compliment": 4, "ask": 2}
		for t in player.size():
			var tier_pool: Dictionary = player[t]
			for opt: String in mc_spec:
				var n := (tier_pool.get(opt, []) as Array).size()
				_check(n >= mc_spec[opt], "%s player %s at tier %d >= %d (got %d)" % [id, opt, t, mc_spec[opt], n])
		# Outcome + player line lookups never come back empty at any tier.
		for opt in ["chat", "flirt", "compliment", "ask"]:
			_check(not Cast.player_line(id, 0, opt).is_empty(), "%s player_line %s tier 0 non-empty" % [id, opt])
		# Bound (mc, reply) pairs per option+outcome: unique across every tier.
		var used_mc := {}
		var used_reply := {}
		var dspec := {"chat.success": 4, "chat.neutral": 4, "flirt.success": 3,
				"flirt.neutral": 3, "flirt.fail": 3, "compliment.success": 4, "compliment.fail": 4}
		for t: Dictionary in tiers:
			var d: Variant = t.get("dialogue", null)
			_check(typeof(d) == TYPE_DICTIONARY, "%s tier %d has dialogue pairs" % [id, int(t.get("min", 0))])
			if typeof(d) != TYPE_DICTIONARY:
				continue
			for clabel: String in dspec:
				var parts := clabel.split(".")
				var cells: Array = ((d as Dictionary).get(parts[0], {}) as Dictionary).get(parts[1], [])
				_check(cells.size() == dspec[clabel], "%s tier %d %s -> %d pairs (got %d)"
						% [id, int(t.get("min", 0)), clabel, dspec[clabel], cells.size()])
				for pair: Variant in cells:
					var p := pair as Dictionary
					_check(p.has("mc") and not str(p.get("mc", "")).is_empty()
							and p.has("reply") and not str(p.get("reply", "")).is_empty(),
							"%s dialogue pair complete" % id)
					var mk := str(p.get("mc", "")).strip_edges().to_lower()
					_check(not used_mc.has(mk), "%s dialogue MC reused" % id)
					used_mc[mk] = true
					var rk := str(p.get("reply", "")).strip_edges().to_lower()
					_check(not used_reply.has(rk), "%s dialogue reply reused" % id)
					used_reply[rk] = true
			var asks: Array = (d as Dictionary).get("ask", [])
			_check(asks.size() == 2, "%s tier %d ask -> 2 pairs (got %d)" % [id, int(t.get("min", 0)), asks.size()])
			for pair: Variant in asks:
				var p := pair as Dictionary
				if p.has("mc") and not str(p.get("mc", "")).is_empty():
					var mk := str(p.get("mc", "")).strip_edges().to_lower()
					_check(not used_mc.has(mk), "%s dialogue MC reused" % id)
					used_mc[mk] = true
				if p.has("reply") and not str(p.get("reply", "")).is_empty():
					var rk := str(p.get("reply", "")).strip_edges().to_lower()
					_check(not used_reply.has(rk), "%s dialogue reply reused" % id)
					used_reply[rk] = true
		for outcome_cat: Array in [["chat", "success"], ["chat", "neutral"],
				["flirt", "success"], ["flirt", "neutral"], ["flirt", "fail"],
				["compliment", "success"], ["compliment", "fail"], ["ask", "success"]]:
			_check(not Cast.pick_outcome(id, outcome_cat[0], outcome_cat[1], 0).is_empty(),
					"%s %s/%s line at tier 0 non-empty" % [id, outcome_cat[0], outcome_cat[1]])
		var events: Array = c.get("events", [])
		_check(events.size() == 3, "%s has 3 milestone events" % id)
		for e: Variant in events:
			var ev: Dictionary = e
			var choices: Array = ev.get("choices", [])
			var ok := choices.size() >= 2
			for ch: Variant in choices:
				if not (ch as Dictionary).has("text") or not (ch as Dictionary).has("reply"):
					ok = false
			_check(ok, "%s event at %d has >=2 complete choices" % [id, int(ev.get("min", 0))])
		_check(not str(c.get("greeting", "")).is_empty(), "%s has a first-meeting line" % id)

	# Tier resolution at every boundary.
	_check(Cast.tier_index(ids[0], 0) == 0, "affection 0 -> tier 0")
	_check(Cast.tier_index(ids[0], 29) == 0, "affection 29 -> tier 0")
	_check(Cast.tier_index(ids[0], 30) == 1, "affection 30 -> tier 1")
	_check(Cast.tier_index(ids[0], 84) == 2, "affection 84 -> tier 2")
	_check(Cast.tier_index(ids[0], 85) == 3, "affection 85 -> tier 3")
	_check(Cast.tier_index(ids[0], 100) == 3, "affection 100 -> tier 3")

	# Areas: links resolve, resolve symmetrically, and hold every resident.
	for aid: String in Cast.area_order:
		var links: Array = Cast.links_of(aid)
		_check(not links.is_empty(), "%s has at least one exit" % aid)
		for l: Variant in links:
			var target := str(l)
			_check(Cast.areas.has(target), "%s -> %s exists" % [aid, target])
			_check(Cast.links_of(target).has(aid), "%s -> %s is two-way" % [aid, target])
		var capacity := 0
		for p in 5:
			capacity = maxi(capacity, Cast.present_in(aid, p).size())
		_check(capacity <= Cast.slots_of(aid).size(),
				"%s has room for %d residents" % [aid, capacity])

	# NPC scheduling: everyone shows up somewhere, and never in two places.
	var scheduled := {}
	for p in 5:
		for id: String in Cast.anyone_present(p):
			scheduled[id] = true
	for id: String in ids:
		_check(scheduled.has(id), "%s is on campus at some point" % id)
	var max_per_area := {}
	for aid: String in Cast.area_order:
		for p in 5:
			for id: String in Cast.present_in(aid, p):
				var key := "%s:%d" % [id, p]
				_check(not max_per_area.has(key), "%s is only in one place at period %d" % [id, p])
				max_per_area[key] = aid

	# Progression rules.
	Game.reset()
	Game.add_affection(ids[0], 200)
	_check(Game.get_affection(ids[0]) == 100, "affection clamps at 100")
	Game.add_affection(ids[0], -500)
	_check(Game.get_affection(ids[0]) == 0, "affection clamps at 0")

	Game.reset()
	Game.add_affection(ids[0], 30)
	var ev := Cast.pending_event(ids[0])
	_check(int(ev.get("min", -1)) == 30, "milestone 30 unlocks at affection 30")
	Game.events_seen[Cast.event_key(ids[0], ev)] = true
	Game.add_affection(ids[0], 30)
	ev = Cast.pending_event(ids[0])
	_check(int(ev.get("min", -1)) == 60, "milestone 60 unlocks next")
	Game.events_seen[Cast.event_key(ids[0], ev)] = true
	Game.add_affection(ids[0], 30)
	ev = Cast.pending_event(ids[0])
	_check(int(ev.get("min", -1)) == 85, "milestone 85 unlocks last")
	Game.events_seen[Cast.event_key(ids[0], ev)] = true
	_check(Cast.pending_event(ids[0]).is_empty(), "no milestones left once all are seen")

	Game.reset()
	Game.add_suspicion(500)
	_check(Game.suspicion == Game.MAX_SUSPICION, "suspicion clamps at max")
	_check(Game.is_outed(), "max suspicion triggers the outed ending")

	# Conversation budget: fresh tokens each period, strict spend enforcement.
	Game.reset()
	_check(Game.tokens == Game.TOKENS_PER_PERIOD, "a new run starts full of tokens (%d)" % Game.tokens)
	_check(Game.spend_tokens(Game.COST_CHAT), "can afford a Just chat")
	_check(Game.tokens == Game.TOKENS_PER_PERIOD - Game.COST_CHAT, "chat cost deducted")
	_check(Game.spend_tokens(999) == false, "cannot spend more than held")
	Game.tokens = 1
	_check(Game.can_pay(1), "can pay exactly what is held")
	_check(not Game.can_pay(2), "cannot pay above what is held")
	Game.reset()
	Game.advance_period()
	_check(Game.tokens == Game.TOKENS_PER_PERIOD, "period advance refills tokens")

	# Ask about herself: free, once per day, per character.
	Game.reset()
	var ask_id: String = str(ids[0])
	Game.day = 4
	_check(Game.ask_available(ask_id), "ask is available the first time")
	Game.mark_asked(ask_id)
	_check(not Game.ask_available(ask_id), "ask is spent for the day once used")
	Game.day = 5
	_check(Game.ask_available(ask_id), "ask resets on a new day")

	Game.reset()
	Game.period = 4
	Game.add_suspicion(50)
	Game.advance_period()
	_check(Game.day == 2, "evening rolls over into day 2")
	_check(Game.period == 0, "a new day starts in the morning")
	_check(Game.suspicion == 50 - Game.NIGHT_SUSPICION_DECAY,
			"suspicion decays overnight (%d)" % Game.suspicion)

	# Save round trip. Skipped rather than clobbering an existing playthrough.
	if Game.has_save():
		print("  SKIP  save round trip (a real save already exists)")
	else:
		Game.reset()
		Game.day = 7
		Game.period = 3
		Game.charm = 9
		Game.suspicion = 22
		Game.area = "library"
		Game.mark_met(ids[0])
		Game.add_affection(ids[0], 44)
		_check(Game.save_game(), "save writes to disk")
		Game.reset()
		_check(Game.load_game(), "save reads back")
		_check(Game.day == 7 and Game.period == 3 and Game.charm == 9
				and Game.suspicion == 22 and Game.area == "library"
				and Game.get_affection(ids[0]) == 44 and Game.has_met(ids[0]),
				"loaded state matches what was saved")
		Game.delete_save()

	print("=== %d checks, %d failures ===\n" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- play test -------------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Advance an open scene to its natural end: event/encounter choice-screens pick
## the first option, the talk menu always picks Leave (so no tokens are spent).
func _close_scene() -> void:
	var guard := 0
	while vn.is_open() and guard < 200:
		guard += 1
		vn.advance()
		await _wait(0.05)
		var nc := vn.choice_count()
		if nc <= 0:
			continue
		if nc >= 4 and vn.choose(nc - 1):  # the talk menu -> Leave
			await _wait(0.08)
		elif vn.choose(0):                  # event/encounter -> first option
			await _wait(0.08)


## Drives the real UI -- opening scenes, pressing choice buttons, closing them,
## travelling, opening the journal -- so the integration the data self-test
## cannot reach is actually exercised. Run with: godot --headless -- --playtest
func _run_playtest() -> void:
	print("\n=== Monster Girl College play test ===")
	Game.reset()
	Game.seen_intro = true
	_last_day = Game.day
	_enter_world()
	await _wait(0.3)
	_check(world.visible and hud.visible, "world and HUD are live after starting")

	# 1. walking into somebody you have never met, then one Just chat and Leave
	_on_talk("vilma")
	await _wait(0.3)
	_check(vn.is_open(), "talking to an unmet girl opens a scene")
	_check(Game.has_met("vilma"), "the first meeting marks her as met")
	_check(not hud.visible, "the HUD hides during a scene")
	var tk_before := Game.tokens
	var guard := 0
	var chatted := false
	while vn.is_open() and guard < 120:
		guard += 1
		vn.advance()
		await _wait(0.06)
		if not chatted and vn.choice_count() >= 4 and vn.choose(0):
			chatted = true
			await _wait(0.12)
		elif chatted and vn.choice_count() >= 4:
			break
	await _wait(0.25)
	guard = 0
	while vn.is_open() and guard < 100:
		guard += 1
		vn.advance()
		await _wait(0.06)
		if vn.choice_count() >= 4 and vn.choose(vn.choice_count() - 1):
			await _wait(0.12)
			break
	await _wait(0.5)
	_check(not vn.is_open(), "the conversation ends on its own")
	_check(Game.tokens == tk_before - Game.COST_CHAT,
			"one Just chat cost %d token (%d -> %d)" % [Game.COST_CHAT, tk_before, Game.tokens])
	_check(world.visible and hud.visible, "the world unlocks again after the scene")

	# 2. the milestone event firing on the next conversation (free, no tokens)
	Game.add_affection("vilma", 40)
	_on_talk("vilma")
	await _wait(0.4)
	_check(vn.is_open(), "the milestone event plays on the next conversation")
	_check(Game.events_seen.has("vilma:30"), "the milestone is marked as seen")
	var aff_before := Game.get_affection("vilma")
	await _close_scene()
	await _wait(0.5)
	_check(not vn.is_open(), "the event scene closes")
	_check(Game.get_affection("vilma") >= aff_before, "the event choice applied affection")

	# 3. flirting spends the risky option's tokens (suspicion is now a roll)
	Game.suspicion = 0
	var tk_flirt := Game.tokens
	_on_talk("vilma")
	await _wait(0.3)
	guard = 0
	var flirted := false
	while vn.is_open() and guard < 80 and not flirted:
		guard += 1
		vn.advance()
		await _wait(0.07)
		if vn.choice_count() >= 4 and vn.choose(1):
			flirted = true
			await _wait(0.12)
	while vn.is_open() and guard < 140:
		guard += 1
		vn.advance()
		await _wait(0.06)
		if vn.choice_count() >= 4 and vn.choose(vn.choice_count() - 1):
			await _wait(0.1)
			break
	await _wait(0.5)
	_check(Game.tokens == tk_flirt - Game.COST_FLIRT,
			"one Flirt cost %d tokens (%d -> %d)" % [Game.COST_FLIRT, tk_flirt, Game.tokens])

	# 4. travelling and whatever is waiting in the next room
	_travel("cafeteria")
	await _wait(0.4)
	_check(Game.area == "cafeteria", "travel moved the player")
	await _close_scene()
	await _wait(0.5)
	_check(not vn.is_open(), "any travel encounter closed")
	_check(hud.visible, "the HUD returns after a travel encounter")

	# 5. the journal
	_action("journal")
	await _wait(0.4)
	_check(_journal != null, "the journal opens")
	if _journal != null:
		_journal._dismiss()
	await _wait(0.4)
	_check(_journal == null and hud.visible, "the journal closes and play resumes")

	# 6. class, and the clock rolling over (which also refills tokens)
	Game.period = 1
	var day_before := Game.day
	var charm_before := Game.charm
	_action("class")
	await _wait(0.4)
	_check(Game.charm > charm_before, "attending class raised charm")
	await _close_scene()
	_check(Game.period != 1, "attending class advanced the clock")
	_check(Game.tokens == Game.TOKENS_PER_PERIOD, "a new period refilled tokens")
	Game.period = 4
	_action("wait")
	await _wait(0.6)
	_check(Game.day == day_before + 1, "the evening rolls over into a new day")

	# 7. getting caught
	Game.add_suspicion(Game.MAX_SUSPICION)
	_on_talk("vilma")
	await _wait(0.4)
	await _close_scene()
	await _wait(0.7)
	_check(not hud.visible and not world.visible, "max suspicion ends the run")

	print("=== %d checks, %d failures ===\n" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
