class_name SpectrumFx
extends RefCounted
# Аудио-реактивная прослойка CRT-шейдера: спектр Master-шины -> адаптивная
# нормировка min/max по скользящему окну -> быстрые/медленные огибающие ->
# beat-punch -> параметры шейдера (music_bass / music_mid / music_treble /
# music_pulse). Про игру ничего не знает: main.gd передаёт ShaderMaterial
# в update() и читает публичное поле pulse для квадрантов.

# Скользящее окно истории для адаптивной нормировки.
const HISTORY_LEN := 60

# Beat-punch (0..1) — main.gd пульсирует им активный квадрант.
var pulse: float = 0.0

var _spectrum: AudioEffectSpectrumAnalyzerInstance

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

# Кэш последних отправленных в шейдер значений: не дёргать
# set_shader_parameter каждый кадр одинаковыми числами.
var _shader_cache: Dictionary = {}


func _init() -> void:
	# Инициализация истории спектра: только деки min/max (кольцевых буферов нет).
	_bass_state = {"min_idx": [], "min_val": [], "max_idx": [], "max_val": []}
	_mid_state = {"min_idx": [], "min_val": [], "max_idx": [], "max_val": []}
	_treble_state = {"min_idx": [], "min_val": [], "max_idx": [], "max_val": []}
	_hist_idx = 0


# Находит (или создаёт) анализатор спектра на шине Master.
# Возвращает false, если драйвер аудио не даёт сделать instance (headless).
func attach_master_bus() -> bool:
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
	return _spectrum != null


# Один кадр аудио-реактивности. Возвращает false, если обновлять нечем
# (нет анализатора или материала) — вызывающий может пропустить свои
# зависимые шаги.
func update(delta: float, material: ShaderMaterial) -> bool:
	if _spectrum == null or material == null:
		return false

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
	if drive > pulse:
		pulse = drive
	else:
		pulse = maxf(0.0, pulse - delta * 3.5)

	_set_param_cached(material, "music_bass",   bass_trans)
	_set_param_cached(material, "music_mid",    mid_trans)
	_set_param_cached(material, "music_treble", treble_trans)
	_set_param_cached(material, "music_pulse",  pulse)
	return true


# Гасит музыкальные параметры шейдера (FX выключен настройкой). Кэш сбрасывается,
# иначе после повторного включения совпадение со старым значением пропустит
# первую запись и шейдер останется обнулённым.
func reset_params(material: ShaderMaterial) -> void:
	if material == null:
		return
	for pname in ["music_bass", "music_mid", "music_treble", "music_pulse"]:
		_shader_cache.erase(pname)
		material.set_shader_parameter(pname, 0.0)


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


func _env(current: float, target: float, delta: float, rate: float) -> float:
	return lerpf(current, target, clampf(rate * delta, 0.0, 1.0))


func _set_param_cached(material: ShaderMaterial, pname: String, value: float) -> void:
	var rounded: float = roundf(value * 1000.0) / 1000.0
	if _shader_cache.get(pname) == rounded:
		return
	_shader_cache[pname] = rounded
	material.set_shader_parameter(pname, rounded)
