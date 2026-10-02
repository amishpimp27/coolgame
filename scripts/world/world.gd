class_name World
extends Node2D
## The walk-around layer for one area: painted backdrop, the girls standing in
## it, and the player. Movement is locked while a dialogue is open.

signal talk_requested(char_id: String)
signal bump_requested(char_id: String)

## Height in px of a character standing at the FRONT edge of the walkable band.
## Characters are scaled between this and FAR_RATIO of it depending on how far up
## the screen they are, so they sit in the backdrop's perspective instead of
## floating at one fixed size regardless of depth.
const NEAR_HEIGHT := 310.0
const FAR_RATIO := 0.52
const PLAYER_BODY := 0.97    ## the player reads a touch shorter than the girls
const SPEED := 300.0
const TALK_RANGE := 118.0
const BUMP_RANGE := 96.0
const HAIL_INTERVAL := 7.5   # seconds of walking before someone may call out
const HAIL_CHANCE := 0.18

var area_id := ""
var _bg: Sprite2D
var _player: Actor
var _npcs := {}          # char_id -> Actor
var _player_pos := Vector2(640, 600)
var _facing := 1.0
var _locked := false
var _walk_since_hail := 0.0
var _move_clock := 0.0

var _walk_top := 330.0
var _walk_bottom := 655.0
var _area_scale := 1.0


func _ready() -> void:
	z_as_relative = true


func build(new_area_id: String, spawn_at: Variant = null) -> void:
	area_id = new_area_id
	for child in get_children():
		child.queue_free()
	_npcs.clear()
	_player = null

	_walk_top = float(Cast.area_def(area_id).get("walk_top", 330))
	_walk_bottom = float(Cast.area_def(area_id).get("walk_bottom", 655))
	# Each painted backdrop has its own implied scale; char_scale trims the
	# character height so they do not tower over a room or vanish in a corridor.
	_area_scale = float(Cast.area_def(area_id).get("char_scale", 1.0))

	_bg = Sprite2D.new()
	var bg_path := "res://assets/backgrounds/%s.png" % Cast.area_bg(area_id)
	if ResourceLoader.exists(bg_path):
		_bg.texture = load(bg_path)
	_bg.centered = false
	_bg.z_index = -100
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_bg)

	_player_pos = Cast.spawn_of(area_id) if spawn_at == null else spawn_at
	_spawn_npcs()
	_spawn_player()
	_walk_since_hail = 0.0


## Character height for a given feet position. Painted backdrops have a
## vanishing point; a sprite that ignores it reads as a sticker pasted flat on
## the floor, and two girls at different depths come out wrongly the same size.
func _height_at(y: float) -> float:
	var span := maxf(1.0, _walk_bottom - _walk_top)
	var t := clampf((y - _walk_top) / span, 0.0, 1.0)
	return NEAR_HEIGHT * _area_scale * lerpf(FAR_RATIO, 1.0, t)


func _spawn_player() -> void:
	_player = Actor.new()
	_player.z_index = int(_player_pos.y)
	_player.face(1.0)
	add_child(_player)
	var tex := load_sprite("player")
	if tex != null:
		_player.setup(tex, _height_at(_player_pos.y) * PLAYER_BODY, Game.player_name)
	_player.position = _player_pos


func _spawn_npcs() -> void:
	var present := Cast.present_in(area_id, Game.period)
	var slots := Cast.slots_of(area_id)
	for i in present.size():
		var id: String = present[i]
		var slot: Array = slots[i % slots.size()]
		var npc := Actor.new()
		npc.char_id = id
		npc.position = Vector2(float(slot[0]), float(slot[1]))
		npc.z_index = int(npc.position.y)
		add_child(npc)
		var tex := load_sprite(id)
		if tex != null:
			var h := _height_at(npc.position.y) \
					* float(Cast.get_char(id).get("height_scale", 1.0))
			npc.setup(tex, h, Cast.display_name(id))
		else:
			# No art for this id: fall back to a coloured silhouette so the
			# area is still playable and the missing asset is obvious.
			npc.setup(placeholder_texture(Cast.color_of(id)),
					_height_at(npc.position.y), Cast.display_name(id))
		_npcs[id] = npc


func load_sprite(id: String) -> Texture2D:
	var path := "res://assets/sprites/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("[World] missing sprite for '%s'" % id)
	return null


func placeholder_texture(colour: Color) -> Texture2D:
	var img := Image.create(64, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(colour.r, colour.g, colour.b, 0.85))
	return ImageTexture.create_from_image(img)


func set_locked(value: bool) -> void:
	_locked = value
	if _locked and _player != null:
		_player.set_walking(false)


func nearest_npc() -> String:
	if _player == null:
		return ""
	var best := ""
	var best_dist := TALK_RANGE
	for id: String in _npcs:
		var d: float = _npcs[id].position.distance_to(_player.position)
		if d < best_dist:
			best_dist = d
			best = id
	return best


func _process(delta: float) -> void:
	if _player == null:
		return
	var dir := Vector2.ZERO
	if not _locked:
		dir = Input.get_vector("mg_left", "mg_right", "mg_up", "mg_down")
	if dir.length_squared() > 0.01:
		dir = dir.normalized()
		_player_pos += dir * SPEED * delta
		_player_pos.x = clampf(_player_pos.x, 70.0, 1210.0)
		_player_pos.y = clampf(_player_pos.y, _walk_top, _walk_bottom)
		if absf(dir.x) > 0.1:
			_facing = signf(dir.x)
		_player.face(_facing)
		_player.set_walking(true)
		_move_clock += delta
		_walk_since_hail += delta
		if _walk_since_hail >= HAIL_INTERVAL:
			_walk_since_hail = 0.0
			_maybe_hail()
	else:
		_player.set_walking(false)
	_player.position = _player_pos
	_player.z_index = int(_player_pos.y)
	# Resize as he walks, so approaching the camera grows him.
	_player.set_height(_height_at(_player_pos.y) * PLAYER_BODY)
	_check_bump()


## Meeting somebody for the first time happens by walking into them, which is
## the whole premise of the game rather than a menu choice.
func _check_bump() -> void:
	if _locked:
		return
	for id: String in _npcs:
		if Game.has_met(id):
			continue
		if _npcs[id].position.distance_to(_player.position) < BUMP_RANGE:
			bump_requested.emit(id)
			return


func _maybe_hail() -> void:
	if _locked or _npcs.is_empty():
		return
	if randf() > HAIL_CHANCE:
		return
	var ids: Array = _npcs.keys()
	for _i in 6:
		var id: String = ids[randi() % ids.size()]
		if Game.has_met(id):
			talk_requested.emit(id)
			return


func _unhandled_input(event: InputEvent) -> void:
	if _locked or _player == null:
		return
	if event.is_action_pressed("mg_talk"):
		var id := nearest_npc()
		if id != "":
			talk_requested.emit(id)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# Clicking a girl is the other obvious way to talk to her.
			var world_pos := get_global_mouse_position()
			for cid: String in _npcs:
				var npc: Actor = _npcs[cid]
				var half_w: float = maxf(40.0, npc.height * 0.30)
				if absf(world_pos.x - npc.position.x) < half_w \
						and world_pos.y > npc.position.y - npc.height \
						and world_pos.y < npc.position.y + 26.0:
					talk_requested.emit(cid)
					get_viewport().set_input_as_handled()
					return
