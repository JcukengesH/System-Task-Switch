class_name HudBuilder
extends RefCounted
# Игровой HUD: верхние полосы, счётчики байтов/прогресса, VU-метр, оверлеи
# ошибки и баннеров, дебаг-меню F3 (сборка сетки — в DebugMenuUi). Ноды не
# лежат в сцене — создаются здесь и вешаются на main (порядок в дереве =
# порядок отрисовки).
# Правил забега HudBuilder не знает: только строит ноды и печатает значения,
# которые передаёт вызывающий (main/SessionRules).

var timer_bar: StatBar
var combo_bar: StatBar
var bytes_label: Label
var progress_label: Label
var vu_label: Label
var debug_menu: PanelContainer
var pause_indicator: Label
var error_overlay: Label
var announce_overlay: Label

# Шрифт терминала — для динамически создаваемых всплывающих нод («+N B»).
var terminal_font: Font = null

var _host: Node                # родитель нод и всплытий твинов (main)
var _announce_tween: Tween
var _error_tween: Tween
var _bytes_pulse_tween: Tween


func attach(host: Node) -> void:
	_host = host


# ---------- Верхние полоски ----------
func create_bars(time_max: float, combo_max: float) -> void:
	for child in _host.get_children():
		if child is StatBar or child.name == "timer_bar" or child.name == "combo_bar":
			child.queue_free()

	timer_bar = StatBar.new()
	timer_bar.name = "timer_bar"
	timer_bar.font_size = 12
	timer_bar.style = StatBar.Style.SIMPLE
	timer_bar.max_value = time_max
	timer_bar.anchor_left = 0.0
	timer_bar.anchor_right = 1.0
	timer_bar.anchor_top = 0.0
	timer_bar.anchor_bottom = 0.0
	timer_bar.offset_bottom = 20.0
	timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(timer_bar)

	combo_bar = StatBar.new()
	combo_bar.name = "combo_bar"
	combo_bar.font_size = 16
	combo_bar.style = StatBar.Style.SEGMENTS
	combo_bar.max_value = combo_max
	combo_bar.segments = 4
	combo_bar.anchor_left = 0.0
	combo_bar.anchor_right = 1.0
	combo_bar.anchor_top = 1.0
	combo_bar.anchor_bottom = 1.0
	combo_bar.offset_top = -28.0
	combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(combo_bar)


# Индикаторы над полосой прогресса: слева байты, справа процент прохождения.
func build_meta_hud() -> void:
	bytes_label = Label.new()
	bytes_label.name = "BytesLabel"
	bytes_label.anchor_top = 1.0
	bytes_label.anchor_bottom = 1.0
	bytes_label.offset_left = 12
	bytes_label.offset_top = -52.0
	bytes_label.offset_right = 260
	bytes_label.offset_bottom = -30.0
	bytes_label.add_theme_font_size_override("font_size", 15)
	bytes_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.45))
	bytes_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bytes_label.visible = false
	_host.add_child(bytes_label)

	# ASCII VU-метр спектра — «стрелочный индикатор» справа от счётчика байтов.
	vu_label = Label.new()
	vu_label.name = "VULabel"
	vu_label.anchor_top = 1.0
	vu_label.anchor_bottom = 1.0
	vu_label.offset_left = 272
	vu_label.offset_top = -50.0
	vu_label.offset_right = 620
	vu_label.offset_bottom = -30.0
	vu_label.add_theme_font_size_override("font_size", 13)
	vu_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vu_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vu_label.visible = false
	_host.add_child(vu_label)

	progress_label = Label.new()
	progress_label.name = "ProgressLabel"
	progress_label.anchor_left = 1.0
	progress_label.anchor_right = 1.0
	progress_label.anchor_top = 1.0
	progress_label.anchor_bottom = 1.0
	progress_label.offset_left = -260
	progress_label.offset_top = -52.0
	progress_label.offset_right = -12
	progress_label.offset_bottom = -30.0
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.add_theme_font_size_override("font_size", 15)
	progress_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_label.visible = false
	_host.add_child(progress_label)


# ---------- Вывод значений (текст/числа готовит вызывающий) ----------
func set_timer_value(v: float) -> void:
	if timer_bar:
		timer_bar.value = v


func set_combo_value(v: float) -> void:
	if combo_bar:
		combo_bar.value = v


func set_bytes_text(text: String) -> void:
	if bytes_label:
		bytes_label.text = text


func set_progress_text(text: String) -> void:
	if progress_label:
		progress_label.text = text


