class_name TerminalScreen
extends Control

# Названия этапов — единый источник правды в Meta (см. meta.gd).
const STAGE_NAMES := Meta.STAGE_LABELS
var _vbox: VBoxContainer
var _font: Font
var _cursor_on: bool = true
var _cursor_timer: Timer
var _cursor_rect: ColorRect
var _cursor_lbl: Label
var _plate_rect: ColorRect
var _plate_lbl: Label
var _plate_w: float = 0.0
var _cursor_cell: float = 0.0
var _cursor_text_w: float = 0.0
var _cursor_h: float = 0.0

# --- Автоподгонка контента по высоте (фидбек 2026-11-14: на maximized-окне
# у экрана поражения последняя кнопка «вылезала» за нижний край).
# Не влезает — все шрифты в _vbox и его отступы множатся на один коэффициент
# вплоть до FIT_MIN_RATIO. Правка не накапливается: перед каждым замером
# размеры возвращаются к базовым (запомнены при создании узла).
const FIT_MIN_RATIO := 0.72
const FIT_MIN_FONT := 6            # нижняя грань читаемости моноширинного
var _fit_base: Dictionary = {}     # instance_id -> базовый font_size Label
var _fit_sep_base: int = 4         # базовый separation _vbox (из _ready)
var _fit_queued: bool = false
var _fit_retries: int = 0
var _fit_margin: MarginContainer   # источник вертикальных полей для замера
var _plate_cursor: bool = false    # резерв ячейки курсора на плашке


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
	_fit_margin = margin

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_fit_sep_base = _vbox.get_theme_constant("separation")
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_vbox)

	# Мигающий «курсор» меню (~0.45 с — стандарт терминальной частоты).
	_cursor_timer = Timer.new()
	_cursor_timer.wait_time = 0.45
	_cursor_timer.autostart = true
	_cursor_timer.timeout.connect(_on_cursor_blink)
	add_child(_cursor_timer)

	# Собственный size у топлевел-контрола под CanvasLayer всегда (0,0) —
	# ориентир только вьюпорт; на его ресайзе пересчитываем автоподгонку.
	get_viewport().size_changed.connect(_request_fit)


func _process(_delta: float) -> void:
	# Первый кадр после show: rect'ы лейблов ещё нулевые — плашка и курсор
	# доезжают до строки, как только layout их посчитает.
	if _plate_rect != null and _plate_rect.visible:
		_position_plate()
	if _cursor_rect != null and _cursor_rect.visible:
		_position_cursor()


# Экраны с меню переопределяют: перекрашивают строку с курсором.
func _on_cursor_blink() -> void:
	_cursor_on = not _cursor_on


# Инверсная видеопара для выбранного пункта (VGA-стиль): белая плашка,
# чёрный текст. Плашка — отдельный нод под строками: stylebox-маргины
# давали плашку уже, чем её прямоугольник, и курсор «выезжал» за край.
# cursor = true резервирует справа ячейку под блочный курсор set_cursor_at.
# off_color — обычный цвет неактивных строк.
func set_inverted(lbl: Label, on: bool,
		off_color: Color = Color(0.7, 0.7, 0.7), cursor: bool = false) -> void:
	# Плашка должна быть по ширине текста, а не на всю строку VBox.
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lbl.remove_theme_stylebox_override("normal")
	if on:
		lbl.add_theme_color_override("font_color", Color.BLACK)
		_update_plate(lbl, cursor)
	else:
		lbl.add_theme_color_override("font_color", off_color)
		# Снять плашку может только её строка — иначе цикл _update_selection
		# гасил бы её «невыбранными» строками, идущими после выбранной.
		if _plate_lbl == lbl:
			_plate_lbl = null
			if _plate_rect != null and is_instance_valid(_plate_rect):
				_plate_rect.visible = false


func _update_plate(lbl: Label, cursor: bool) -> void:
	if _plate_rect == null or not is_instance_valid(_plate_rect):
		_plate_rect = ColorRect.new()
		_plate_rect.name = "SelectionPlate"
		_plate_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plate_rect.visible = false
		add_child(_plate_rect)
		# Под контейнером с текстом, над чёрным фоном.
		move_child(_plate_rect, 1)
	_plate_lbl = lbl
	var fs: int = lbl.get_theme_font_size("font_size")
	var font: Font = lbl.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var w: float = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
	if cursor:
		w += 2.0 + font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_plate_w = w
	_plate_cursor = cursor
	_plate_rect.visible = true
	_plate_rect.color = Color.WHITE
	_position_plate()


# Плашка/курсор «едут» за строкой: в первый кадр после add_line rect лейбла
# ещё нулевой, поэтому позиция пересчитывается каждый кадр (_process).
func _position_plate() -> void:
	if _plate_lbl == null or not is_instance_valid(_plate_lbl):
		return
	var r: Rect2 = _plate_lbl.get_global_rect()
	if r.size.x <= 0.0:
		return
	_plate_rect.size = Vector2(_plate_w, r.size.y)
	_plate_rect.global_position = Vector2(r.position.x - 4.0, r.position.y)


# Ширина моноширинной ячейки в размере шрифта лейбла.
func _cell_width(lbl: Label) -> float:
	var fs: int = lbl.get_theme_font_size("font_size")
	var font: Font = lbl.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


