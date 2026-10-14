extends Control

enum Mode { NONE, TEXT, SHAPE }

var display_mode: int = Mode.NONE
var is_active_zone: bool = false
var font_regular: Font
var font_bold: Font

# Данные фигур.
var shape_sides: int = 0
var shape_digit: int = 0
var shape_show_digit: bool = true
var shape_second_sides: int = -1
var shape_digit_in_first: bool = true
var shape_digit_text: String = ""
var shape_missing_first: bool = false
var shape_missing_second: bool = false

var content_root: Control
var label: Label

var _pulse: float = 0.0
var _base_scale: Vector2 = Vector2.ONE
var _base_rotation: float = 0.0
var _press_scale: float = 1.0
# Текущий цвет глифа — нужен, чтобы вернуть его после инверсионной вспышки.
var _label_color: Color = Color.WHITE
var _press_tween: Tween
# Фосфорный шлейф верного ответа (CRT ghosting, см. shaders/ghost.gdshader):
# оверлей под контентом, ghost_amount 1->0 ведёт твин.
var _ghost_rect: ColorRect
var _ghost_mat: ShaderMaterial
var _ghost_tween: Tween
var _ghost_value: float = 0.0
# Фигуры (Polymetry) не имеют label — вспышка для них делается тоном линий.
var _shape_flash: bool = false
# «Черточка» под цифрой 6/9: при флипе/повороте она едет вместе с контентом
# и однозначно различает перевёрнутую шестёрку с девяткой.
var _digit_mark: ColorRect


func _ready() -> void:
	custom_minimum_size = Vector2(200, 200)

	content_root = Control.new()
	content_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_root)

	label = Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	content_root.add_child(label)

	# Ghost-оверлей — под контентом (индекс 0), чтобы глифы оставались чёткими.
	var ghost_shader := load("res://shaders/ghost.gdshader")
	if ghost_shader != null:
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = ghost_shader
		_ghost_rect = ColorRect.new()
		_ghost_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ghost_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ghost_rect.material = _ghost_mat
		content_root.add_child(_ghost_rect)
		content_root.move_child(_ghost_rect, 0)

	_digit_mark = ColorRect.new()
	_digit_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_digit_mark.visible = false
	content_root.add_child(_digit_mark)

	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if content_root:
		content_root.pivot_offset = size / 2.0
	_fit_label_font_size()
	_place_digit_mark()
	queue_redraw()


func clear_item() -> void:
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	_press_scale = 1.0
	_shape_flash = false
	display_mode = Mode.NONE
	label.visible = false
	if _digit_mark:
		_digit_mark.visible = false
	_apply_content_transform()
	queue_redraw()


func set_active(value: bool) -> void:
	is_active_zone = value
	queue_redraw()


func set_pulse(v: float) -> void:
	var clamped: float = clampf(v, 0.0, 1.0)
	if absf(clamped - _pulse) < 0.01:
		return
	_pulse = clamped
	queue_redraw()

func play_correct_feedback() -> void:
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	# Единый фидбек для всех режимов (включая Polymetry, где контента Label
	# нет и ранний return съедал вспышку): мгновенная инверсия знака либо
	# яркая вспышка линий фигуры, поверх — фосфорный шлейф (ghosting).
	_press_scale = 1.0
	_apply_content_transform()
	var has_label: bool = label != null and label.visible
	if has_label:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		sb.content_margin_top = 2.0
		sb.content_margin_bottom = 2.0
		label.add_theme_stylebox_override("normal", sb)
		label.add_theme_color_override("font_color", Color.BLACK)
	_shape_flash = display_mode == Mode.SHAPE and not has_label
	if _shape_flash:
		queue_redraw()
	_press_tween = create_tween()
	_press_tween.tween_interval(0.07)
	_press_tween.tween_callback(_end_flash)
	_start_ghost()


func _end_flash() -> void:
	_shape_flash = false
	if label != null and is_instance_valid(label) and label.visible:
		label.remove_theme_stylebox_override("normal")
		label.add_theme_color_override("font_color", _label_color)
	queue_redraw()


