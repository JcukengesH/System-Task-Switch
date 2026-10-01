class_name StatBar
extends Control

enum Style { SIMPLE, SEGMENTS }

@export var style: int = Style.SIMPLE
@export var max_value: float = 100.0
@export var segments: int = 4
@export var font_size: int = 16
@export var fill_char: String = "#"
@export var empty_char: String = "."
@export var sep_char: String = "|"
@export var color_filled: Color = Color.WHITE
@export var color_empty: Color = Color(0.25, 0.25, 0.25, 1.0)
@export var color_border: Color = Color(0.75, 0.75, 0.75, 1.0)

var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, max_value)
		queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var sample_size: Vector2 = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ch_w: float = sample_size.x
	var ch_h: float = sample_size.y
	if ch_w <= 0.0 or ch_h <= 0.0:
		return

	var cols: int = int(floor(size.x / ch_w))
	if cols < 4:
		cols = 4
	var inner: int = cols - 2
	# Позиция базовой линии текста — примерно вертикальный центр.
	var baseline_y: float = (size.y + ch_h) * 0.5

	# Скобки по краям.
	draw_string(font, Vector2(0.0, baseline_y), "[", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color_border)
	draw_string(font, Vector2(float(cols - 1) * ch_w, baseline_y), "]", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color_border)

	if style == Style.SEGMENTS and segments > 1:
		var seg_inner: int = (inner - (segments - 1)) / segments
		if seg_inner < 1:
			seg_inner = 1
		var seg_span: float = max_value / float(segments)
		var x_char: int = 1
		for s in range(segments):
			var seg_value: float = clampf(value - float(s) * seg_span, 0.0, seg_span)
			var frac: float = seg_value / seg_span
			var filled: int = int(round(float(seg_inner) * frac))
			for i in range(seg_inner):
				var ch: String = fill_char if i < filled else empty_char
				var col: Color = color_filled if i < filled else color_empty
				draw_string(font, Vector2(float(x_char + i) * ch_w, baseline_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
			x_char += seg_inner
			if s < segments - 1:
				draw_string(font, Vector2(float(x_char) * ch_w, baseline_y), sep_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color_border)
				x_char += 1
	else:
		var frac: float = (value / max_value) if max_value > 0.0 else 0.0
		var filled: int = int(round(float(inner) * frac))
		for i in range(inner):
			var ch: String = fill_char if i < filled else empty_char
			var col: Color = color_filled if i < filled else color_empty
			draw_string(font, Vector2(float(1 + i) * ch_w, baseline_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
