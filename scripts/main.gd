extends Control

const START_TIME := 15
const MAX_TIME := 30.0          # верхний предел таймера (бар показывает честно)
const BONUS_PER_CORRECT := 1.0
const WIN_COMBO := 400
const GARBAGE_TIMEOUT := 0.75

const QUADRANT_ORDER := [0, 1, 3, 2]

const EFFECT_MIN := 0.25
const EFFECT_MAX := 1.0
const EFFECT_COMBO_CAP := 300.0
const EFFECT_RISE_SPEED := 1.5
const EFFECT_FALL_SPEED := 1.2
const ANSWER_FEEDBACK_DELAY := 0.10
# Окно молчания после старта забега: клик-рестарт (или его второй такт
# двойного клика) не должен превращаться в ответ на первом символе.
const START_INPUT_GRACE := 0.35
const EFFECT_MASTER_MAX := 1.5

const SETTINGS_PATH := "user://terminal_settings.cfg"

# Бонус времени за переход на новый этап (порог комбо, один раз на этап).
const STAGE_BONUSES := {"shapes": 100, "stroop": 200, "master": 300}

@onready var quadrants: Array = [
	$Margin/VBox/Grid/Quadrant0,
	$Margin/VBox/Grid/Quadrant1,
	$Margin/VBox/Grid/Quadrant2,
	$Margin/VBox/Grid/Quadrant3
]
@onready var garbage_timer: Timer = $GarbageTimer
@onready var countdown_timer: Timer = $CountdownTimer

enum State { BOOT, MENU, CONFIG, HELP, GAME, CUTSCENE, SHOP }
var current_state: int = State.BOOT

var active := false
var paused: bool = false
var timer_value: float = float(START_TIME)
var combo := 0
var max_combo := 0
var current_item: Dictionary = {}
var current_quadrant := -1
var order_index := 0
var waiting_for_garbage := false
# Пороги бонусов времени, уже выданных в текущей партии.
var _stage_bonus_given: Dictionary = {}
var mode := "letters"
var errors_in_stage: int = 0
var debug_start_combo: int = 0

var timer_bar: StatBar
var combo_bar: StatBar

var debug_menu: PanelContainer
var pause_indicator: Label
var error_overlay: Label
var _error_tween: Tween

# Мета-прогрессия: байты, купленные модули/механики, очки за всё время.
var _meta := MetaStore.new()      # байты/этапы/механики + правила покупок
var _run_bytes: int = 0        # заработано в текущем забеге
var _debug_run: bool = false   # F3-старт: обходит гейт «этап не куплен»
var bytes_label: Label
var progress_label: Label
var vu_label: Label
# Квантование обновления VU-метра: ~8 «кадров» в секунду, как стрелочный
# индикатор на старом железе, а не плавный 60 FPS осциллограф.
var _vu_accum: float = 0.0
var _bytes_pulse_tween: Tween

var _terminal_font: Font = null
var _terminal_font_bold: Font = null

# Шрифтовые привязки (пользовательские клавиши/кнопки мыши для ответов).
var binding_answer1: InputEvent = null
var binding_answer2: InputEvent = null
# Настройки пользователя (сохраняются в SETTINGS_PATH).
var music_volume: float = 0.8      # 0.0..1.0
var sfx_volume: float = 0.8
var crt_enabled: bool = true
var music_fx_enabled: bool = true

var _crt_layer: CanvasLayer

# Материал CRT-оверлея; аудио-реактивные параметры шейдера ведёт SpectrumFx.
var _crt_material: ShaderMaterial
# Порог отправки пульса в квадранты: set_pulse дёргаем только при реальном
# изменении beat-punch, а не каждый кадр.
var _pulse_sent: float = -1.0
# Спектр в этом кадре живой (музыка играет, FX включены) — для VU-метра.
var _vu_live: bool = false

# Менеджер экранов.
var _screen_layer: CanvasLayer
var _current_screen: TerminalScreen

# Генератор заданий (режимы, модификаторы, антиповтор Струпа — внутри него).
var _gen := TaskGen.new()

# Аудио-реактивщина CRT-шейдера (спектр -> огибающие -> параметры шейдера).
var _fx := SpectrumFx.new()

# Музыка (intro->loop плееры, трек-лист, громкость).
var _music := MusicDeck.new()

# Попапы-подсказки (правила этапа / включение модификатора).
var _popup := HintPopup.new()

var _effect_current: float = EFFECT_MIN
var _effect_target: float = EFFECT_MIN
var _margin: Control
var _shake_tween: Tween
var _answer_locked: bool = false


