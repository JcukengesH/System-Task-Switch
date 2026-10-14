class_name SpectrumFx
extends RefCounted
# Аудио-реактивная прослойка CRT-шейдера: спектр Master-шины -> адаптивная
# нормировка min/max по скользящему окну -> быстрые/медленные огибающие ->
# 5 каналов (bass/lowmid/mid/highmid/treble) + beat + texture -> параметры
# шейдера. Про игру ничего не знает: main.gd передаёт ShaderMaterial в
# update() и читает публичные поля (pulse — для квадрантов, каналы — для VU).

# Скользящее окно истории для адаптивной нормировки.
const HISTORY_LEN := 60

# Каналы спектра: имя -> [частота низа, частота верха]. 5 полос вместо трёх
# — графика реагирует детальнее (низкие «гудят», высокие «сыпят» по-разному).
const BANDS := {
	"bass":    [30.0, 150.0],
	"lowmid":  [150.0, 400.0],
	"mid":     [400.0, 1200.0],
	"highmid": [1200.0, 3500.0],
	"treble":  [3500.0, 12000.0],
}

# Кривая отклика транзиента: вместо жёсткого clamp(x*4) (только 0 или 1) —
# мягкое насыщение x/(x+0.6)*1.6: средние значения живут, пики не бьют в потолок.
const TRANS_GAIN := 2.5
const TRANS_SOFT := 0.6
const TRANS_NORM := 1.6

# Beat-punch (0..1) — main.gd пульсирует им активный квадрант.
var pulse: float = 0.0
# Атака баса (фронт удара) и «сыпучесть» верхов — отдельные каналы реакции.
var beat: float = 0.0
var hiss: float = 0.0
# Огибающие полос (0..1) — публичны для VU-метра HUD'а и слоя искажений.
var bass: float = 0.0
var lowmid: float = 0.0
var mid: float = 0.0
var highmid: float = 0.0
var treble: float = 0.0

var _spectrum: AudioEffectSpectrumAnalyzerInstance

# История спектра по каналам: монотонные деки min/max по скользящему окну
# HISTORY_LEN (деки хранят «логические» инкрементальные индексы, кольцевой
# буфер не нужен).
var _bands: Dictionary = {}
var _hist_idx: int = 0

# Кэш последних отправленных в шейдер значений: не дёргать
# set_shader_parameter каждый кадр одинаковыми числами.
var _shader_cache: Dictionary = {}


func _init() -> void:
	# Инициализация истории спектра: только деки min/max (кольцевых буферов нет).
	for band in BANDS:
		_bands[band] = {
			"min_idx": [], "min_val": [], "max_idx": [], "max_val": [],
			"fast": 0.0, "slow": 0.0, "prev_fast": 0.0, "value": 0.0,
		}
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

	var fast_rate: float = 32.0
	var slow_rate: float = 2.5

	for band in BANDS:
		var range_hz: Array = BANDS[band]
		var raw: float = _spectrum.get_magnitude_for_frequency_range(
			range_hz[0], range_hz[1]).length()
		var normed: float = _adaptive_norm(_to_db(raw), _bands[band])
		var st: Dictionary = _bands[band]
		st["prev_fast"] = st["fast"]
		st["fast"] = _env(st["fast"], normed, delta, fast_rate)
		st["slow"] = _env(st["slow"], normed, delta, slow_rate)
		var trans: float = clampf((st["fast"] - st["slow"]) * TRANS_GAIN, 0.0, 1.0)
		st["value"] = _soft_curve(trans)

	bass = _bands["bass"]["value"]
	lowmid = _bands["lowmid"]["value"]
	mid = _bands["mid"]["value"]
	highmid = _bands["highmid"]["value"]
	treble = _bands["treble"]["value"]

	# Beat — фронт атаки баса (рост быстрой огибающей). Короткий, колкий.
	var bass_onset: float = clampf(
		(_bands["bass"]["fast"] - float(_bands["bass"]["prev_fast"])) * 28.0, 0.0, 1.0)
	beat = maxf(bass_onset, beat - delta * 5.0)

	# Hiss — дрожание верхов (тарелки/шум): модуль быстрых колебаний treble.
	var treble_fluct: float = clampf(
		absf(_bands["treble"]["fast"] - float(_bands["treble"]["prev_fast"])) * 20.0, 0.0, 1.0)
	hiss = maxf(treble_fluct, hiss - delta * 3.0)

	var drive: float = maxf(bass, treble * 0.9)
	drive = maxf(drive, lowmid * 0.85)
	drive = maxf(drive, highmid * 0.8)
	drive = maxf(drive, mid * 0.7)
	if drive > pulse:
		pulse = drive
	else:
		pulse = maxf(0.0, pulse - delta * 3.5)

	_set_param_cached(material, "music_bass", bass)
	_set_param_cached(material, "music_lowmid", lowmid)
	_set_param_cached(material, "music_mid", mid)
	_set_param_cached(material, "music_highmid", highmid)
	_set_param_cached(material, "music_treble", treble)
	_set_param_cached(material, "music_pulse", pulse)
	_set_param_cached(material, "music_beat", beat)
	_set_param_cached(material, "music_texture", hiss)
	return true


# Гасит музыкальные параметры шейдера (FX выключен настройкой). Кэш сбрасывается,
# иначе после повторного включения совпадение со старым значением пропустит
# первую запись и шейдер останется обнулённым.
func reset_params(material: ShaderMaterial) -> void:
	if material == null:
		return
	for pname in ["music_bass", "music_lowmid", "music_mid", "music_highmid",
			"music_treble", "music_pulse", "music_beat", "music_texture",
			"music_effect"]:
		_shader_cache.erase(pname)
		material.set_shader_parameter(pname, 0.0)
	bass = 0.0
	lowmid = 0.0
	mid = 0.0
	highmid = 0.0
	treble = 0.0
	beat = 0.0
	hiss = 0.0


func _soft_curve(x: float) -> float:
	# Плавное насыщение: 0 -> 0, 0.5 -> ~0.73, 1.0 -> 1.0. Середина диапазона
	# перестаёт «выпрыгивать» в максимум, эффекты читаются как градация.
	return clampf(x / (x + TRANS_SOFT) * TRANS_NORM, 0.0, 1.0)


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