# Блочный курсор — отдельный нод поверх конца выбранной строки. Раньше
# «█» вставлялся в текст: глиф был меньше плашки выделения, а при мигании
# строка дёргалась (фидбек). Теперь текст не меняется, блок рисуется
# точного размера в ячейку шрифта и по высоте совпадает с плашкой.
func set_cursor_at(lbl: Label, on: bool) -> void:
	if _cursor_rect == null or not is_instance_valid(_cursor_rect):
		_cursor_rect = ColorRect.new()
		_cursor_rect.name = "BlockCursor"
		_cursor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cursor_rect.visible = false
		add_child(_cursor_rect)
	if not on or lbl == null or not is_instance_valid(lbl) or not lbl.visible:
		# Скрыть может только та строка, которой курсор сейчас принадлежит:
		# иначе цикл _update_selection прячет блок «невыбранными» строками.
		if _cursor_lbl == lbl:
			_cursor_lbl = null
			_cursor_rect.visible = false
		return
	_cursor_lbl = lbl
	var fs: int = lbl.get_theme_font_size("font_size")
	var font: Font = lbl.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	_cursor_cell = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_cursor_text_w = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_cursor_h = font.get_height(fs)
	_cursor_rect.visible = true
	# На плашке выделения курсор чёрный, на голом фоне — цветом текста.
	if _plate_lbl == lbl:
		_cursor_rect.color = Color.BLACK
	else:
		_cursor_rect.color = lbl.get_theme_color("font_color")
	_position_cursor()


func _position_cursor() -> void:
	if _cursor_lbl == null or not is_instance_valid(_cursor_lbl):
		return
	var r: Rect2 = _cursor_lbl.get_global_rect()
	if r.size.x <= 0.0 and _cursor_text_w > 0.0:
		return
	_cursor_rect.size = Vector2(_cursor_cell, _cursor_h)
	# Текст без stylebox-маргинов начинается ровно с границы лейбла.
	_cursor_rect.global_position = Vector2(
		r.position.x + _cursor_text_w + 1.0,
		r.position.y + (r.size.y - _cursor_h) * 0.5)


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
	_fit_base[lbl.get_instance_id()] = font_size
	_request_fit()
	return lbl


func clear_all() -> void:
	for c in _vbox.get_children():
		c.queue_free()
	_fit_base.clear()
	_fit_retries = 0
	_vbox.add_theme_constant_override("separation", _fit_sep_base)


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
	if _cursor_rect != null and is_instance_valid(_cursor_rect):
		_cursor_rect.visible = false
	_cursor_lbl = null
	if _plate_rect != null and is_instance_valid(_plate_rect):
		_plate_rect.visible = false
	_plate_lbl = null
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


# «Мгновенная» версия clear_animated — для навигационных выходов экранов.
# Анимированная очистка создавала мёртвое окно 0.3..0.6 с, в котором экран
# съедал повторные нажатия (_locked), и игрок воспринимал это как «клавиша
# не сработала». По STYLE.md анимации дискретны: страницы переключаются сразу.
func clear_instant() -> void:
	if _cursor_timer:
		_cursor_timer.stop()
	if _cursor_rect != null and is_instance_valid(_cursor_rect):
		_cursor_rect.visible = false
	_cursor_lbl = null
	if _plate_rect != null and is_instance_valid(_plate_rect):
		_plate_rect.visible = false
	_plate_lbl = null
	clear_all()


func _exit_tree() -> void:
	# Экран уходит из дерева (queue_free у экрана) — гасим таймер, иначе
	# последний timeout может ударить по уже freed-лейблам (_update_selection).
	if _cursor_timer:
		_cursor_timer.stop()


# ---------- Автоподгонка ----------
func _request_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit.call_deferred()


# Откат к базовым размерам -> замер -> одно общее сжатие, если не влезает.
# Отложенный запуск + кадр ожидания: get_combined_minimum_size() обязан
# увидеть свежие размеры шрифтов, а в первые кадры size.y ещё нулевой.
func _fit() -> void:
	_fit_queued = false
	if not is_inside_tree() or _vbox == null or not is_instance_valid(_vbox):
		return
	var vp: Vector2 = get_viewport_rect().size
	if vp.y <= 0.0:
		if _fit_retries < 30:
			_fit_retries += 1
			_request_fit()
		return
	_fit_retries = 0

	var labels: Array = []
	_collect_labels(_vbox, labels)
	var bases: Dictionary = {}
	for lbl in labels:
		var id: int = lbl.get_instance_id()
		var base: int = int(_fit_base.get(id, lbl.get_theme_font_size("font_size")))
		bases[id] = base
		lbl.add_theme_font_size_override("font_size", base)
	_fit_base = bases
	_vbox.add_theme_constant_override("separation", _fit_sep_base)

	await get_tree().process_frame
	if not is_inside_tree() or _vbox == null or not is_instance_valid(_vbox):
		return
	var need: float = _vbox.get_combined_minimum_size().y
	if need <= 0.0:
		return
	var avail: float = get_viewport_rect().size.y \
		- _fit_margin.get_theme_constant("margin_top") \
		- _fit_margin.get_theme_constant("margin_bottom")
	if need <= avail:
		return
	var k: float = clampf(avail / need, FIT_MIN_RATIO, 1.0)
	for lbl in labels:
		if not is_instance_valid(lbl):
			continue
		var fs: int = int(round(float(bases[lbl.get_instance_id()]) * k))
		lbl.add_theme_font_size_override("font_size", maxi(FIT_MIN_FONT, fs))
	_vbox.add_theme_constant_override("separation", int(round(_fit_sep_base * k)))
	# Плашка и курсор измерены старыми метриками — пересчитать.
	if _plate_lbl != null and is_instance_valid(_plate_lbl) \
			and _plate_rect != null and is_instance_valid(_plate_rect) and _plate_rect.visible:
		_update_plate(_plate_lbl, _plate_cursor)
	if _cursor_lbl != null and is_instance_valid(_cursor_lbl) \
			and _cursor_rect != null and is_instance_valid(_cursor_rect) and _cursor_rect.visible:
		set_cursor_at(_cursor_lbl, true)


func _collect_labels(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Label:
			out.append(c)
		_collect_labels(c, out)