# Фосфорный шлейф: вспышка 1.0 -> длинное жёлтое затухание (CRT ghosting).
func _start_ghost() -> void:
	if _ghost_mat == null:
		return
	_ghost_value = 1.0
	_ghost_mat.set_shader_parameter("ghost_amount", 1.0)
	if _ghost_tween and _ghost_tween.is_valid():
		_ghost_tween.kill()
	_ghost_tween = create_tween()
	_ghost_tween.tween_method(_set_ghost, 1.0, 0.0, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _set_ghost(v: float) -> void:
	_ghost_value = v
	if _ghost_mat:
		_ghost_mat.set_shader_parameter("ghost_amount", v)
	# Тон линий фигур зависит от шлейфа — просим перерисовку.
	if _shape_flash or display_mode == Mode.SHAPE:
		queue_redraw()


func set_fonts(regular: Font, bold: Font) -> void:
	font_regular = regular
	font_bold = bold
	if label and font_regular:
		label.add_theme_font_override("font", font_regular)


func set_transform_effect(effect: String) -> void:
	_base_scale = Vector2.ONE
	_base_rotation = 0.0
	match effect:
		"flip-h":
			_base_scale = Vector2(-1, 1)
		"flip-v":
			_base_scale = Vector2(1, -1)
		"rotate-180":
			_base_rotation = 180.0
	_apply_content_transform()
	queue_redraw()


func _apply_content_transform() -> void:
	if content_root == null:
		return
	content_root.pivot_offset = size / 2.0
	content_root.scale = Vector2(_base_scale.x * _press_scale, _base_scale.y * _press_scale)
	content_root.rotation_degrees = _base_rotation


func show_text(text: String, color: Color, inv: bool = false) -> void:
	display_mode = Mode.TEXT
	label.visible = true
	label.text = text
	if inv and font_bold:
		label.add_theme_font_override("font", font_bold)
		_label_color = Color.WHITE
		label.add_theme_color_override("font_color", Color.WHITE)
	else:
		if font_regular:
			label.add_theme_font_override("font", font_regular)
		_label_color = color
		label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	_fit_label_font_size()
	_update_digit_mark(text)
	queue_redraw()


# Различение 6/9 при флипе (HEX): под последней цифрой ставим короткую черту.
# Черточка — ребёнок content_root, поэтому переворачивается вместе с глифом:
# «6 с чёрточкой снизу» в перевёрнутом виде читается однозначно.
func _update_digit_mark(text: String) -> void:
	if _digit_mark == null:
		return
	var mark: bool = text.length() == 2 and (text[1] == "6" or text[1] == "9")
	_digit_mark.visible = mark
	if mark:
		_digit_mark.color = _label_color
		_place_digit_mark()


func _place_digit_mark() -> void:
	if _digit_mark == null or not _digit_mark.visible:
		return
	if label == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var fs: int = label.get_theme_font_size("font_size")
	var font: Font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var cell: float = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if cell <= 0.0:
		return
	# Текст из 2 символов центрирован: последний — на +0.5 ячейки от центра.
	var cx: float = size.x / 2.0 + cell * 0.5
	var h: float = maxf(3.0, fs * 0.07)
	_digit_mark.size = Vector2(cell * 0.62, h)
	_digit_mark.position = Vector2(cx - _digit_mark.size.x / 2.0, size.y / 2.0 + fs * 0.40)


func show_shape(sides: int, digit: int, digit_text: String, show_digit: bool, second_sides: int, digit_in_first: bool, missing_first: bool = false, missing_second: bool = false) -> void:
	display_mode = Mode.SHAPE
	label.visible = false
	shape_sides = sides
	shape_digit = digit
	shape_digit_text = digit_text
	shape_show_digit = show_digit
	shape_second_sides = second_sides
	shape_digit_in_first = digit_in_first
	shape_missing_first = missing_first
	shape_missing_second = missing_second
	queue_redraw()


func show_stroop(word: String, color: Color, inverse: bool) -> void:
	display_mode = Mode.TEXT
	label.visible = true
	label.text = word
	if inverse and font_bold:
		label.add_theme_font_override("font", font_bold)
	else:
		if font_regular:
			label.add_theme_font_override("font", font_regular)
	_label_color = color
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	_fit_label_font_size()
	queue_redraw()


func _draw() -> void:
	_draw_ascii_border()
	if display_mode == Mode.SHAPE:
		_draw_shapes()


func _fit_label_font_size() -> void:
	if label == null or label.text.is_empty():
		return
	if size.x <= 1.0 or size.y <= 1.0:
		return

	var font: Font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font

	var avail_w: float = size.x * 0.82
	var avail_h: float = size.y * 0.62
	var text: String = label.text

	# Бинарный поиск по чётным размерам 200..20: «влезает» монотонно
	# выполняется при уменьшении шрифта, поэтому ~7 измерений вместо ~90.
	var lo: int = 0
	var hi: int = 90  # (200 - 20) / 2
	while lo < hi:
		var mid: int = (lo + hi) / 2
		var s: int = 200 - 2 * mid
		var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s)
		if ts.x <= avail_w and float(s) * 1.25 <= avail_h:
			hi = mid
		else:
			lo = mid + 1
	label.add_theme_font_size_override("font_size", 200 - 2 * lo)


# Метрики ASCII-рамки зависят только от размера контрола и шрифта — кэшируем,
# чтобы на каждый redraw не строить строки и не мерить шрифт заново.
var _border_cache: Dictionary = {}


