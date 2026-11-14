class_name ConfirmDialog
extends Node
# Модальная плашка подтверждения в CRT-стиле: инверсные строки «да/нет»,
# чёрный фон, белая рамка. Ловит ввод только пока открыта и только через
# handle_input(): собственного _input() здесь нет, иначе диалог перехватывал
# бы события раньше хоста (экраны читают ввод в _input, а не _unhandled_input).

signal confirmed
signal cancelled

const DIM_ALPHA := 0.85
# ScreenLayer у main = 50, CRT-оверлей FxDirector = 100: плашка обязана быть
# выше экранов и ниже скан-линий, иначе тонет под чёрным фоном config_menu.
const DIALOG_LAYER := 90
const BODY_WIDTH := 46
const TITLE_SIZE := 20
const BODY_SIZE := 16
const ROW_SIZE := 18
const ROW_MARGIN_X := 8.0
const ROW_MARGIN_Y := 3.0

# Шрифт хоста: экран сам решает, каким шрифтом рисовать плашку (main
# раздаёт HomeVideo всем экранам). null -> системный fallback.
var font: Font

var _root: CanvasLayer
var _panel: PanelContainer
var _rows: Array[Label] = []
var _selected := 1


## Показывает вопрос. Выбран по умолчанию — отказ: случайное ENTER
## не должно сбрасывать прогресс.
func open(title: String, body: String, yes_text := "CONFIRM", no_text := "CANCEL") -> void:
	if is_open():
		close()
	_root = CanvasLayer.new()
	_root.layer = DIALOG_LAYER
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, DIM_ALPHA)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_panel = PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color.BLACK
	frame.border_color = Color.WHITE
	frame.set_border_width_all(2)
	frame.set_content_margin_all(18.0)
	_panel.add_theme_stylebox_override("panel", frame)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	column.add_child(_make_label(title.to_upper(), TITLE_SIZE, false))
	column.add_child(_make_label("", BODY_SIZE, false))
	for line: String in _wrap(body):
		column.add_child(_make_label(line, BODY_SIZE, false))
	column.add_child(_make_label("", BODY_SIZE, false))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	column.add_child(buttons)
	_rows = []
	for text: String in [yes_text.to_upper(), no_text.to_upper()]:
		var row := _make_label("  %s  " % text, ROW_SIZE, true)
		_rows.append(row)
		buttons.add_child(row)
	# Каждый показ начинается с отказа: выбор, нажитый в прошлом окне
	# (стрелкой или наведением мыши), не переносится — иначе случайный ENTER
	# после «открыть -> навести -> отменить» сбрасывал бы прогресс.
	_selected = 1
	_refresh_rows()


## true — событие принадлежит диалогу, хост обязан его не обрабатывать.
func handle_input(event: InputEvent) -> bool:
	if not is_open():
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_move_selection(-1)
			KEY_RIGHT, KEY_D:
				_move_selection(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate(_selected)
			KEY_ESCAPE:
				_cancel()
			_:
				return false
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
			get_viewport().set_input_as_handled()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# Модальное поведение: ЛКМ всегда принадлежит плашке. Попадание по
			# строке — выбор; клик вне панели — отказ (безопасное действие);
			# клик по телу панели — ничего. Меню под затемнением не реагирует.
			var pressed_row := _row_at(mb.position)
			if pressed_row >= 0:
				_activate(pressed_row)
			elif not _panel.get_global_rect().has_point(mb.position):
				_cancel()
			get_viewport().set_input_as_handled()
			return true
		return true
	if event is InputEventMouseMotion:
		# Пока плашка открыта, движение принадлежит ей: меню под затемнением
		# не должно подсвечивать свои строки.
		var index := _row_at((event as InputEventMouse).position)
		if index >= 0 and index != _selected:
			_selected = index
			_refresh_rows()
		return true
	return false


func is_open() -> bool:
	return _root != null


func close() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	_panel = null
	_rows = []


func _activate(index: int) -> void:
	if not is_open():
		return
	close()
	if index == 0:
		confirmed.emit()
	else:
		cancelled.emit()


func _cancel() -> void:
	if not is_open():
		return
	close()
	cancelled.emit()


func _move_selection(step: int) -> void:
	if _rows.is_empty():
		return
	_selected = wrapi(_selected + step, 0, _rows.size())
	_refresh_rows()


func _refresh_rows() -> void:
	for i: int in _rows.size():
		var row: Label = _rows[i]
		if row != null and is_instance_valid(row):
			_apply_row_state(row, i == _selected)


# Инверсия строки: stylebox с белым фоном и чёрным текстом. Отступы
# одинаковы в обоих состояниях — подсветка не меняет геометрию строки.
func _apply_row_state(row: Label, selected: bool) -> void:
	if selected:
		row.add_theme_color_override("font_color", Color.BLACK)
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color.WHITE
		plate.content_margin_left = ROW_MARGIN_X
		plate.content_margin_right = ROW_MARGIN_X
		plate.content_margin_top = ROW_MARGIN_Y
		plate.content_margin_bottom = ROW_MARGIN_Y
		row.add_theme_stylebox_override("normal", plate)
	else:
		row.add_theme_color_override("font_color", Color.WHITE)
		var ghost := StyleBoxEmpty.new()
		ghost.content_margin_left = ROW_MARGIN_X
		ghost.content_margin_right = ROW_MARGIN_X
		ghost.content_margin_top = ROW_MARGIN_Y
		ghost.content_margin_bottom = ROW_MARGIN_Y
		row.add_theme_stylebox_override("normal", ghost)


func _make_label(text: String, size_px: int, interactive: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE if not interactive \
		else Control.MOUSE_FILTER_PASS
	var active_font: Font = font if font != null else ThemeDB.fallback_font
	label.add_theme_font_override("font", active_font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", Color.WHITE)
	return label


func _wrap(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for chunk: String in text.split("\n"):
		if chunk.length() <= BODY_WIDTH:
			out.append(chunk)
			continue
		var line := ""
		for word: String in chunk.split(" "):
			if line.is_empty():
				line = word
			elif line.length() + 1 + word.length() <= BODY_WIDTH:
				line += " " + word
			else:
				out.append(line)
				line = word
		if not line.is_empty():
			out.append(line)
	return out


func _row_at(global_pos: Vector2) -> int:
	for i: int in _rows.size():
		var row: Label = _rows[i]
		if row != null and is_instance_valid(row) and row.get_global_rect().has_point(global_pos):
			return i
	return -1
