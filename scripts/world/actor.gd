class_name Actor
extends Node2D
## A character standing in an area: painted sprite + contact shadow.
##
## The node's origin is the character's FEET. That makes depth sorting a matter
## of z_index = y, and it means the world can resize the character as she walks
## toward the camera, which a painted backdrop with a vanishing point requires.

const SHADOW := Color(0.0, 0.0, 0.12, 0.30)

var char_id := ""
var char_name := ""
var height := 0.0          ## drawn height in px, used for click hit tests

var _sprite: Sprite2D
var _tex_height := 1.0
var _shadow_w := 44.0
var _shadow_h := 13.0
var _bob_t := 0.0
var _walking := false
var _base_y := 0.0


func setup(tex: Texture2D, target_height: float, display_name: String, tint: Color = Color.WHITE) -> void:
	char_name = display_name
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = true
		# The art is rendered around 1300px tall and drawn at a fraction of
		# that. Without mipmaps the GPU point-samples a single texel and the
		# result crawls with aliasing -- that is the "pixelated" look.
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(_sprite)
	_sprite.texture = tex
	_sprite.modulate = tint
	_tex_height = maxf(1.0, tex.get_size().y)
	height = 0.0
	set_height(target_height)


## Resize in place. The world calls this as a character moves: people grow as
## they approach the camera, so somebody at the front of a corridor is visibly
## larger than somebody at the back.
func set_height(target_height: float) -> void:
	if _sprite == null or absf(target_height - height) < 0.25:
		return
	height = target_height
	var s := target_height / _tex_height
	_sprite.scale = Vector2(s, s)
	# centered=true draws about the node position, so lift by half the height to
	# put the sprite's bottom edge exactly on the node origin (the feet).
	_base_y = -target_height * 0.5
	_sprite.position = Vector2(0, _base_y)
	_shadow_w = clampf(target_height * 0.20, 14.0, 130.0)
	_shadow_h = _shadow_w * 0.30
	queue_redraw()


func face(direction: float) -> void:
	if _sprite != null and direction != 0.0:
		_sprite.flip_h = direction < 0.0


func set_walking(walking: bool) -> void:
	_walking = walking


func _process(delta: float) -> void:
	if _sprite == null:
		return
	if not _walking:
		if not is_equal_approx(_sprite.position.y, _base_y):
			_sprite.position.y = _base_y
		if not is_equal_approx(_sprite.scale.y, _sprite.scale.x):
			_sprite.scale.y = _sprite.scale.x
		return
	_bob_t += delta * 13.0
	# Two bounces per stride, plus a hair of squash. Scaled off the drawn height
	# so a distant character does not bounce as far as a close one.
	var amp := clampf(height * 0.030, 1.5, 9.0)
	var bob := absf(sin(_bob_t)) * amp
	_sprite.position.y = _base_y - bob
	var squash := 1.0 + sin(_bob_t * 2.0) * 0.012
	_sprite.scale.y = _sprite.scale.x * squash


func _draw() -> void:
	# Soft contact shadow so the character does not look pasted onto the floor.
	_draw_ellipse(Vector2(0, 2), Vector2(_shadow_w, _shadow_h), SHADOW)


func _draw_ellipse(centre: Vector2, radii: Vector2, colour: Color) -> void:
	var points := PackedVector2Array()
	var segments := 24
	for i in segments:
		var a := TAU * float(i) / float(segments)
		points.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, colour)