func _draw_ascii_border() -> void:
	var font: Font = get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var fs: int = 18

	var key: String = str(int(size.x)) + "x" + str(int(size.y))
	var m: Dictionary = _border_cache.get(key, {})
	if m.is_empty():
		var sample_size: Vector2 = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var ch_w: float = sample_size.x
		var ch_h: float = sample_size.y
		if ch_w <= 0.0 or ch_h <= 0.0:
			return
		var cols: int = maxi(int(floor(size.x / ch_w)), 4)
		var rows: int = maxi(int(floor(size.y / ch_h)), 4)
		m = {
			"ch_w": ch_w, "ch_h": ch_h, "cols": cols, "rows": rows,
			"edge": "+" + "-".repeat(cols - 2) + "+",
		}
		if _border_cache.size() > 16:
			_border_cache.clear()
		_border_cache[key] = m

	var ch_w: float = m["ch_w"]
	var ch_h: float = m["ch_h"]
	var cols: int = m["cols"]
	var rows: int = m["rows"]
	var edge: String = m["edge"]

	var boost: float = _pulse if is_active_zone else 0.0
	var color: Color
	if is_active_zone:
		color = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.75, 0.25), boost * 0.8)
	else:
		color = Color(1, 1, 1, 0.7)

	var y_top: float = 0.0
	var y_bottom: float = float(rows - 1) * ch_h
	var x_right: float = float(cols - 1) * ch_w

	# Верх/низ — по одному draw_string (моноширинный шрифт даёт ту же
	# раскладку, что прежний посимвольный цикл), бока — построчно.
	draw_string(font, Vector2(0.0, y_top), edge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	draw_string(font, Vector2(0.0, y_bottom), edge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	for r in range(1, rows - 1):
		var y: float = float(r) * ch_h
		draw_string(font, Vector2(0.0, y), "|", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		draw_string(font, Vector2(x_right, y), "|", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

	# Аудио-свечение поверх (только активный квадрант и заметный пульс).
	if boost > 0.15:
		var glow_col: Color = Color(1.0, 0.6, 0.2, boost * 0.6)
		draw_string(font, Vector2(0.0, y_top), edge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, glow_col)
		draw_string(font, Vector2(0.0, y_bottom), edge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, glow_col)
		for r in range(1, rows - 1):
			var y2: float = float(r) * ch_h
			draw_string(font, Vector2(0.0, y2), "|", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, glow_col)
			draw_string(font, Vector2(x_right, y2), "|", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, glow_col)


func _draw_shapes() -> void:
	var press_active: bool = _press_scale < 0.999
	if press_active:
		var t: Transform2D = Transform2D.IDENTITY
		t = t.translated(-size / 2.0)
		t = t.scaled(Vector2(_press_scale, _press_scale))
		t = t.translated(size / 2.0)
		draw_set_transform_matrix(t)

	var dt: String = shape_digit_text if shape_digit_text != "" else str(shape_digit)
	if shape_second_sides >= 0:
		var gap: float = 20.0
		var fig_width: float = (size.x - gap) / 2.0
		var cx1: float = fig_width / 2.0
		var cx2: float = size.x - fig_width / 2.0
		var cy: float = size.y / 2.0
		var r: float = min(fig_width, size.y) / 2.0 * 0.7
		_draw_one_shape(Vector2(cx1, cy), r, shape_sides, dt, shape_digit_in_first, shape_missing_first)
		_draw_one_shape(Vector2(cx2, cy), r, shape_second_sides, dt, not shape_digit_in_first, shape_missing_second)
	else:
		var cx: float = size.x / 2.0
		var cy: float = size.y / 2.0
		var r: float = min(size.x, size.y) / 2.0 * 0.7
		_draw_one_shape(Vector2(cx, cy), r, shape_sides, dt, shape_show_digit, shape_missing_first)
	if press_active:
		draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_one_shape(center: Vector2, r: float, sides: int, digit_text: String, show_digit: bool, missing_edge: bool) -> void:
	# Во время вспышки/шлейфа линии «остывают» как люминофор:
	# бело-жёлтые -> янтарные -> обычный белый.
	var col := Color.WHITE
	var w := 4.0
	if _ghost_value > 0.02:
		var g: float = _ghost_value
		col = Color(1.0, lerpf(0.55, 1.0, g), lerpf(0.12, 0.95, g))
		w = 4.0 + g * 2.5
	if sides == 0:
		draw_arc(center, r, 0.0, TAU, 48, col, w, true)
	else:
		var points := PackedVector2Array()
		for i in range(sides):
			var angle: float = -PI / 2.0 + float(i) * TAU / float(sides)
			points.append(center + Vector2(cos(angle), sin(angle)) * r)

		if missing_edge and sides >= 3:
			for i in range(sides):
				var nxt: int = (i + 1) % sides
				if i == 0:
					continue
				draw_line(points[i], points[nxt], col, w, true)
		else:
			points.append(points[0])
			draw_polyline(points, col, w, true)

	if show_digit:
		var font: Font = get_theme_font("font")
		if font == null:
			font = ThemeDB.fallback_font
		var font_size: int = 40
		var text_size: Vector2 = font.get_string_size(digit_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos: Vector2 = center - text_size / 2.0 + Vector2(0, text_size.y * 0.3)
		draw_string(font, pos, digit_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)
