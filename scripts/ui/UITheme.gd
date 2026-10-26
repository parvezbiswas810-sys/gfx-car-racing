class_name UITheme
extends RefCounted
## Shared look and feel for every screen.
##
## Screens are assembled in code rather than stored as .tscn files. That keeps
## the whole interface consistent, makes it trivial to re-skin, and means the
## layout cannot silently break when a theme resource is edited by hand.

const BG_TOP := Color(0.05, 0.07, 0.13)
const BG_BOTTOM := Color(0.10, 0.14, 0.24)
const ACCENT := Color(0.20, 0.72, 1.00)
const ACCENT_WARM := Color(1.00, 0.62, 0.12)
const ACCENT_DANGER := Color(0.95, 0.28, 0.30)
const TEXT := Color(0.94, 0.96, 1.00)
const TEXT_DIM := Color(0.66, 0.71, 0.82)
const PANEL := Color(0.07, 0.10, 0.18, 0.88)

const FONT_BOLD := "res://assets/fonts/UI-Bold.ttf"
const FONT_REGULAR := "res://assets/fonts/UI.ttf"


static func font_bold() -> FontFile:
	if ResourceLoader.exists(FONT_BOLD):
		return load(FONT_BOLD)
	return null


static func font_regular() -> FontFile:
	if ResourceLoader.exists(FONT_REGULAR):
		return load(FONT_REGULAR)
	return null


static func title_font() -> FontFile:
	return font_bold()


# ---------------------------------------------------------------------------
# style boxes
# ---------------------------------------------------------------------------

static func panel_box(colour: Color = PANEL, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.35, 0.45, 0.62, 0.45)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	return sb


static func button_box(fill: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = border
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


static func apply_button_style(button: Button, accent: Color = ACCENT) -> void:
	button.add_theme_stylebox_override("normal", button_box(Color(0.10, 0.14, 0.23, 0.92), Color(0.28, 0.36, 0.52, 0.8)))
	button.add_theme_stylebox_override("hover", button_box(accent.darkened(0.35), accent))
	button.add_theme_stylebox_override("pressed", button_box(accent.darkened(0.15), accent.lightened(0.2)))
	button.add_theme_stylebox_override("focus", button_box(Color(0, 0, 0, 0), accent))
	button.add_theme_stylebox_override("disabled", button_box(Color(0.10, 0.11, 0.14, 0.7), Color(0.25, 0.27, 0.32, 0.6)))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", TEXT_DIM)
	button.add_theme_color_override("font_focus_color", TEXT)
	var f := font_bold()
	if f != null:
		button.add_theme_font_override("font", f)
	button.add_theme_font_size_override("font_size", 22)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_constant_override("outline_size", 0)


# ---------------------------------------------------------------------------
# widgets
# ---------------------------------------------------------------------------

static func make_button(text: String, accent: Color = ACCENT, min_height: float = 58.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, min_height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button_style(b, accent)
	return b


static func make_label(text: String, font_size: int = 20, colour: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	var f := font_bold() if bold else font_regular()
	if f != null:
		l.add_theme_font_override("font", f)
	return l


static func make_title(text: String, font_size: int = 52) -> Label:
	var l := make_label(text, font_size, TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l


static func make_panel(colour: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(colour))
	return p


static func make_vbox(separation: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func make_hbox(separation: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func make_margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	return m


static func make_slider(minimum: float, maximum: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = minimum
	s.max_value = maximum
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


static func make_option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	o.custom_minimum_size = Vector2(240, 52)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var f := font_regular()
	if f != null:
		o.add_theme_font_override("font", f)
	o.add_theme_font_size_override("font_size", 20)
	o.add_theme_color_override("font_color", TEXT)
	o.add_theme_stylebox_override("normal", button_box(Color(0.10, 0.14, 0.23, 0.92), Color(0.28, 0.36, 0.52, 0.8), 10))
	o.add_theme_stylebox_override("hover", button_box(Color(0.14, 0.20, 0.32, 0.95), ACCENT, 10))
	o.add_theme_stylebox_override("pressed", button_box(Color(0.16, 0.24, 0.38, 0.95), ACCENT, 10))
	return o


static func make_check(text: String, pressed: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = pressed
	c.add_theme_font_size_override("font_size", 20)
	c.add_theme_color_override("font_color", TEXT)
	var f := font_regular()
	if f != null:
		c.add_theme_font_override("font", f)
	return c


static func make_field(placeholder: String, text: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(240, 52)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 20)
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	var f := font_regular()
	if f != null:
		e.add_theme_font_override("font", f)
	e.add_theme_stylebox_override("normal", button_box(Color(0.06, 0.09, 0.15, 0.95), Color(0.28, 0.36, 0.52, 0.8), 10))
	e.add_theme_stylebox_override("focus", button_box(Color(0.08, 0.12, 0.20, 0.95), ACCENT, 10))
	return e


static func make_background() -> Control:
	"""Full-screen gradient backdrop shared by all menu screens."""
	var root := Control.new()
	root.name = "Background"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 top_colour : source_color = vec4(0.05, 0.07, 0.13, 1.0);
uniform vec4 bottom_colour : source_color = vec4(0.10, 0.14, 0.24, 1.0);
uniform vec4 accent : source_color = vec4(0.20, 0.72, 1.0, 1.0);

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(bottom_colour.rgb, top_colour.rgb, uv.y);
	// Soft diagonal sheen so the flat gradient does not look like a placeholder.
	float band = smoothstep(0.55, 0.0, abs(uv.x - uv.y * 0.55 - 0.30));
	col += accent.rgb * band * 0.055;
	float vignette = smoothstep(1.05, 0.25, distance(uv, vec2(0.5)));
	col *= mix(0.72, 1.06, vignette);
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("top_colour", BG_TOP)
	mat.set_shader_parameter("bottom_colour", BG_BOTTOM)
	mat.set_shader_parameter("accent", ACCENT)
	grad.material = mat
	root.add_child(grad)
	return root


static func make_screen(title: String, subtitle: String = "") -> Control:
	"""Standard page: backdrop, heading and a centred content column."""
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(make_background())

	var column := VBoxContainer.new()
	column.name = "Content"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var margin := make_margin(28, 18, 28, 18)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(column)
	page.add_child(margin)

	var heading := make_title(title, 46)
	heading.name = "Heading"
	column.add_child(heading)

	if not subtitle.is_empty():
		var sub := make_label(subtitle, 19, TEXT_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.name = "Subtitle"
		column.add_child(sub)
	return page


static func add_footer(page: Control, version: String) -> void:
	var label := make_label(version, 14, Color(0.45, 0.50, 0.60))
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.position = Vector2(-260, -34)
	label.size = Vector2(240, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page.add_child(label)