func _ready() -> void:
	_load_settings()
	_apply_terminal_theme()

	_create_bars()
	_setup_crt_overlay()
	_fx.attach_master_bus()
	_music.attach(self)
	_build_debug_menu()
	_build_pause_indicator()
	_build_error_overlay()
	_popup.build(self)
	_build_meta_hud()
	_set_game_input_transparent()
	_margin = get_node_or_null("Margin")
	_music.set_volume(music_volume)
	_apply_sfx_volume()
	_apply_crt_setting()

	# Применяем шрифт ко ВСЕМУ дереву (включая динамически созданные ноды).
	if _terminal_font:
		_apply_font_recursive(self, _terminal_font)

	var margin := get_node_or_null("Margin")
	if margin is MarginContainer:
		margin.add_theme_constant_override("margin_top", 80)
		margin.add_theme_constant_override("margin_bottom", 40)

	_set_game_visible(false)

	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "ScreenLayer"
	_screen_layer.layer = 50
	add_child(_screen_layer)

	update_timer_display()
	update_combo_display()

	_show_boot_screen()


func _apply_sfx_volume() -> void:
	# ВАЖНО: только применение громкости. Ранее сюда ошибочно попал хвост
	# _ready(), из-за чего любое изменение настроек перезапускало boot-экран.
	SFX.set_volume(sfx_volume)


# ---------- CRT-оверлей ----------
func _setup_crt_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CRTLayer"
	layer.layer = 100
	_crt_layer = layer

	var rect := ColorRect.new()
	rect.name = "CRTRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE

	var shader_path := "res://shaders/crt.gdshader"
	if ResourceLoader.exists(shader_path):
		var mat := ShaderMaterial.new()
		mat.shader = load(shader_path)
		_crt_material = mat
		rect.material = mat
	else:
		push_warning("crt.gdshader не найден, оверлей отключён.")
		layer.queue_free()
		# Обязательно обнуляем ссылку: иначе _apply_crt_setting() будет
		# обращаться к удалённому узлу при переключении CRT в настройках.
		_crt_layer = null
		return

	layer.add_child(rect)
	add_child(layer)


# ---------- Аудио-реактивный шейдер ----------
func _process(delta: float) -> void:
	_update_effect_scale(delta)

	_popup.tick(delta, paused)
	_tick_vu(delta)

	if not music_fx_enabled:
		_vu_live = false
		return
	if not _fx.update(delta, _crt_material):
		_vu_live = false
		return
	_vu_live = true

	if current_state == State.GAME:
		# Пульс обновляем только когда величина реально изменилась — иначе
		# set_pulse -> queue_redraw у активного квадранта каждый кадр.
		if absf(_fx.pulse - _pulse_sent) > 0.005:
			_pulse_sent = _fx.pulse
			for q in quadrants:
				q.set_pulse(_fx.pulse if q.is_active_zone else 0.0)


# ---------- Верхние полоски ----------
func _create_bars() -> void:
	for child in get_children():
		if child is StatBar or child.name == "timer_bar" or child.name == "combo_bar":
			child.queue_free()

	timer_bar = StatBar.new()
	timer_bar.name = "timer_bar"
	timer_bar.font_size = 12
	timer_bar.style = StatBar.Style.SIMPLE
	timer_bar.max_value = MAX_TIME
	timer_bar.anchor_left = 0.0
	timer_bar.anchor_right = 1.0
	timer_bar.anchor_top = 0.0
	timer_bar.anchor_bottom = 0.0
	timer_bar.offset_bottom = 20.0
	timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(timer_bar)

	combo_bar = StatBar.new()
	combo_bar.name = "combo_bar"
	combo_bar.font_size = 16
	combo_bar.style = StatBar.Style.SEGMENTS
	combo_bar.max_value = float(WIN_COMBO)
	combo_bar.segments = 4
	combo_bar.anchor_left = 0.0
	combo_bar.anchor_right = 1.0
	combo_bar.anchor_top = 1.0
	combo_bar.anchor_bottom = 1.0
	combo_bar.offset_top = -28.0
	combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combo_bar)


# Индикаторы над полосой прогресса: слева байты, справа процент прохождения.
func _build_meta_hud() -> void:
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
	add_child(bytes_label)

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
	add_child(vu_label)

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
	add_child(progress_label)


func _update_bytes_display() -> void:
	if bytes_label:
		bytes_label.text = "BYTES: %d" % (_meta.balance() + _run_bytes)
		if _debug_run:
			bytes_label.text += "   [F3-DEBUG: БЕЗ ПРОГРЕССА]"


# VU-метр: обновляется ступенями ~8 раз/с — «дискретная электроника», не OS-осциллограф.
func _tick_vu(delta: float) -> void:
	if vu_label == null or not vu_label.visible:
		return
	_vu_accum += delta
	if _vu_accum < 0.125:
		return
	_vu_accum = 0.0
	var b: float = _fx.bass if _vu_live else 0.0
	var m: float = _fx.mid if _vu_live else 0.0
	var t: float = _fx.treble if _vu_live else 0.0
	vu_label.text = "B%s M%s T%s" % [_vu_bars(b), _vu_bars(m), _vu_bars(t)]


func _vu_bars(v: float) -> String:
	var n: int = int(roundf(clampf(v, 0.0, 1.0) * 5.0))
	return "▓".repeat(n) + "░".repeat(5 - n)


func _update_progress_display() -> void:
	if progress_label:
		var pct: int = clampi(int(round(float(combo) * 100.0 / float(WIN_COMBO))), 0, 100)
		progress_label.text = "ПРОГРЕСС: %d%%" % pct


func _flash_byte_gain(amount: int) -> void:
	_update_bytes_display()
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
	if _terminal_font:
		pop.add_theme_font_override("font", _terminal_font)
	add_child(pop)
	# Аутентичный стиль: «+N B» не всплывает плавно, а шагает по строкам
	# растра (3 дискретных шага) и гаснет ступенями.
	var tw := create_tween()
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
	_bytes_pulse_tween = create_tween()
	_bytes_pulse_tween.tween_property(bytes_label, "self_modulate", Color(1, 0.9, 0.35, 1), 0.07)
	_bytes_pulse_tween.tween_property(bytes_label, "self_modulate", Color(1, 1, 1, 1), 0.3)


# ---------- UI-оверлеи ----------
func _build_pause_indicator() -> void:
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
	add_child(pause_indicator)


func _build_error_overlay() -> void:
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
	add_child(error_overlay)


func flash_error_number(n: int) -> void:
	if error_overlay == null:
		return
	error_overlay.text = str(n)
	error_overlay.modulate = Color(1, 1, 1, 1)
	error_overlay.visible = true
	if _error_tween and _error_tween.is_valid():
		_error_tween.kill()
	_error_tween = create_tween()
	_error_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_error_tween.tween_property(error_overlay, "modulate:a", 0.0, 1.0)
	_error_tween.tween_callback(func() -> void: error_overlay.visible = false)


func _register_error_and_flash() -> bool:
	# Инкрементирует счётчик ошибок; возвращает true, если лимит исчерпан.
	# Лимит = купленный «допуск ошибок» (0 ур. — любая ошибка фатальна).
	# Если ошибка не фатальна — применяется купленный уровень отката.
	errors_in_stage += 1
	var allowed: int = _meta.tolerance()
	if errors_in_stage > allowed:
		return true
	flash_error_number(allowed - errors_in_stage)
	_apply_rollback()
	return false


func _apply_rollback() -> void:
	# 0: в начало игры · 1: в начало этапа · 2: -20 очков · 3: без отката.
	match _meta.rollback_level():
		0:
			combo = 0
		1:
			combo = TaskGen.get_mode_reset_value(combo)
		2:
			combo = maxi(0, combo - 20)
		_:
			pass
	update_combo_display()
	var new_mode := TaskGen.get_main_mode(combo)
	if new_mode != mode:
		# Откат уронил игрока на предыдущий этап: музыка и бюджет ошибок — новые.
		mode = new_mode
		errors_in_stage = 0
		_music.play_for_mode(mode)



func _format_binding(e: InputEvent) -> String:
	if e is InputEventKey:
		var s := OS.get_keycode_string(e.keycode)
		return s if s != "" else "?"
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				return "ЛКМ"
			MOUSE_BUTTON_RIGHT:
				return "ПКМ"
			MOUSE_BUTTON_MIDDLE:
				return "СКМ"
			MOUSE_BUTTON_XBUTTON1:
				return "М4"
			MOUSE_BUTTON_XBUTTON2:
				return "М5"
		return "М" + str(e.button_index)
	return "?"


# Строка клавиш для попапа правил этапа (биндинги игрока).
func _format_answer_keys() -> String:
	return "ОТВЕТ: [1] → %s   [2] → %s" % [
		_format_binding(binding_answer1), _format_binding(binding_answer2)
	]


func _style_button(btn: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 1)
	box.border_color = Color(1, 1, 1, 1)
	box.set_border_width_all(2)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6

	var box_hover: StyleBoxFlat = box.duplicate()
	box_hover.bg_color = Color(1, 1, 1, 1)

	btn.add_theme_stylebox_override("normal", box)
	btn.add_theme_stylebox_override("hover", box_hover)
	btn.add_theme_stylebox_override("pressed", box_hover)
	btn.add_theme_stylebox_override("focus", box)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.BLACK)
	btn.add_theme_color_override("font_pressed_color", Color.BLACK)


# ---------- Debug-меню (F3): сетка по этапам × модификаторам ----------
func _build_debug_menu() -> void:
	debug_menu = PanelContainer.new()
	debug_menu.name = "DebugMenu"
	debug_menu.visible = false
	debug_menu.set_anchors_preset(Control.PRESET_CENTER)
	debug_menu.offset_left = -270
	debug_menu.offset_right = 270
	debug_menu.offset_top = -150
	debug_menu.offset_bottom = 150

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color.WHITE
	style.set_border_width_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	debug_menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	debug_menu.add_child(vbox)

	var title := Label.new()
	title.text = "F3: START COMBO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "обходит гейт этапов · байты/очки не начисляются"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(sub)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	vbox.add_child(columns)

	var stages := [
		{"name": "HEX",    "base": 0},
		{"name": "POLY",   "base": 100},
		{"name": "STROOP", "base": 200},
		{"name": "MASTER", "base": 300},
	]

	for stage in stages:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		columns.add_child(col)

		var header := Label.new()
		header.text = stage["name"]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 14)
		header.modulate = Color(0.7, 0.7, 0.7)
		col.add_child(header)

		var base: int = stage["base"]
		for offset in [0, 20, 40, 60, 80]:
			var value: int = base + offset
			var btn := Button.new()
			btn.text = str(value)
			btn.custom_minimum_size = Vector2(70, 28)
			_style_button(btn)
			btn.pressed.connect(_on_debug_start_combo.bind(value))
			col.add_child(btn)

	add_child(debug_menu)


func _toggle_debug_menu() -> void:
	if debug_menu == null:
		return
	debug_menu.visible = not debug_menu.visible


func _toggle_pause() -> void:
	if not active:
		return
	paused = not paused
	countdown_timer.paused = paused
	garbage_timer.paused = paused
	if pause_indicator:
		pause_indicator.visible = paused


func _on_debug_start_combo(c: int) -> void:
	# Debug-функция доступна только в отладочных сборках (см. KEY_F3 в _unhandled_input).
	if not OS.is_debug_build():
		return
	SFX.key()
	if debug_menu:
		debug_menu.visible = false
	start_game(c, true)


# ---------- Экраны ----------
func _set_game_visible(v: bool) -> void:
	var margin := get_node_or_null("Margin")
	if margin:
		margin.visible = v
	if timer_bar:
		timer_bar.visible = v
	if combo_bar:
		combo_bar.visible = v
	if error_overlay:
		error_overlay.visible = false
	if bytes_label:
		bytes_label.visible = v
	if vu_label:
		vu_label.visible = v and music_fx_enabled
	if progress_label:
		progress_label.visible = v
	if not v:
		_popup.hide_popup()


func _transition_to(screen: TerminalScreen) -> void:
	if _current_screen and is_instance_valid(_current_screen):
		_current_screen.queue_free()
	_current_screen = screen
	screen.set_terminal_font(_terminal_font)
	_screen_layer.add_child(screen)


func _show_boot_screen() -> void:
	current_state = State.BOOT
	var boot := preload("res://scripts/screens/boot_screen.gd").new()
	boot.boot_finished.connect(_show_main_menu)
	_transition_to(boot)


func _show_main_menu() -> void:
	current_state = State.MENU
	_music.play("menu")
	_set_game_visible(false)
	var m := preload("res://scripts/screens/main_menu.gd").new()
	m.menu_action.connect(_on_menu_action)
	_transition_to(m)


func _on_menu_action(action: String) -> void:
	match action:
		"start":          _start_game_from_menu()
		"configuration":  _show_config_menu()
		"system update":  _show_system_update()
		"help":           _show_help_screen()
		"exit":           _quit_with_sound()


func _quit_with_sound() -> void:
	if _current_screen and is_instance_valid(_current_screen):
		_current_screen.queue_free()
		_current_screen = null
	SFX.shutdown()
	var wait: float = SFX.shutdown_length()
	if wait <= 0.0:
		wait = 1.0
	await get_tree().create_timer(wait).timeout
	get_tree().quit()


func _start_game_from_menu() -> void:
	current_state = State.GAME
	if _current_screen and is_instance_valid(_current_screen):
		_current_screen.queue_free()
		_current_screen = null
	_set_game_visible(true)
	# Старт с учёта купленного «пропуска этапа»; не наследует debug_start_combo.
	start_game(_meta.skip_start_combo())


func _show_config_menu() -> void:
	current_state = State.CONFIG
	var m = preload("res://scripts/screens/config_menu.gd").new()
	m.set_bindings(binding_answer1, binding_answer2)
	m.set_settings(music_volume, sfx_volume, crt_enabled, music_fx_enabled)
	m.back_requested.connect(_show_main_menu)
	m.bindings_changed.connect(_on_bindings_changed)
	m.settings_changed.connect(_on_settings_changed)
	_transition_to(m)


func _on_settings_changed(volume: float, sfx_vol: float, crt: bool, music_fx: bool) -> void:
	music_volume = clampf(volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_vol, 0.0, 1.0)
	crt_enabled = crt
	music_fx_enabled = music_fx
	_music.set_volume(music_volume)
	_apply_sfx_volume()
	_apply_crt_setting()
	_apply_music_fx_setting()
	_save_settings()


func _on_bindings_changed(e1: InputEvent, e2: InputEvent) -> void:
	binding_answer1 = e1
	binding_answer2 = e2
	_save_settings()


func _show_help_screen() -> void:
	current_state = State.HELP
	var m := preload("res://scripts/screens/help_screen.gd").new()
	m.set_bindings(binding_answer1, binding_answer2)
	m.back_requested.connect(_show_main_menu)
	_transition_to(m)


# ---------- Магазин SYSTEM UPDATE ----------
func _show_system_update() -> void:
	current_state = State.SHOP
	var m := preload("res://scripts/screens/system_update.gd").new()
	m.buy_handler = _meta_buy
	m.back_requested.connect(_show_main_menu)
	# apply_meta до add_child: _ready() построит витрину уже с данными.
	m.apply_meta(_meta.snapshot())
	_transition_to(m)