# Всплывающий «+N B» над счётчиком + пульс счётчика жёлтым. text — свежая
# строка BYTES (перерисовывается всегда, даже при amount <= 0, как раньше).
func flash_byte_gain(amount: int, bytes_text: String) -> void:
	set_bytes_text(bytes_text)
	if amount <= 0 or bytes_label == null:
		return
	# Всплывающий «+N B» над счётчиком: вверх + затухание.
	var pop := Label.new()
	pop.text = "+%d B" % amount
	pop.anchor_top = 1.0
	pop.anchor_bottom = 1.0
	pop.offset_left = 12
	pop.offset_top = -74.0
	pop.offset_right = 160
	pop.offset_bottom = -54.0
	pop.add_theme_font_size_override("font_size", 15)
	pop.add_theme_color_override("font_color", Color(0.45, 1.0, 0.45))
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if terminal_font:
		pop.add_theme_font_override("font", terminal_font)
	_host.add_child(pop)
	# Аутентичный стиль: «+N B» не всплывает плавно, а шагает по строкам
	# растра (3 дискретных шага) и гаснет ступенями.
	var tw := _host.create_tween()
	for i in 3:
		tw.tween_interval(0.16)
		var step_idx := i
		tw.tween_callback(func() -> void:
			pop.offset_top -= 10.0
			pop.offset_bottom -= 10.0
			pop.modulate.a = 1.0 - float(step_idx + 1) * 0.34)
	tw.tween_callback(pop.queue_free)
	# Пульс самого счётчика жёлтым.
	if _bytes_pulse_tween != null and _bytes_pulse_tween.is_valid():
		_bytes_pulse_tween.kill()
	bytes_label.self_modulate = Color(1, 1, 1, 1)
	_bytes_pulse_tween = _host.create_tween()
	_bytes_pulse_tween.tween_property(bytes_label, "self_modulate", Color(1, 0.9, 0.35, 1), 0.07)
	_bytes_pulse_tween.tween_property(bytes_label, "self_modulate", Color(1, 1, 1, 1), 0.3)


# ---------- UI-оверлеи ----------
func build_pause_indicator() -> void:
	pause_indicator = Label.new()
	pause_indicator.text = "|| ПАУЗА ||"
	pause_indicator.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pause_indicator.offset_top = 24
	pause_indicator.offset_bottom = 48
	pause_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_indicator.add_theme_font_size_override("font_size", 20)
	pause_indicator.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	pause_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_indicator.visible = false
	_host.add_child(pause_indicator)


func build_error_overlay() -> void:
	error_overlay = Label.new()
	error_overlay.name = "ErrorOverlay"
	error_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	error_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_overlay.add_theme_font_size_override("font_size", 400)
	error_overlay.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1))
	error_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	error_overlay.visible = false
	error_overlay.modulate = Color(1, 1, 1, 0)
	_host.add_child(error_overlay)


# Полноэкранный баннер: крупная надпись по центру — по принципу красной
# цифры ошибки, но текстом (объявление модификаторов, старт финала).
func build_announce_overlay() -> void:
	announce_overlay = Label.new()
	announce_overlay.name = "AnnounceOverlay"
	announce_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	announce_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	announce_overlay.add_theme_font_size_override("font_size", 150)
	announce_overlay.add_theme_color_override("font_color", Color.WHITE)
	announce_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announce_overlay.visible = false
	announce_overlay.modulate = Color(1, 1, 1, 0)
	_host.add_child(announce_overlay)


func flash_error_number(n: int) -> void:
	if error_overlay == null:
		return
	error_overlay.text = str(n)
	error_overlay.modulate = Color(1, 1, 1, 1)
	error_overlay.visible = true
	if _error_tween and _error_tween.is_valid():
		_error_tween.kill()
	_error_tween = _host.create_tween()
	_error_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_error_tween.tween_property(error_overlay, "modulate:a", 0.0, 1.0)
	_error_tween.tween_callback(func() -> void: error_overlay.visible = false)


# Баннеры по очереди: items = [{ "text", "color", "size" }].
func flash_announcements(items: Array) -> void:
	if announce_overlay == null or items.is_empty():
		return
	announce_overlay.visible = true
	announce_overlay.modulate = Color(1, 1, 1, 0)
	if _announce_tween and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = _host.create_tween()
	for it in items:
		_announce_tween.tween_callback(_set_announce.bind(it))
		_announce_tween.tween_property(announce_overlay, "modulate:a", 1.0, 0.06)
		_announce_tween.tween_interval(0.85)
		_announce_tween.tween_property(announce_overlay, "modulate:a", 0.0, 0.4)
	_announce_tween.tween_callback(func() -> void: announce_overlay.visible = false)


func _set_announce(it: Dictionary) -> void:
	announce_overlay.text = str(it.get("text", ""))
	announce_overlay.add_theme_font_size_override("font_size", int(it.get("size", 150)))
	announce_overlay.add_theme_color_override("font_color", it.get("color", Color.WHITE))


# ---------- Видимость игрового HUD (Margin двигает вызывающий) ----------
# vu_gate — music_fx_enabled: VU-метр live только при включённых FX-от-музыки.
func set_game_nodes_visible(v: bool, vu_gate: bool) -> void:
	if timer_bar:
		timer_bar.visible = v
	if combo_bar:
		combo_bar.visible = v
	if error_overlay:
		error_overlay.visible = false
	if bytes_label:
		bytes_label.visible = v
	if vu_label:
		vu_label.visible = v and vu_gate
	if progress_label:
		progress_label.visible = v


# ---------- Debug-меню (F3) ----------
# Сборка сетки — в DebugMenuUi (отдельный файл: весь debug-контур удаляется
# перед релизом вместе с ним; здесь остаётся только владение нодой).
func build_debug_menu(on_pick: Callable) -> void:
	debug_menu = DebugMenuUi.build(_host, on_pick)
