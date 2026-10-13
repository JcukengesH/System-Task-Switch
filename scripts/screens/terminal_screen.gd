class_name TerminalScreen
extends Control

# Названия этапов — единый источник правды в Meta (см. meta.gd).
const STAGE_NAMES := Meta.STAGE_LABELS
var _vbox: VBoxContainer
var _font: Font
var _cursor_on: bool = true
var _cursor_timer: Timer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_vbox)

	# Мигающий «курсор» меню (~0.45 с — стандарт терминальной частоты).
	_cursor_timer = Timer.new()
	_cursor_timer.wait_time = 0.45
	_cursor_timer.autostart = true
	_cursor_timer.timeout.connect(_on_cursor_blink)
	add_child(_cursor_timer)


# Экраны с меню переопределяют: перекрашивают строку с курсором.
func _on_cursor_blink() -> void:
	_cursor_on = not _cursor_on


# Инверсная видеопара для выбранного пункта (VGA-стиль): белая плашка,
# чёрный текст. off_color — обычный цвет неактивных строк.
func set_inverted(lbl: Label, on: bool,
		off_color: Color = Color(0.7, 0.7, 0.7)) -> void:
	# Плашка должна быть по ширине текста, а не на всю строку VBox.
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if on:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE
		sb.content_margin_left = 4.0
		sb.content_margin_right = 4.0
		lbl.add_theme_stylebox_override("normal", sb)
		lbl.add_theme_color_override("font_color", Color.BLACK)
	else:
		lbl.remove_theme_stylebox_override("normal")
		lbl.add_theme_color_override("font_color", off_color)


func set_terminal_font(font: Font) -> void:
	_font = font


func add_line(text: String, color: Color = Color.WHITE, font_size: int = 20) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	if _font:
		lbl.add_theme_font_override("font", _font)
	_vbox.add_child(lbl)
	return lbl


func clear_all() -> void:
	for c in _vbox.get_children():
		c.queue_free()


func type_lines(lines: Array, delay: float = 0.12) -> void:
	for line in lines:
		if not is_inside_tree():
			return
		var text: String
		var color: Color = Color.WHITE
		var fs: int = 20
		if typeof(line) == TYPE_DICTIONARY:
			text = str(line.get("text", ""))
			color = line.get("color", Color.WHITE)
			fs = line.get("size", 20)
		else:
			text = str(line)
		add_line(text, color, fs)
		await get_tree().create_timer(delay).timeout


func clear_animated(delay: float = 0.04) -> void:
	# Курсорная мигалка не должна заглянуть в освобождаемые строки.
	if _cursor_timer:
		_cursor_timer.stop()
	var kids := _vbox.get_children()
	for c in kids:
		if not is_inside_tree():
			return
		if is_instance_valid(c):
			c.queue_free()
		await get_tree().create_timer(delay).timeout
	# Остались в дереве — возобновляем мигание (для экранов, что чистятся
	# и перестраиваются, а не умирают; у мёртвых экранах _exit_tree уже стопнул).
	if is_inside_tree() and _cursor_timer:
		_cursor_timer.start()


func _exit_tree() -> void:
	# Экран уходит из дерева (queue_free у экрана) — гасим таймер, иначе
	# последний timeout может ударить по уже freed-лейблам (_update_selection).
	if _cursor_timer:
		_cursor_timer.stop()
