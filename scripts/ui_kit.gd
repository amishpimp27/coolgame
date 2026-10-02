class_name UIKit
extends RefCounted
## Small builders for a consistent look, so every screen is not re-inventing
## StyleBoxFlat with slightly different numbers.

const INK := Color("#f6eef6")
const INK_DIM := Color("#b6a8bd")
const PANEL_BG := Color("#150f1c")
const PANEL_BG_LIGHT := Color("#241a2e")
const ACCENT := Color("#ff6fae")

const FONT_BODY := "res://assets/fonts/segoeui.ttf"
const FONT_BOLD := "res://assets/fonts/segoeuib.ttf"
const FONT_ITALIC := "res://assets/fonts/segoeuii.ttf"


static func font(bold := false, italic := false) -> FontFile:
	var path := FONT_BODY
	if bold:
		path = FONT_BOLD
	elif italic:
		path = FONT_ITALIC
	if ResourceLoader.exists(path):
		var f: Variant = load(path)
		if f is Font:
			return f
	return null


static func theme() -> Theme:
	var t := Theme.new()
	var body := font()
	if body != null:
		t.default_font = body
	t.default_font_size = 20
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "RichTextLabel", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_color", "CheckBox", INK)
	return t


static func panel_style(bg: Color = PANEL_BG, border: Color = Color("#3a2b48"),
		radius := 10, border_width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func panel(bg: Color = PANEL_BG, border: Color = Color("#3a2b48"),
		radius := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border, radius))
	return p


static func label(text: String, size := 20, colour: Color = INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	var f := font(bold)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4 if size <= 26 else 0)
	return l


## Wrapping body text with a readable surface behind it.
static func body_label(text: String, size := 22, colour: Color = INK) -> Label:
	var l := label(text, size, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, accent: Color = ACCENT, size := 19) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var f := font(true)
	if f != null:
		b.add_theme_font_override("font", f)
	var normal := panel_style(PANEL_BG_LIGHT, Color(accent.r, accent.g, accent.b, 0.45), 8, 2)
	var hover := panel_style(Color(accent.r, accent.g, accent.b, 0.22), accent, 8, 2)
	var pressed := panel_style(Color(accent.r, accent.g, accent.b, 0.35), accent, 8, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


static func hsep(height := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func hue_bar(value: float, maximum: float, fill: Color, width := 160.0,
		height := 14.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = maximum
	pb.value = clampf(value, 0.0, maximum)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(int(height * 0.5))
	bg.border_color = Color(1, 1, 1, 0.16)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(int(height * 0.5))
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb
