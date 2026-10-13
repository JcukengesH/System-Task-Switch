extends Control

const START_TIME := 15
const MAX_TIME := 30.0          # верхний предел таймера (бар показывает честно)
const BONUS_PER_CORRECT := 1.0
# Лимит ошибок на этап задаётся покупкой «ДОПУСК ОШИБОК» (магазин SYSTEM
# UPDATE), константа оставлена только как верхняя граница уровня механики.
const MAX_ERRORS_PER_STAGE := 3
const WIN_COMBO := 400
const GARBAGE_TIMEOUT := 0.75

const VOWELS := ["A", "E", "I", "O"]
const CONSONANTS := ["G", "K", "M", "R"]
const EVEN := ["2", "4", "6", "8"]
const ODD := ["3", "5", "7", "9"]
const GARBAGE_SYMBOLS := ["!", "@", "#", "$", "%", "^", "&", "*", "?", "+", "_", "№"]
const QUADRANT_ORDER := [0, 1, 3, 2]

const FIGURE_TYPES := ["circle", "triangle", "square", "pentagon", "hexagon", "octagon"]
const SIDES_MAP := {
	"circle": 0, "triangle": 3, "square": 4,
	"pentagon": 5, "hexagon": 6, "octagon": 8
}

const COLOR_WORDS := [
	{"name": "КРАСНЫЙ", "color": Color(0.85, 0.1, 0.1)},
	{"name": "СИНИЙ", "color": Color(0.15, 0.25, 0.95)},
	{"name": "ЗЕЛЕНЫЙ", "color": Color(0.15, 0.75, 0.15)},
	{"name": "ЖЕЛТЫЙ", "color": Color(0.95, 0.8, 0.0)},
	{"name": "БЕЛЫЙ", "color": Color(1, 1, 1)},
	{"name": "ФИОЛЕТОВЫЙ", "color": Color(0.55, 0.15, 0.75)},
	{"name": "ГОЛУБОЙ", "color": Color(0.1, 0.85, 0.9)}
]

const MUSIC_TRACKS := {
	"menu":   {"intro": "res://audio/menu_intro_v2.ogg", "loop": "res://audio/menu_loop_v2.ogg"},
	"stage1": {"intro": "res://audio/stage1_intro.ogg",  "loop": "res://audio/stage1_loop.ogg"},
	"stage2": {"intro": "res://audio/stage2_intro.ogg",  "loop": "res://audio/stage2_loop.ogg"},
	"stage3": {"intro": "res://audio/stage3_intro.ogg",  "loop": "res://audio/stage3_loop.ogg"},
	"stage4": {"intro": "res://audio/stage4_intro.ogg",  "loop": "res://audio/stage4_loop.ogg"},
	"outro":  {"intro": "res://audio/outro.ogg",         "loop": ""},
}
const EFFECT_MIN := 0.15
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

# Секция истории для аудио-реактивного шейдера.
const HISTORY_LEN := 60

# Бонус времени за переход на новый этап (порог комбо, один раз на этап).
const STAGE_BONUSES := {"shapes": 100, "stroop": 200, "master": 300}

const MOD_THRESHOLDS := {
	"letters": {"randomQuadrant": 20, "flip": 40, "inverse": 60, "garbage": 80},
	"shapes": {"missingEdge": 120, "mathExpression": 140, "twoShapes": 160, "garbage": 180},
	"stroop": {"inverse": 220, "flip": 240, "shuffle": 260, "garbage": 280},
}

# ---------- Подсказки игроку (попапы в стиле терминала) ----------
# Имена модификаторов для заголовка попапа.
const MOD_NAMES := {
	"randomQuadrant": "СЛУЧАЙНЫЙ УГОЛ",
	"flip": "ПЕРЕВОРОТ СИМВОЛА",
	"inverse": "ИНВЕРСИЯ ОТВЕТА",
	"garbage": "СБОЙ СИСТЕМЫ",
	"missingEdge": "ПРОПУЩЕННАЯ ГРАНЬ",
	"mathExpression": "МАТЕМАТИЧЕСКИЙ ПРИМЕР",
	"twoShapes": "ДВЕ ФИГУРЫ",
	"shuffle": "ПЕРЕМЕШАННЫЕ БУКВЫ",
}

# Краткая инструкция «как действовать» при включении модификатора.
const MOD_HINTS := {
	"letters": {
		"randomQuadrant": "ЗАДАНИЕ ТЕПЕРЬ ПОЯВЛЯЕТСЯ\nВ СЛУЧАЙНОМ УГЛУ. ПРАВИЛА ТЕ ЖЕ",
		"flip": "СИМВОЛ МОЖЕТ БЫТЬ ПЕРЕВЁРНУТ\nНА ОТВЕТ ЭТО НЕ ВЛИЯЕТ",
		"inverse": "ЖИРНЫЙ СИМВОЛ = ОТВЕТ НАОБОРОТ\n[1] <-> [2]",
		"garbage": "НА ЭКРАНЕ @ # $ % ?\nНЕ ЖМИ НИЧЕГО — ПОДОЖДИ СЕКУНДУ",
	},
	"shapes": {
		"missingEdge": "У ФИГУРЫ МОЖЕТ НЕ ХВАТАТЬ ГРАНИ\nСЧИТАЙ ВИДИМЫЕ",
		"mathExpression": "ВМЕСТО ЦИФРЫ — ПРИМЕР (5+3)\nСНАЧАЛА ПОСЧИТАЙ ЕГО",
		"twoShapes": "ДВЕ ФИГУРЫ РЯДОМ\nСЧИТАЙ СУММУ ИХ ГРАНЕЙ",
		"garbage": "НА ЭКРАНЕ @ # $ % ?\nНЕ ЖМИ НИЧЕГО — ПОДОЖДИ СЕКУНДУ",
	},
	"stroop": {
		"inverse": "ЖИРНОЕ СЛОВО = ОТВЕТ НАОБОРОТ\n[1] <-> [2]",
		"flip": "СЛОВО МОЖЕТ БЫТЬ ПЕРЕВЁРНУТО\nНА ОТВЕТ ЭТО НЕ ВЛИЯЕТ",
		"shuffle": "БУКВЫ В СЛОВАХ ПЕРЕМЕШАНЫ (ЙСИНI)\nСРАВНИВАЙ ЦВЕТ С НАЗВАНИЕМ КАК ЕСТЬ",
		"garbage": "НА ЭКРАНЕ @ # $ % ?\nНЕ ЖМИ НИЧЕГО — ПОДОЖДИ СЕКУНДУ",
	},
}

const POPUP_MODE_PRESSURES := 3   # попап правил висит до 3-х нажатий
const POPUP_HINT_SECONDS := 5.0   # попап модификатора висит 5 секунд

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
var meta: Dictionary = Meta.default_meta()
var _run_bytes: int = 0        # заработано в текущем забеге
var _debug_run: bool = false   # F3-старт: обходит гейт «этап не куплен»
var bytes_label: Label
var progress_label: Label
var _bytes_pulse_tween: Tween

# Попап-подсказка (правила этапа / включение модификатора).
var answer_popup: PanelContainer
var _popup_title: Label
var _popup_rule: Label
var _popup_keys: Label
var _popup_fade_tween: Tween
var _popup_presses: int = 0     # >0: попап висит до N нажатий ответа
var _popup_time: float = 0.0    # >0: попап висит N секунд
var _hinted_mods: Dictionary = {}  # уже показанные модификаторы за партию

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

# Музыка.
var _intro_player: AudioStreamPlayer
var _loop_player: AudioStreamPlayer
var _current_music_key: String = ""

# Аудио-спектр для шейдера.
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _crt_material: ShaderMaterial
# История спектра: монотонные деки min/max по скользящему окну HISTORY_LEN
# (деки хранят «логические» инкрементальные индексы, кольцевой буфер не нужен).
var _bass_state: Dictionary = {}
var _mid_state: Dictionary = {}
var _treble_state: Dictionary = {}
var _hist_idx: int = 0
var _bass_fast: float = 0.0
var _bass_slow: float = 0.0
var _mid_fast: float = 0.0
var _mid_slow: float = 0.0
var _treble_fast: float = 0.0
var _treble_slow: float = 0.0
var _beat_punch: float = 0.0
var _pulse_sent: float = -1.0
# Кэш последних отправленных в шейдер значений: не дёргать
# set_shader_parameter каждый кадр одинаковыми числами.
var _shader_cache: Dictionary = {}

# Менеджер экранов.
var _screen_layer: CanvasLayer
var _current_screen: TerminalScreen

# Антиповтор слова в Струпе.
var _last_stroop_word: String = ""

var _effect_current: float = EFFECT_MIN
var _effect_target: float = EFFECT_MIN
var _margin: Control
var _shake_tween: Tween
var _answer_locked: bool = false


func _ready() -> void:
	_load_settings()
	_apply_terminal_theme()

	# Инициализация истории спектра: только деки min/max (кольцевых буферов
	# больше нет — значения живут в самих деках).
	_bass_state = {"min_idx": [], "min_val": [], "max_idx": [], "max_val": []}
	_mid_state = {"min_idx": [], "min_val": [], "max_idx": [], "max_val": []}
	_treble_state = {"min_idx": [], "min_val": [], "max_idx": [], "max_val": []}
	_hist_idx = 0

	_create_bars()
	_setup_crt_overlay()
	_setup_music()
	_build_debug_menu()
	_build_pause_indicator()
	_build_error_overlay()
	_build_answer_popup()
	_build_meta_hud()
	_set_game_input_transparent()
	_margin = get_node_or_null("Margin")
	_apply_audio_settings()
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


# ---------- Музыка ----------
func _setup_music() -> void:
	_intro_player = AudioStreamPlayer.new()
	_intro_player.bus = "Master"
	_intro_player.volume_db = -6.0
	_intro_player.finished.connect(_on_intro_finished)
	add_child(_intro_player)

	_loop_player = AudioStreamPlayer.new()
	_loop_player.bus = "Master"
	_loop_player.volume_db = -6.0
	add_child(_loop_player)

	_setup_spectrum()


func _setup_spectrum() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	var analyzer_index: int = -1
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectSpectrumAnalyzer:
			analyzer_index = i
			break
	if analyzer_index == -1:
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.1
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
		AudioServer.add_bus_effect(bus_idx, fx)
		analyzer_index = AudioServer.get_bus_effect_count(bus_idx) - 1
	_spectrum = AudioServer.get_bus_effect_instance(bus_idx, analyzer_index)


func _on_intro_finished() -> void:
	var entry: Dictionary = MUSIC_TRACKS.get(_current_music_key, {})
	var loop_path: String = entry.get("loop", "")
	if loop_path == "":
		return
	var loop_stream: AudioStream = _load_music(loop_path, true)
	if loop_stream == null:
		return
	_loop_player.stream = loop_stream
	_loop_player.play()


func _load_music(path: String, loop: bool) -> AudioStream:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
		if loop:
			stream.loop_offset = 0.0
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		stream.loop_begin = 0
	return stream


func play_music(key: String) -> void:
	if key == _current_music_key:
		return
	if _intro_player == null:
		return

	_current_music_key = key

	if _intro_player.playing:
		_intro_player.stop()
	if _loop_player.playing:
		_loop_player.stop()

	var entry: Dictionary = MUSIC_TRACKS.get(key, {})
	if entry.is_empty():
		push_warning("play_music: неизвестный ключ '%s'" % key)
		return

	var intro_path: String = entry.get("intro", "")
	var loop_path: String = entry.get("loop", "")

	var intro_stream: AudioStream = _load_music(intro_path, false)
	if intro_stream != null:
		_intro_player.stream = intro_stream
		_intro_player.play()
	else:
		var loop_stream: AudioStream = _load_music(loop_path, true)
		if loop_stream != null:
			_loop_player.stream = loop_stream
			_loop_player.play()


func _update_music_for_mode() -> void:
	match mode:
		"letters": play_music("stage1")
		"shapes":  play_music("stage2")
		"stroop":  play_music("stage3")
		"master":  play_music("stage4")


# ---------- Аудио-реактивный шейдер ----------
func _process(delta: float) -> void:
	_update_effect_scale(delta)

	# Таймер подсказки-модификатора (на паузе не тратится).
	if _popup_time > 0.0 and not paused:
		_popup_time -= delta
		if _popup_time <= 0.0:
			_popup_hide()

	if not music_fx_enabled:
		return
	if _spectrum == null or _crt_material == null:
		return

	var bass_raw: float   = _spectrum.get_magnitude_for_frequency_range(30.0, 200.0).length()
	var mid_raw: float    = _spectrum.get_magnitude_for_frequency_range(200.0, 2000.0).length()
	var treble_raw: float = _spectrum.get_magnitude_for_frequency_range(4000.0, 12000.0).length()

	var bass_db: float   = _to_db(bass_raw)
	var mid_db: float    = _to_db(mid_raw)
	var treble_db: float = _to_db(treble_raw)

	var bass_n: float   = _adaptive_norm(bass_db, _bass_state)
	var mid_n: float    = _adaptive_norm(mid_db, _mid_state)
	var treble_n: float = _adaptive_norm(treble_db, _treble_state)

	var fast_rate: float = 45.0
	var slow_rate: float = 2.0
	_bass_fast   = _env(_bass_fast,   bass_n,   delta, fast_rate)
	_bass_slow   = _env(_bass_slow,   bass_n,   delta, slow_rate)
	_mid_fast    = _env(_mid_fast,    mid_n,    delta, fast_rate)
	_mid_slow    = _env(_mid_slow,    mid_n,    delta, slow_rate)
	_treble_fast = _env(_treble_fast, treble_n, delta, fast_rate)
	_treble_slow = _env(_treble_slow, treble_n, delta, slow_rate)

	var bass_trans: float   = clampf((_bass_fast - _bass_slow) * 4.0,     0.0, 1.0)
	var mid_trans: float    = clampf((_mid_fast - _mid_slow) * 4.0,      0.0, 1.0)
	var treble_trans: float = clampf((_treble_fast - _treble_slow) * 4.0, 0.0, 1.0)

	var drive: float = maxf(bass_trans, treble_trans * 0.9)
	drive = maxf(drive, mid_trans * 0.7)
	if drive > _beat_punch:
		_beat_punch = drive
	else:
		_beat_punch = maxf(0.0, _beat_punch - delta * 3.5)

	_set_shader_param_cached("music_bass",   bass_trans)
	_set_shader_param_cached("music_mid",    mid_trans)
	_set_shader_param_cached("music_treble", treble_trans)
	_set_shader_param_cached("music_pulse",  _beat_punch)

	if current_state == State.GAME:
		# Пульс обновляем только когда величина реально изменилась — иначе
		# set_pulse -> queue_redraw у активного квадранта каждый кадр.
		if absf(_beat_punch - _pulse_sent) > 0.005:
			_pulse_sent = _beat_punch
			for q in quadrants:
				q.set_pulse(_beat_punch if q.is_active_zone else 0.0)


func _to_db(magnitude: float) -> float:
	if magnitude <= 0.000001:
		return -80.0
	return clampf(linear_to_db(magnitude), -80.0, 0.0)


func _adaptive_norm(value: float, state: Dictionary) -> float:
	# Скользящее окно min/max: монотонные деки (пары [логический индекс,
	# значение]). Вытеснение по монотонному счётчику _hist_idx, а не по слоту
	# кольца — иначе окно min/max ломалось сразу после первого переполнения.
	# pop_front() в GDScript это O(n), но n <= HISTORY_LEN (60), т.е. горит
	# на уровне шума; честный кольцевой дек здесь не нужен.
	var idxs: Array = state["min_idx"]
	var minq: Array = state["min_val"]
	var idxe: Array = state["max_idx"]
	var maxq: Array = state["max_val"]

	var t: int = _hist_idx  # логический индекс нового отсчёта
	_hist_idx += 1

	# Всё с индексом <= expired уже за левой границей окна [t-HISTORY_LEN+1; t].
	var expired: int = t - HISTORY_LEN

	while not idxs.is_empty() and int(idxs[0]) <= expired:
		idxs.pop_front()
		minq.pop_front()
	while not idxs.is_empty() and float(minq[minq.size() - 1]) > value:
		idxs.pop_back()
		minq.pop_back()
	idxs.append(t)
	minq.append(value)

	while not idxe.is_empty() and int(idxe[0]) <= expired:
		idxe.pop_front()
		maxq.pop_front()
	while not idxe.is_empty() and float(maxq[maxq.size() - 1]) < value:
		idxe.pop_back()
		maxq.pop_back()
	idxe.append(t)
	maxq.append(value)

	if minq.is_empty() or maxq.is_empty():
		return 0.0
	var mn: float = minq[0]
	var mx: float = maxq[0]
	var rng: float = mx - mn
	if rng < 3.0:
		return 0.0
	return clampf((value - mn) / rng, 0.0, 1.0)


func _set_shader_param_cached(pname: String, value: float) -> void:
	var rounded: float = roundf(value * 1000.0) / 1000.0
	if _shader_cache.get(pname) == rounded:
		return
	_shader_cache[pname] = rounded
	_crt_material.set_shader_parameter(pname, rounded)


func _env(current: float, target: float, delta: float, rate: float) -> float:
	return lerpf(current, target, clampf(rate * delta, 0.0, 1.0))


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
		bytes_label.text = "BYTES: %d" % (int(meta["bytes"]) + _run_bytes)


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
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pop, "offset_top", -104.0, 0.7)
	tw.tween_property(pop, "offset_bottom", -84.0, 0.7)
	tw.tween_property(pop, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(pop.queue_free)
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
	var allowed: int = int(meta["tolerance"])
	if errors_in_stage > allowed:
		return true
	flash_error_number(allowed - errors_in_stage)
	_apply_rollback()
	return false


func _apply_rollback() -> void:
	# 0: в начало игры · 1: в начало этапа · 2: -20 очков · 3: без отката.
	match int(meta["rollback"]):
		0:
			combo = 0
		1:
			combo = get_mode_reset_value(combo)
		2:
			combo = maxi(0, combo - 20)
		_:
			pass
	update_combo_display()
	var new_mode := get_main_mode(combo)
	if new_mode != mode:
		# Откат уронил игрока на предыдущий этап: музыка и бюджет ошибок — новые.
		mode = new_mode
		errors_in_stage = 0
		_update_music_for_mode()


# ---------- Попапы-подсказки (стиль «терминальное окно») ----------
# Появляются по центру, не перекрывают символы в квадрантах и не принимают
# ввод: mouse_filter = IGNORE у всех узлов. Правила этапа висят до нескольких
# нажатий ответа, подсказка модификатора — несколько секунд.
func _build_answer_popup() -> void:
	answer_popup = PanelContainer.new()
	answer_popup.name = "AnswerPopup"
	answer_popup.visible = false
	answer_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	answer_popup.set_anchors_preset(Control.PRESET_CENTER)
	answer_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	answer_popup.grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.88)
	style.border_color = Color(1, 1, 1, 0.9)
	style.set_border_width_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	answer_popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	answer_popup.add_child(vbox)

	_popup_title = Label.new()
	_popup_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_title.add_theme_font_size_override("font_size", 18)
	_popup_title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	vbox.add_child(_popup_title)

	_popup_rule = Label.new()
	_popup_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_rule.add_theme_font_size_override("font_size", 15)
	_popup_rule.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_popup_rule)

	_popup_keys = Label.new()
	_popup_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_keys.add_theme_font_size_override("font_size", 13)
	_popup_keys.add_theme_color_override("font_color", Color(0.45, 1, 0.45))
	vbox.add_child(_popup_keys)

	answer_popup.modulate = Color(1, 1, 1, 0)
	add_child(answer_popup)


func _popup_show(title: String, rule: String, show_keys: bool, presses: int, seconds: float) -> void:
	if answer_popup == null or not is_instance_valid(answer_popup):
		return
	_popup_title.text = title
	_popup_rule.text = rule
	_popup_keys.visible = show_keys
	if show_keys:
		_popup_keys.text = "ОТВЕТ: [1] → %s   [2] → %s" % [
			_format_binding(binding_answer1), _format_binding(binding_answer2)
		]
	_popup_presses = presses
	_popup_time = seconds
	answer_popup.visible = true
	answer_popup.modulate = Color(1, 1, 1, 0)
	if _popup_fade_tween and _popup_fade_tween.is_valid():
		_popup_fade_tween.kill()
	_popup_fade_tween = create_tween()
	_popup_fade_tween.tween_property(answer_popup, "modulate:a", 1.0, 0.12)


func _popup_hide() -> void:
	_popup_presses = 0
	_popup_time = 0.0
	if answer_popup == null or not is_instance_valid(answer_popup) or not answer_popup.visible:
		return
	if _popup_fade_tween and _popup_fade_tween.is_valid():
		_popup_fade_tween.kill()
	_popup_fade_tween = create_tween()
	_popup_fade_tween.tween_property(answer_popup, "modulate:a", 0.0, 0.25)
	_popup_fade_tween.tween_callback(func() -> void: answer_popup.visible = false)


func _show_mode_popup(m: String) -> void:
	var idx := clampi(get_stage_index(m), 1, TerminalScreen.STAGE_NAMES.size())
	_popup_show("ЭТАП %d — %s" % [idx, TerminalScreen.STAGE_NAMES[idx - 1]],
		_mode_rule_text(m), true, POPUP_MODE_PRESSURES, 0.0)


func _mode_rule_text(m: String) -> String:
	match m:
		"letters":
			return "ВВЕРХУ:  [2] ГЛАСНАЯ · [1] СГЛАСНАЯ\nВНИЗУ:   [2] ЧЁТНАЯ · [1] НЕЧЁТНАЯ\n+1 B ЗА ВЕРНЫЙ ОТВЕТ"
		"shapes":
			return "СРАВНИ ЧИСЛО ГРАНЕЙ С ЦИФРОЙ\n[2] = РАВНО · [1] = НЕ РАВНО\n+2 B ЗА ВЕРНЫЙ ОТВЕТ"
		"stroop":
			return "СРАВНИ ЦВЕТ ТЕКСТА С ЕГО НАЗВАНИЕМ\n[2] = СОВПАДАЕТ · [1] = НЕТ\n+3 B ЗА ВЕРНЫЙ ОТВЕТ"
	return "ВСЕ ТИПЫ ЗАДАНИЙ ВПЕРЕМЕШКУ\nБАЙТОВ НЕТ · ЛЮБАЯ ОШИБКА — КОНЕЦ ИГРЫ"


func _maybe_show_mod_hint(submode: String) -> void:
	var thresholds: Dictionary = MOD_THRESHOLDS.get(submode, {})
	var hints: Dictionary = MOD_HINTS.get(submode, {})
	for key in thresholds:
		var tag := str(submode) + "/" + str(key)
		if _hinted_mods.has(tag):
			continue
		if combo >= int(thresholds[key]):
			_hinted_mods[tag] = true
			_popup_show("МОДИФИКАТОР: " + str(MOD_NAMES.get(key, key)),
				str(hints.get(key, "")), false, 0, POPUP_HINT_SECONDS)
			return


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
	sub.text = "(restart)"
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
	if progress_label:
		progress_label.visible = v
	if not v:
		_popup_hide()


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
	play_music("menu")
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
	start_game(_skip_start_combo())


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
	_apply_audio_settings()
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
func _meta_snapshot() -> Dictionary:
	return meta.duplicate(true)


func _show_system_update() -> void:
	current_state = State.SHOP
	var m := preload("res://scripts/screens/system_update.gd").new()
	m.buy_handler = _meta_buy
	m.back_requested.connect(_show_main_menu)
	# apply_meta до add_child: _ready() построит витрину уже с данными.
	m.apply_meta(_meta_snapshot())
	_transition_to(m)


func _meta_buy(item: String) -> bool:
	var ok := _meta_try_buy(item)
	if ok:
		SFX.key()
	else:
		SFX.error()
	# Обновляем витрину свежим снапшотом (покупка/отказ).
	if _current_screen and is_instance_valid(_current_screen) and _current_screen.has_method("apply_meta"):
		_current_screen.apply_meta(_meta_snapshot())
	return ok


func _stage_owned(s: String) -> bool:
	if s == "letters":
		return true
	return bool(meta["stages"].get(s, false))


func _skip_start_combo() -> int:
	return int(Meta.STAGE_START_COMBO[clampi(int(meta["skip"]), 0, 3)])


func _meta_spend(price: int) -> bool:
	if int(meta["bytes"]) < price:
		return false
	meta["bytes"] = int(meta["bytes"]) - price
	return true


func _meta_try_buy(item: String) -> bool:
	match item:
		"stage_shapes", "stage_stroop", "stage_master":
			var stage: String = item.substr(6)
			if _stage_owned(stage):
				return false
			var idx: int = Meta.STAGE_ORDER.find(stage)
			if idx > 0 and not _stage_owned(str(Meta.STAGE_ORDER[idx - 1])):
				return false
			if not _meta_spend(int(Meta.STAGE_PRICES[stage])):
				return false
			meta["stages"][stage] = true
		"tolerance":
			var lvl: int = int(meta["tolerance"])
			if lvl >= MAX_ERRORS_PER_STAGE or not _meta_spend(int(Meta.TOLERANCE_PRICES[lvl])):
				return false
			meta["tolerance"] = lvl + 1
		"rollback":
			# Линия заблокирована, пока допуск ошибок не куплен хотя бы в 1 ур.
			var lvl2: int = int(meta["tolerance"])
			if lvl2 < 1:
				return false
			var rb: int = int(meta["rollback"])
			if rb >= 3 or not _meta_spend(int(Meta.ROLLBACK_PRICES[rb])):
				return false
			meta["rollback"] = rb + 1
		"skip":
			var sk: int = int(meta["skip"])
			if sk >= 3:
				return false
			var need_stage: String = str(Meta.STAGE_ORDER[sk])
			var prev_stage: String = "letters" if sk == 0 else str(Meta.STAGE_ORDER[sk - 1])
			if not _stage_owned(need_stage):
				return false
			if int(meta["life"].get(prev_stage, 0)) < Meta.SKIP_REQ_POINTS:
				return false
			if not _meta_spend(int(Meta.SKIP_PRICES[sk])):
				return false
			meta["skip"] = sk + 1
		_:
			return false
	_save_settings()
	return true


func _show_end_cutscene() -> void:
	play_music("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	var m := preload("res://scripts/screens/end_cutscene.gd").new()
	m.bytes_earned = _run_bytes
	m.cutscene_finished.connect(_show_main_menu)
	_transition_to(m)


func _show_lose_cutscene(reason: String, failed_stage: int, progress_pct: int) -> void:
	play_music("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	var m = preload("res://scripts/screens/lose_cutscene.gd").new()
	m.reason = reason
	m.failed_stage = failed_stage
	m.progress_pct = progress_pct
	m.bytes_earned = _run_bytes
	m.bytes_balance = int(meta["bytes"])
	m.restart_requested.connect(_on_lose_restart)
	m.menu_requested.connect(_show_main_menu)
	m.shop_requested.connect(_on_lose_shop)
	_transition_to(m)


func _on_lose_shop() -> void:
	# Магазин прямо с экрана поражения: байты забега уже зачислены в
	# end_game(), так что баланс на витрине актуален. «Назад» -> main menu.
	_show_system_update()


func _show_shift_complete(completed_stages: int, progress_pct: int) -> void:
	play_music("outro")
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
	start_game(_skip_start_combo())

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
		return
	if _event_matches(event, binding_answer2):
		handle_answer(2)
		return


# ---------- Настройки управления ----------
func _load_settings() -> void:
	meta = Meta.default_meta()
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
		meta["bytes"] = maxi(0, int(cfg.get_value("meta", "bytes", 0)))
		for s in Meta.STAGE_ORDER:
			meta["stages"][s] = bool(cfg.get_value("meta", "stage_" + str(s), false))
		meta["tolerance"] = clampi(int(cfg.get_value("meta", "tolerance", 0)), 0, 3)
		meta["rollback"] = clampi(int(cfg.get_value("meta", "rollback", 0)), 0, 3)
		meta["skip"] = clampi(int(cfg.get_value("meta", "skip", 0)), 0, 3)
		for st in ["letters", "shapes", "stroop", "master"]:
			meta["life"][st] = maxi(0, int(cfg.get_value("meta", "life_" + st, 0)))


func _default_key_binding(keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	return e


func _read_binding(cfg: ConfigFile, key: String, fallback: InputEvent) -> InputEvent:
	# Если секции input в конфиге нет, берём значение из fallback,
	# иначе keycode/button_index станет 0 и биндинг сломается.
	var t: String = cfg.get_value("input", key + "_type", "")
	var v: Variant = cfg.get_value("input", key + "_value", null)
	if v == null:
		return fallback
	if t == "mouse":
		var mb := InputEventMouseButton.new()
		mb.button_index = v
		return mb
	var k := InputEventKey.new()
	k.keycode = v
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
	cfg.set_value("meta", "bytes", int(meta["bytes"]))
	for s in Meta.STAGE_ORDER:
		cfg.set_value("meta", "stage_" + str(s), bool(meta["stages"][s]))
	cfg.set_value("meta", "tolerance", int(meta["tolerance"]))
	cfg.set_value("meta", "rollback", int(meta["rollback"]))
	cfg.set_value("meta", "skip", int(meta["skip"]))
	for st in ["letters", "shapes", "stroop", "master"]:
		cfg.set_value("meta", "life_" + st, int(meta["life"][st]))
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


func _apply_audio_settings() -> void:
	var v: float = clampf(music_volume, 0.0, 1.0)
	var db: float = -80.0 if v <= 0.001 else linear_to_db(v)
	if _intro_player:
		_intro_player.volume_db = db
	if _loop_player:
		_loop_player.volume_db = db


func _apply_crt_setting() -> void:
	if is_instance_valid(_crt_layer):
		_crt_layer.visible = crt_enabled

func _apply_music_fx_setting() -> void:
	if _crt_material == null:
		return
	if not music_fx_enabled:
		_crt_material.set_shader_parameter("music_bass", 0.0)
		_crt_material.set_shader_parameter("music_mid", 0.0)
		_crt_material.set_shader_parameter("music_treble", 0.0)
		_crt_material.set_shader_parameter("music_pulse", 0.0)
		for q in quadrants:
			q.set_pulse(0.0)

func _update_effect_scale(delta: float) -> void:
	var target: float = EFFECT_MIN
	if current_state == State.GAME:
		if combo <= int(EFFECT_COMBO_CAP):
			# 0..300 : 0.15 .. 1.0
			var t: float = clampf(float(combo) / EFFECT_COMBO_CAP, 0.0, 1.0)
			target = lerpf(EFFECT_MIN, EFFECT_MAX, t)
		else:
			# 300..400 : 1.0 .. 1.5
			var t2: float = clampf(float(combo - int(EFFECT_COMBO_CAP)) / 100.0, 0.0, 1.0)
			target = lerpf(EFFECT_MAX, EFFECT_MASTER_MAX, t2)
	_effect_target = target
	var speed: float = EFFECT_RISE_SPEED if _effect_target > _effect_current else EFFECT_FALL_SPEED
	_effect_current = move_toward(_effect_current, _effect_target, speed * delta)
	if _crt_material:
		_crt_material.set_shader_parameter("effect_scale", _effect_current)


func _trigger_correct_shake() -> void:
	if _margin == null or not is_instance_valid(_margin):
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_margin.pivot_offset = _margin.size / 2.0
	var angle: float = randf_range(-1.2, 1.2)
	_shake_tween = create_tween()
	_shake_tween.tween_property(_margin, "rotation_degrees", angle, 0.08)
	_shake_tween.tween_property(_margin, "rotation_degrees", 0.0, 0.18)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _apply_font_recursive(node: Node, font: Font) -> void:
	if node is Control:
		node.add_theme_font_override("font", font)
	for child in node.get_children():
		_apply_font_recursive(child, font)


# ---------- Утилиты ----------
func random_item(arr: Array):
	return arr[randi() % arr.size()]


func shuffle_letters(s: String) -> String:
	var letters: Array = []
	for i in range(s.length()):
		letters.append(s[i])
	letters.shuffle()
	return "".join(PackedStringArray(letters))


func get_main_mode(c: int) -> String:
	if c >= 300: return "master"
	if c >= 200: return "stroop"
	if c >= 100: return "shapes"
	return "letters"


func get_mode_reset_value(c: int) -> int:
	if c < 100: return 0
	if c < 200: return 100
	if c < 300: return 200
	return 300


func get_stage_index(m: String) -> int:
	match m:
		"letters": return 1
		"shapes":  return 2
		"stroop":  return 3
		"master":  return 4
	return 1


func get_modifiers_for_submode(submode: String) -> Dictionary:
	# Модификаторы описаны данными (MOD_THRESHOLDS), а не if-цепочкой.
	var mods := {}
	var thresholds: Dictionary = MOD_THRESHOLDS.get(submode, {})
	for key in thresholds:
		if combo >= int(thresholds[key]):
			mods[key] = true
	return mods


func choose_submode() -> String:
	if mode == "master":
		return random_item(["letters", "shapes", "stroop"])
	return mode


# ---------- Генерация заданий ----------
func generate_item() -> Dictionary:
	var submode := choose_submode()
	var mods := get_modifiers_for_submode(submode)

	if mods.get("garbage", false) and randf() < 0.15:
		var length := 3 + randi() % 3
		var text := ""
		for i in range(length):
			text += random_item(GARBAGE_SYMBOLS)
		return {"type": "garbage", "text": text, "submode": submode}

	if submode == "letters":
		return generate_letters_item(mods)
	elif submode == "shapes":
		return generate_shapes_item(mods)
	return generate_stroop_item(mods)


func generate_letters_item(mods: Dictionary) -> Dictionary:
	var is_vowel := randf() < 0.5
	var is_even := randf() < 0.5
	var letter: String = random_item(VOWELS) if is_vowel else random_item(CONSONANTS)
	var digit: String = random_item(EVEN) if is_even else random_item(ODD)
	var is_red: bool = mods.get("inverse", false) and randf() < 0.2
	return {
		"type": "letter", "letter": letter, "digit": digit,
		"isVowel": is_vowel, "isEven": is_even, "isRed": is_red,
		"display": letter + digit, "submode": "letters"
	}


func _generate_math_expression() -> Dictionary:
	if randf() < 0.5:
		var a: int = randi() % 5 + 1
		var b: int = randi() % 5 + 1
		return {"text": "%d+%d" % [a, b], "value": a + b}
	var a: int = randi() % 7 + 4
	var b: int = randi() % (a - 1) + 1
	return {"text": "%d-%d" % [a, b], "value": a - b}


func generate_shapes_item(mods: Dictionary) -> Dictionary:
	var figure_type: String = random_item(FIGURE_TYPES)
	var sides: int = SIDES_MAP[figure_type]

	var two_shapes := false
	var second_sides: int = 0
	if mods.get("twoShapes", false) and randf() < 0.2:
		two_shapes = true
		var fig2: String = random_item(FIGURE_TYPES)
		second_sides = SIDES_MAP[fig2]

	var missing_first := false
	var missing_second := false
	if mods.get("missingEdge", false):
		if sides >= 3 and randf() < 0.35:
			missing_first = true
		if two_shapes and second_sides >= 3 and randf() < 0.35:
			missing_second = true

	var visible_first: int = sides - 1 if missing_first else sides
	var visible_second: int = second_sides - 1 if missing_second else second_sides
	var total_visible: int = visible_first + (visible_second if two_shapes else 0)

	var digit_value: int
	var digit_text: String = ""
	var use_expr: bool = mods.get("mathExpression", false) and randf() < 0.35
	if use_expr:
		var expr := _generate_math_expression()
		digit_value = expr["value"]
		digit_text = expr["text"]
	else:
		if two_shapes:
			if randf() < 0.5:
				digit_value = min(total_visible, 16)
			else:
				digit_value = randi() % 17
		else:
			if randf() < 0.5:
				digit_value = min(visible_first, 9)
			else:
				digit_value = randi() % 10

	var digit_in_first := true
	if two_shapes:
		digit_in_first = randf() < 0.5

	var correct: int
	if two_shapes:
		correct = 2 if total_visible == digit_value else 1
	else:
		correct = 2 if visible_first == digit_value else 1

	return {
		"type": "shape", "sides": sides, "digit": digit_value,
		"digitText": digit_text,
		"twoShapes": two_shapes, "secondSides": second_sides,
		"digitInFirst": digit_in_first, "correct": correct,
		"missingFirst": missing_first, "missingSecond": missing_second,
		"submode": "shapes"
	}


func generate_stroop_item(mods: Dictionary) -> Dictionary:
	var word_obj: Dictionary
	var color_obj: Dictionary
	var match_flag: bool

	var word_pool: Array = []
	for w in COLOR_WORDS:
		if w["name"] != _last_stroop_word:
			word_pool.append(w)
	if word_pool.is_empty():
		word_pool = COLOR_WORDS.duplicate()

	if randf() < 0.5:
		word_obj = random_item(word_pool)
		color_obj = word_obj
		match_flag = true
	else:
		word_obj = random_item(word_pool)
		var filtered: Array = []
		for c in COLOR_WORDS:
			if c["name"] != word_obj["name"]:
				filtered.append(c)
		color_obj = random_item(filtered)
		match_flag = false

	_last_stroop_word = word_obj["name"]

	var inverse: bool = mods.get("inverse", false) and randf() < 0.2
	var shuffled := false
	var shuffled_word: String = word_obj["name"]
	if mods.get("shuffle", false) and randf() < 0.2:
		shuffled = true
		shuffled_word = shuffle_letters(word_obj["name"])

	var correct := 2 if match_flag else 1
	if inverse:
		correct = 1 if correct == 2 else 2

	var flip: bool = mods.get("flip", false) and randf() < 0.25

	return {
		"type": "stroop", "word": word_obj["name"], "colorValue": color_obj["color"],
		"match": match_flag, "inverse": inverse, "shuffled": shuffled,
		"shuffledWord": shuffled_word, "flip": flip, "correct": correct, "submode": "stroop"
	}


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
				quad.set_transform_effect(random_item(["flip-h", "flip-v", "rotate-180"]))
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
				quad.set_transform_effect(random_item(["flip-h", "flip-v", "rotate-180"]))

	current_item = item
	current_quadrant = quad_index


func get_correct_answer(item: Dictionary):
	if item["type"] == "garbage":
		return null
	if item["type"] == "letter":
		var is_top := current_quadrant < 2
		var correct: int = (2 if item["isVowel"] else 1) if is_top else (2 if item["isEven"] else 1)
		if item["isRed"]:
			correct = 1 if correct == 2 else 2
		return correct
	if item["type"] == "shape":
		return item["correct"]
	if item["type"] == "stroop":
		return item["correct"]
	return null


func show_next_item() -> void:
	if waiting_for_garbage:
		return

	const STAGE_TIME_BONUS := 5.0
	var new_mode := get_main_mode(combo)
	if new_mode != mode:
		# Гейт мета-прогрессии: следующий этап не куплен — забег успешно
		# завершается на границе установленных модулей (F3-старт обходит).
		if not _debug_run and not _stage_owned(new_mode):
			end_game("stage_complete")
			return
		mode = new_mode
		errors_in_stage = 0
		_update_music_for_mode()
		_show_mode_popup(new_mode)
		# Бонус времени за переход на новый этап (один раз на этап).
		var threshold: int = STAGE_BONUSES.get(new_mode, 0)
		if threshold > 0 and combo >= threshold and not _stage_bonus_given.has(threshold):
			_stage_bonus_given[threshold] = true
			timer_value += STAGE_TIME_BONUS
			update_timer_display()

	var item := generate_item()
	current_item = item

	var quad_index: int
	if mode == "letters":
		var mods := get_modifiers_for_submode("letters")
		if mods.get("randomQuadrant", false) and randf() < 0.3:
			quad_index = randi() % 4
		else:
			quad_index = QUADRANT_ORDER[order_index]
			order_index = (order_index + 1) % QUADRANT_ORDER.size()
	else:
		quad_index = QUADRANT_ORDER[order_index]
		order_index = (order_index + 1) % QUADRANT_ORDER.size()

	display_item(item, quad_index)
	_maybe_show_mod_hint(str(item.get("submode", mode)))


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
	if _popup_presses > 0:
		_popup_presses -= 1
		if _popup_presses <= 0:
			_popup_hide()

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

	var correct = get_correct_answer(current_item)
	if correct == null:
		return

	if button == correct:
		SFX.key()
		combo += 1
		if combo > max_combo:
			max_combo = combo
		# Экономика забега: байты по курсу этапа (The Sequence — 0) и
		# «очки за всё время» в статистику этого этапа.
		var rate: int = int(Meta.BYTE_RATES.get(mode, 0))
		meta["life"][mode] = int(meta["life"].get(mode, 0)) + 1
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
	_popup_hide()
	waiting_for_garbage = false
	for q in quadrants:
		q.clear_item()
		q.set_active(false)
		q.set_transform_effect("none")

	var stage_idx: int = get_stage_index(mode)
	var progress_pct: int = clampi(int(round(float(combo) * 100.0 / float(WIN_COMBO))), 0, 100)

	# Зарплата забега уходит в общий кошелёк и сохраняется. _run_bytes не
	# обнуляем: катсцены печатают её как «SALARY», старт нового забега сбросит.
	if _run_bytes > 0:
		meta["bytes"] = int(meta["bytes"]) + _run_bytes
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
	else:
		debug_start_combo = maxi(initial_combo, 0)

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
	mode = get_main_mode(combo)
	_update_music_for_mode()

	# Подсказки: при старте с высоким комбо (F3) пропущенные модификаторы
	# не показываем, зато сразу даём попап правил текущего этапа.
	_hinted_mods = {}
	for submode in MOD_THRESHOLDS:
		for key in MOD_THRESHOLDS[submode]:
			if initial_combo >= int(MOD_THRESHOLDS[submode][key]):
				_hinted_mods[str(submode) + "/" + str(key)] = true
	_popup_hide()
	_show_mode_popup(mode)

	update_timer_display()
	update_combo_display()
	_update_bytes_display()

	var first_item := generate_item()
	current_item = first_item
	var first_quad: int = QUADRANT_ORDER[0]
	display_item(first_item, first_quad)
	order_index = 1
	countdown_timer.start(1.0)