func _meta_buy(item: String) -> bool:
	# Правила покупки — в MetaStore; здесь звук, сохранение и обновление витрины.
	var ok := _meta.try_buy(item)
	if ok:
		_save_settings()
		SFX.key()
	else:
		SFX.error()
	# Обновляем витрину свежим снапшотом (покупка/отказ).
	if _current_screen and is_instance_valid(_current_screen) and _current_screen.has_method("apply_meta"):
		_current_screen.apply_meta(_meta.snapshot())
	return ok


func _show_end_cutscene() -> void:
	_music.play("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	var m := preload("res://scripts/screens/end_cutscene.gd").new()
	m.bytes_earned = _run_bytes
	m.cutscene_finished.connect(_show_main_menu)
	_transition_to(m)


func _show_lose_cutscene(reason: String, failed_stage: int, progress_pct: int) -> void:
	_music.play("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	var m = preload("res://scripts/screens/lose_cutscene.gd").new()
	m.reason = reason
	m.failed_stage = failed_stage
	m.progress_pct = progress_pct
	m.bytes_earned = _run_bytes
	m.bytes_balance = _meta.balance()
	m.restart_requested.connect(_on_lose_restart)
	m.menu_requested.connect(_show_main_menu)
	m.shop_requested.connect(_on_lose_shop)
	_transition_to(m)


func _on_lose_shop() -> void:
	# Магазин прямо с экрана поражения: байты забега уже зачислены в
	# end_game(), так что баланс на витрине актуален. «Назад» -> main menu.
	_show_system_update()


func _show_shift_complete(completed_stages: int, progress_pct: int) -> void:
	_music.play("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	var m := preload("res://scripts/screens/shift_complete.gd").new()
	m.completed_stages = completed_stages
	m.progress_pct = progress_pct
	m.bytes_earned = _run_bytes
	m.restart_requested.connect(_on_lose_restart)
	m.menu_requested.connect(_show_main_menu)
	_transition_to(m)


func _on_lose_restart() -> void:
	current_state = State.GAME
	if _current_screen and is_instance_valid(_current_screen):
		_current_screen.queue_free()
		_current_screen = null
	_set_game_visible(true)
	# Рестарт с учётом купленного «пропуска этапа» (ур.0 -> с нуля).
	start_game(_meta.skip_start_combo())

func _abort_game() -> void:
	if not active:
		return
	# Дальше всё делает end_game — он остановит таймеры, очистит поле
	# и покажет lose_cutscene с причиной "aborted".
	end_game("aborted")


# ---------- Ввод ----------
func _unhandled_input(event: InputEvent) -> void:
	if current_state != State.GAME:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			# Debug-меню — только в отладочных сборках.
			if OS.is_debug_build():
				SFX.key()
				_toggle_debug_menu()
			return
		if event.keycode == KEY_F4:
			SFX.key()
			_toggle_pause()
			return
		if event.keycode == KEY_ESCAPE:
			SFX.key()
			_abort_game()
			return
		if debug_menu and debug_menu.visible:
			return

	# Здесь всегда active == true: end_game() мгновенно переводит current_state
	# в CUTSCENE, а рестарт обрабатывает сам cutscene — мёртвая ветка убрана.

	if _event_matches(event, binding_answer1):
		handle_answer(1)
		get_viewport().set_input_as_handled()
		return
	if _event_matches(event, binding_answer2):
		handle_answer(2)
		get_viewport().set_input_as_handled()
		return


# ---------- Настройки управления ----------
func _load_settings() -> void:
	binding_answer1 = _default_key_binding(KEY_1)
	binding_answer2 = _default_key_binding(KEY_2)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		binding_answer1 = _read_binding(cfg, "answer1", binding_answer1)
		binding_answer2 = _read_binding(cfg, "answer2", binding_answer2)
		music_volume = clampf(cfg.get_value("audio", "volume", 0.8), 0.0, 1.0)
		sfx_volume = clampf(cfg.get_value("audio", "sfx_volume", 0.8), 0.0, 1.0)
		crt_enabled = cfg.get_value("video", "crt", true)
		music_fx_enabled = cfg.get_value("video", "music_fx", true)
		_meta.load_from_cfg(cfg)


func _default_key_binding(keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	return e


func _read_binding(cfg: ConfigFile, key: String, fallback: InputEvent) -> InputEvent:
	# Если секции input в конфиге нет, берём значение из fallback,
	# иначе keycode/button_index станет 0 и биндинг сломается.
	var t: String = cfg.get_value("input", key + "_type", "")
	var v: Variant = cfg.get_value("input", key + "_value", null)
	if v == null or typeof(v) != TYPE_INT:
		return fallback
	if t == "mouse":
		# Валидные кнопки: LEFT(1) … XBUTTON2(9). Сentinels *_MAX в 4.7 нет.
		if int(v) < MOUSE_BUTTON_LEFT or int(v) > MOUSE_BUTTON_XBUTTON2:
			return fallback
		var mb := InputEventMouseButton.new()
		mb.button_index = int(v)
		return mb
	# Мусор/обнулённый keycode: printable-диапазон начинается с KEY_SPACE(32),
	# спецклавиши — с KEY_SPECIAL; всё меньше 32 не может быть биндингом.
	if int(v) < 32:
		return fallback
	var k := InputEventKey.new()
	k.keycode = int(v)
	return k


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if binding_answer1 is InputEventMouseButton:
		cfg.set_value("input", "answer1_type", "mouse")
		cfg.set_value("input", "answer1_value", binding_answer1.button_index)
	else:
		cfg.set_value("input", "answer1_type", "key")
		cfg.set_value("input", "answer1_value", binding_answer1.keycode)
	if binding_answer2 is InputEventMouseButton:
		cfg.set_value("input", "answer2_type", "mouse")
		cfg.set_value("input", "answer2_value", binding_answer2.button_index)
	else:
		cfg.set_value("input", "answer2_type", "key")
		cfg.set_value("input", "answer2_value", binding_answer2.keycode)
	cfg.set_value("audio", "volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("video", "crt", crt_enabled)
	cfg.set_value("video", "music_fx", music_fx_enabled)
	_meta.save_to_cfg(cfg)
	cfg.save(SETTINGS_PATH)


func _event_matches(event: InputEvent, binding: InputEvent) -> bool:
	if binding == null:
		return false
	if binding is InputEventKey and event is InputEventKey:
		return event.pressed and not event.echo and event.keycode == binding.keycode
	if binding is InputEventMouseButton and event is InputEventMouseButton:
		return event.pressed and event.button_index == binding.button_index
	return false


# ---------- Оформление ----------
func _apply_terminal_theme() -> void:
	var font: Font = null
	var font_bold: Font = null
	var font_path := "res://fonts/HomeVideo-Regular.otf"
	var font_bold_path := "res://fonts/HomeVideo-Bold.otf"

	if ResourceLoader.exists(font_path):
		font = load(font_path)
	if ResourceLoader.exists(font_bold_path):
		font_bold = load(font_bold_path)

	if font == null:
		push_warning("HomeVideo-Regular не найден, использую системный моноширинный.")
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Courier New", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		font = mono
	if font_bold == null:
		font_bold = font

	_terminal_font = font
	_terminal_font_bold = font_bold

	for q in quadrants:
		q.set_fonts(font, font_bold)

# Рекурсивно ставим IGNORE на игровое поддерево, чтобы клики доходили до _unhandled_input.
func _set_game_input_transparent() -> void:
	# Корневой Control тоже должен пропускать мышь, иначе он перехватит
	# все клики раньше, чем они дойдут до _unhandled_input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := get_node_or_null("Background")
	if bg:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := get_node_or_null("Margin")
	if margin:
		_make_subtree_ignore_mouse(margin)


func _make_subtree_ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_make_subtree_ignore_mouse(c)


func _apply_crt_setting() -> void:
	if is_instance_valid(_crt_layer):
		_crt_layer.visible = crt_enabled

func _apply_music_fx_setting() -> void:
	if _crt_material == null:
		return
	if not music_fx_enabled:
		_fx.reset_params(_crt_material)
		for q in quadrants:
			q.set_pulse(0.0)

func _update_effect_scale(delta: float) -> void:
	var target: float = EFFECT_MIN
	if current_state == State.GAME:
		if combo <= int(EFFECT_COMBO_CAP):
			# 0..300 : EFFECT_MIN .. EFFECT_MAX
			var t: float = clampf(float(combo) / EFFECT_COMBO_CAP, 0.0, 1.0)
			target = lerpf(EFFECT_MIN, EFFECT_MAX, t)
		else:
			# 300..400 : EFFECT_MAX .. EFFECT_MASTER_MAX
			var t2: float = clampf(float(combo - int(EFFECT_COMBO_CAP)) / 100.0, 0.0, 1.0)
			target = lerpf(EFFECT_MAX, EFFECT_MASTER_MAX, t2)
	# Гибрид: искажения растут не только от комбо, но и от музыки — бас и
	# верха «тянут» картинку к аналоговым помехам на пиках (в тишине — чисто).
	if current_state == State.GAME and music_fx_enabled:
		target += _fx.bass * 0.15 + _fx.treble * 0.08
	_effect_target = clampf(target, 0.0, EFFECT_MASTER_MAX)
	var speed: float = EFFECT_RISE_SPEED if _effect_target > _effect_current else EFFECT_FALL_SPEED
	_effect_current = move_toward(_effect_current, _effect_target, speed * delta)
	if _crt_material:
		_crt_material.set_shader_parameter("effect_scale", _effect_current)


func _trigger_correct_shake() -> void:
	if _margin == null or not is_instance_valid(_margin):
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	# Аутентичный стиль, смягчённый: горизонтальный срыв развёртки остался
	# дискретным, но амплитуда уменьшена — текст не «уезжает» при каждом ответе.
	var base_left: float = _margin.offset_left
	_shake_tween = create_tween()
	_shake_tween.tween_property(_margin, "offset_left", base_left + 4.0, 0.0)
	_shake_tween.tween_interval(0.04)
	_shake_tween.tween_property(_margin, "offset_left", base_left - 3.0, 0.0)
	_shake_tween.tween_interval(0.04)
	_shake_tween.tween_property(_margin, "offset_left", base_left, 0.0)

func _apply_font_recursive(node: Node, font: Font) -> void:
	if node is Control:
		node.add_theme_font_override("font", font)
	for child in node.get_children():
		_apply_font_recursive(child, font)


# ---------- Отображение ----------
func display_item(item: Dictionary, quad_index: int) -> void:
	# Оптимизация: раньше трогались все 4 квадранта на каждое задание.
	# Достаточно очистить предыдущий активный и подготовить новый.
	if current_quadrant >= 0 and current_quadrant < quadrants.size() and current_quadrant != quad_index:
		var prev = quadrants[current_quadrant]
		prev.clear_item()
		prev.set_active(false)
		prev.set_transform_effect("none")

	var quad = quadrants[quad_index]
	quad.clear_item()
	quad.set_transform_effect("none")
	quad.set_active(true)

	match item["type"]:
		"garbage":
			quad.show_text(item["text"], Color(0.55, 0.55, 0.55))
			waiting_for_garbage = true
			SFX.corrupted()
			garbage_timer.start(GARBAGE_TIMEOUT)
		"letter":
			if item["isRed"]:
				quad.show_text(item["display"], Color.BLACK, true)
			else:
				quad.show_text(item["display"], Color.WHITE, false)
			if combo >= 40 and randf() < 0.25:
				quad.set_transform_effect(TaskGen.random_item(TaskGen.TRANSFORMS))
		"shape":
			var second: int = item["secondSides"] if item["twoShapes"] else -1
			var mf: bool = item.get("missingFirst", false)
			var ms: bool = item.get("missingSecond", false)
			var dt: String = item.get("digitText", "")
			quad.show_shape(item["sides"], item["digit"], dt, true, second, item["digitInFirst"], mf, ms)
		"stroop":
			var word_to_show: String = item["shuffledWord"] if item["shuffled"] else item["word"]
			quad.show_stroop(word_to_show, item["colorValue"], item["inverse"])
			if item["flip"]:
				quad.set_transform_effect(TaskGen.random_item(TaskGen.TRANSFORMS))

	current_item = item
	current_quadrant = quad_index
	# Короткий «терминальный бип»: символ не просто появился — он отпечатался.
	SFX.beep()


func show_next_item() -> void:
	if waiting_for_garbage:
		return

	const STAGE_TIME_BONUS := 5.0
	var new_mode := TaskGen.get_main_mode(combo)
	if new_mode != mode:
		# Гейт мета-прогрессии: следующий этап не куплен — забег успешно
		# завершается на границе установленных модулей (F3-старт обходит).
		if not _debug_run and not _meta.stage_owned(new_mode):
			end_game("stage_complete")
			return
		mode = new_mode
		errors_in_stage = 0
		_music.play_for_mode(mode)
		_popup.show_stage(new_mode, _format_answer_keys())
		# Бонус времени за переход на новый этап (один раз на этап).
		var threshold: int = STAGE_BONUSES.get(new_mode, 0)
		if threshold > 0 and combo >= threshold and not _stage_bonus_given.has(threshold):
			_stage_bonus_given[threshold] = true
			timer_value += STAGE_TIME_BONUS
			update_timer_display()

	var item := _gen.generate_item(mode, combo)
	current_item = item

	var quad_index: int
	if mode == "letters":
		var mods := _gen.modifiers_for("letters", combo)
		if mods.get("randomQuadrant", false) and randf() < 0.3:
			quad_index = randi() % 4
		else:
			quad_index = QUADRANT_ORDER[order_index]
			order_index = (order_index + 1) % QUADRANT_ORDER.size()
	else:
		quad_index = QUADRANT_ORDER[order_index]
		order_index = (order_index + 1) % QUADRANT_ORDER.size()

	display_item(item, quad_index)
	_popup.show_modifier_hint(str(item.get("submode", mode)), combo)


# ---------- Обновление верхних полосок ----------
func update_timer_display() -> void:
	# Ограничиваем и отображаемое значение, и само поле: иначе бар (max_value)
	# «врал» бы при накоплении времени выше предела.
	timer_value = clampf(timer_value, 0.0, MAX_TIME)
	if timer_bar:
		timer_bar.value = timer_value


func update_combo_display() -> void:
	if combo_bar:
		combo_bar.value = float(combo)
	_update_progress_display()


# ---------- Обработка ответа ----------
func handle_answer(button: int) -> void:
	if not active:
		return
	if _answer_locked:
		return

	# Любое нажатие ответа «считывается» подсказкой этапа.
	_popup.on_answer_press()

	if waiting_for_garbage:
		garbage_timer.stop()
		waiting_for_garbage = false
		SFX.error()
		if mode == "master":
			end_game("master_error")
			return
		if _register_error_and_flash():
			end_game("errors_limit")
			return
		show_next_item()
		return

	if current_quadrant == -1 or current_item.is_empty():
		return
	if current_item["type"] == "garbage":
		return

	var correct = TaskGen.correct_answer(current_item, current_quadrant)
	if correct == null:
		return

	if button == correct:
		SFX.key()
		combo += 1
		if combo > max_combo:
			max_combo = combo
		# Экономика забега: байты по курсу этапа (The Sequence — 0) и
		# «очки за всё время» в статистику этого этапа. F3-забег — вне
		# прогрессии: ни байтов, ни очков, чтобы обход гейта этапов
		# нельзя было перепутать с честным забегом.
		var rate: int = 0 if _debug_run else int(Meta.BYTE_RATES.get(mode, 0))
		if not _debug_run:
			_meta.record_answer(mode)
		if rate > 0:
			_run_bytes += rate
		update_combo_display()
		_flash_byte_gain(rate)
		if combo >= WIN_COMBO:
			end_game("win")
			return
		timer_value += BONUS_PER_CORRECT
		update_timer_display()

		# Фидбек: вдавливаем символ и слегка крутим экран.
		_answer_locked = true
		if current_quadrant >= 0 and current_quadrant < quadrants.size():
			var q = quadrants[current_quadrant]
			if q:
				q.play_correct_feedback()
		_trigger_correct_shake()

		await get_tree().create_timer(ANSWER_FEEDBACK_DELAY).timeout
		_answer_locked = false
		if not active:
			return
		show_next_item()
	else:
		SFX.error()
		if mode == "master":
			end_game("master_error")
			return
		if _register_error_and_flash():
			end_game("errors_limit")
			return
		show_next_item()


# ---------- Таймеры ----------
func _on_countdown_tick() -> void:
	timer_value -= 1.0
	update_timer_display()
	if timer_value <= 0.0:
		timer_value = 0.0
		update_timer_display()
		end_game("timeout")


func _on_garbage_timeout() -> void:
	waiting_for_garbage = false
	show_next_item()


# ---------- Завершение ----------
func end_game(reason: String) -> void:
	if not active:
		return
	active = false
	countdown_timer.stop()
	garbage_timer.stop()
	_popup.hide_popup()
	waiting_for_garbage = false
	for q in quadrants:
		q.clear_item()
		q.set_active(false)
		q.set_transform_effect("none")

	var stage_idx: int = TaskGen.get_stage_index(mode)
	var progress_pct: int = clampi(int(round(float(combo) * 100.0 / float(WIN_COMBO))), 0, 100)

	# Зарплата забега уходит в общий кошелёк и сохраняется. _run_bytes не
	# обнуляем: катсцены печатают её как «SALARY», старт нового забега сбросит.
	if _run_bytes > 0:
		_meta.add_bytes(_run_bytes)
	_save_settings()

	if reason == "win":
		_show_end_cutscene()
	elif reason == "stage_complete":
		_show_shift_complete(stage_idx, progress_pct)
	else:
		_show_lose_cutscene(reason, stage_idx, progress_pct)


# ---------- Старт ----------
func start_game(initial_combo: int = -1, debug: bool = false) -> void:
	_debug_run = debug
	_run_bytes = 0
	if initial_combo < 0:
		initial_combo = debug_start_combo
	debug_start_combo = maxi(initial_combo, 0)
	# Вне F3 забег не может начаться с некупленного этапа: страховка на
	# случай, если высокий комбо придёт из skip/F3-наследия/внешнего вызова.
	if not debug and not _meta.stage_owned(TaskGen.get_main_mode(initial_combo)):
		initial_combo = 0

	countdown_timer.stop()
	garbage_timer.stop()
	countdown_timer.paused = false
	garbage_timer.paused = false
	paused = false
	if pause_indicator:
		pause_indicator.visible = false
	# Окно молчания на старт: клик, которым рестартнули игру (он же кнопка
	# ответа), и второй такт двойного клика не должны стать ответом.
	_answer_locked = true
	var grace := get_tree().create_timer(START_INPUT_GRACE)
	grace.timeout.connect(func() -> void: _answer_locked = false)

	active = true
	timer_value = float(START_TIME)
	combo = initial_combo
	max_combo = initial_combo
	order_index = 0
	current_quadrant = -1
	current_item = {}
	waiting_for_garbage = false
	errors_in_stage = 0
	_stage_bonus_given = {}
	for t in STAGE_BONUSES.values():
		if initial_combo >= t:
			_stage_bonus_given[t] = true
	mode = TaskGen.get_main_mode(combo)
	_music.play_for_mode(mode)

	# Подсказки: при старте с высоким комбо (F3) пропущенные модификаторы
	# не показываем, зато сразу даём попап правил текущего этапа.
	_popup.start_run(initial_combo)
	_popup.show_stage(mode, _format_answer_keys())

	update_timer_display()
	update_combo_display()
	_update_bytes_display()

	var first_item := _gen.generate_item(mode, combo)
	current_item = first_item
	var first_quad: int = QUADRANT_ORDER[0]
	display_item(first_item, first_quad)
	order_index = 1
	countdown_timer.start(1.0)
