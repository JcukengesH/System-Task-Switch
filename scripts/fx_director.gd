class_name FxDirector
extends RefCounted
# CRT-оверлей и аудио-реактивные стадии «сходящей с ума системы». Владеет
# SpectrumFx (спектр -> огибающие -> параметры шейдера), слоями безумия по
# этапам, VU-тиком и тряской поля. Настроек не хранит — читает SettingsIO;
# игровое состояние (состояние игры, комбо, этап, квадранты) получает
# параметрами из main.gd каждый кадр.

const EFFECT_MIN := 0.25
const EFFECT_MAX := 1.0
const EFFECT_COMBO_CAP := 300.0  # = Meta.STAGE_START_COMBO[3]: начало THE SEQUENCE
const EFFECT_RISE_SPEED := 1.5
const EFFECT_FALL_SPEED := 1.2
# Музыкальный слой искажений (music_effect в шейдере): суммарная «жёсткость»
# огибающих спектра. Поднимается на ударах, сползает медленно. Умножается на
# мягкую кривую fx_reactivity (pow 1.5): 30% слайдера дают ~16% «дёрганья»,
# 100% — прежнюю полноту. Какой артефакт вообще имеет право жить — решает
# стадийный слой ниже (и шейдерные fx_*, и пульс рамок).
const MUSIC_EFFECT_MAX := 1.0
const MUSIC_RISE_SPEED := 2.8
const MUSIC_FALL_SPEED := 1.6
const EFFECT_MASTER_MAX := 1.5

# Стадии «сходящей с ума системы» (см. fx_scan/fx_glitch/fx_madness в
# crt.gdshader). Индекс = этап разблокировки: 0 HEX — пульс рамок (единственный
# эффект этапа), 1 POLYMETRY — дыхание скан-линий/виньетки/glow, 2 STROOPTEST —
# микро-срывы и RGB-расщепление, 3 THE SEQUENCE — полное безумие. На своём
# этапе слой растёт логарифмически по комбо от seed до max; при переходе
# дальше — плавно откатывается к default и слегка подрастает. Геометрия CRT
# (base_effect) не тронута: бочка экрана — это терминал, она всегда.
# Нижняя граница этапа = Meta.STAGE_START_COMBO[i] (§10.4 — единый источник
# правды по порогам этапов), верхняя = низ + ширина этапа.
const STAGE_COMBO_WIDTH := 100    # шаг Meta.STAGE_START_COMBO (0→100→200→300)
const FX_LAYER_SEED := [0.4, 0.12, 0.12, 0.12]
const FX_LAYER_DEFAULT := [0.55, 0.35, 0.3, 0.45]
const FX_LAYER_MAX := [1.0, 0.7, 0.85, 1.0]
const FX_LOG_K := 5.0
const FX_RISE_SPEED := 0.9
const FX_FALL_SPEED := 0.8

# Источник настроек (music_fx_enabled / crt_enabled / fx_reactivity).
var settings: SettingsIO
# Аудио-реактивщина CRT-шейдера (спектр -> огибающие -> параметры шейдера).
var fx := SpectrumFx.new()
# VU-метр его строит HudBuilder, но стрелку двигает владелец спектра — здесь.
var vu_label: Label = null
# Игровое поле (MarginContainer): трясётся при верном ответе.
var margin: Control = null

var _host: Node = null           # родитель оверлея и твинов (main)
var _crt_layer: CanvasLayer
# Материал CRT-оверлея; аудио-реактивные параметры шейдера ведёт SpectrumFx.
var _crt_material: ShaderMaterial
# Порог отправки пульса в квадранты: set_pulse дёргаем только при реальном
# изменении beat-punch, а не каждый кадр.
var _pulse_sent: float = -1.0
# Спектр в этом кадре живой (музыка играет, FX включены) — для VU-метра.
var _vu_live: bool = false

var _effect_current: float = EFFECT_MIN
var _effect_target: float = EFFECT_MIN
var _music_effect_current: float = 0.0
var _music_effect_target: float = 0.0
# Текущие веса стадийных слоёв (пульс/scan/glitch/madness), 0..1.
var _fx_layers: Array = [0.0, 0.0, 0.0, 0.0]
# Квантование обновления VU-метра: ~8 «кадров» в секунду, как стрелочный
# индикатор на старом железе, а не плавный 60 FPS осциллограф.
var _vu_accum: float = 0.0
var _shake_tween: Tween


# ---------- CRT-оверлей ----------
func setup_overlay(host: Node) -> void:
	_host = host
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
		# Node не ref-counted: без явного освобождения rect остался бы
		# orphan-инстансом ObjectDB (класс утечек из V-017).
		rect.free()
		# Обязательно обнуляем ссылку: иначе apply_crt_setting() будет
		# обращаться к удалённому узлу при переключении CRT в настройках.
		_crt_layer = null
		return

	layer.add_child(rect)
	host.add_child(layer)


# ---------- Аудио-реактивный шейдер ----------
# in_game — current_state == State.GAME; mode — текущий этап (для стадийного
# индекса); quadrants — массив узлов квадрантов (пульс рамок).
func process(delta: float, in_game: bool, combo: int, mode: String, quadrants: Array) -> void:
	_update_effect_scale(delta, in_game, combo)
	_update_stage_fx_layers(delta, in_game, combo, mode)

	_tick_vu(delta)

	if not settings.music_fx_enabled:
		_vu_live = false
		return
	if not fx.update(delta, _crt_material):
		_vu_live = false
		return
	_vu_live = true

	if in_game:
		# Пульс обновляем только когда величина реально изменилась — иначе
		# set_pulse -> queue_redraw у активного квадранта каждый кадр.
		# Амплитуда: мягкая кривая слайдера × стадийный слой 0 (единственный
		# эффект первого этапа, потом откатывается к дефолту).
		var pulse: float = fx.pulse * (0.4 + 0.6 * _react()) * _fx_layers[0]
		if absf(pulse - _pulse_sent) > 0.005:
			_pulse_sent = pulse
			for q in quadrants:
				q.set_pulse(pulse if q.is_active_zone else 0.0)


func _update_effect_scale(delta: float, in_game: bool, combo: int) -> void:
	# Слой «база»: геометрия и свет CRT (бочка, виньетка, скан-линии, glow)
	# растут только от комбо — изгиб экрана на музыку не реагирует.
	var target: float = EFFECT_MIN
	if in_game:
		if combo <= int(EFFECT_COMBO_CAP):
			# 0..300 : EFFECT_MIN .. EFFECT_MAX
			var t: float = clampf(float(combo) / EFFECT_COMBO_CAP, 0.0, 1.0)
			target = lerpf(EFFECT_MIN, EFFECT_MAX, t)
		else:
			# 300..400 : EFFECT_MAX .. EFFECT_MASTER_MAX
			var t2: float = clampf(float(combo - int(EFFECT_COMBO_CAP)) / float(STAGE_COMBO_WIDTH), 0.0, 1.0)
			target = lerpf(EFFECT_MAX, EFFECT_MASTER_MAX, t2)
	_effect_target = target
	var speed: float = EFFECT_RISE_SPEED if _effect_target > _effect_current else EFFECT_FALL_SPEED
	_effect_current = move_toward(_effect_current, _effect_target, speed * delta)

	# Слой «музыка»: суммарная жёсткость пяти огибающих + beat. Только он
	# разгоняет срывы/зерно/вспышки в шейдере; в тишине плавно гаснет в 0.
	var mt: float = 0.0
	if in_game and settings.music_fx_enabled:
		mt = fx.bass * 0.7 + fx.lowmid * 0.45 + fx.mid * 0.3 \
			+ fx.highmid * 0.5 + fx.treble * 0.6 + fx.beat * 0.8
	_music_effect_target = clampf(mt * _react(), 0.0, MUSIC_EFFECT_MAX)
	var mspeed: float = MUSIC_RISE_SPEED if _music_effect_target > _music_effect_current else MUSIC_FALL_SPEED
	_music_effect_current = move_toward(_music_effect_current, _music_effect_target, mspeed * delta)

	if _crt_material:
		_crt_material.set_shader_parameter("base_effect", _effect_current)
		_crt_material.set_shader_parameter("music_effect", _music_effect_current)


# Мягкая кривая слайдера реактивности: малые значения «почти игнорируют»
# музыку, 100% — вся полнота прежних эффектов. Слайдер — debug-инструмент,
# в релизе значение замораживается константой.
func _react() -> float:
	return pow(settings.fx_reactivity, 1.5)


func _fx_stage_index(mode: String) -> int:
	return clampi(TaskGen.get_stage_index(mode) - 1, 0, Meta.STAGE_START_COMBO.size() - 1)


# Стадийные слои безумия: логарифмический рост по комбо внутри текущего этапа,
# плавный откат сыгранных слоёв к дефолту, обнуление ещё не открытых.
func _update_stage_fx_layers(delta: float, in_game: bool, combo: int, mode: String) -> void:
	var sidx: int = _fx_stage_index(mode)
	var p: float = 0.0
	if in_game:
		var lo: float = float(Meta.STAGE_START_COMBO[sidx])
		var hi: float = lo + float(STAGE_COMBO_WIDTH)
		p = clampf((float(combo) - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
	var t: float = log(1.0 + p * FX_LOG_K) / log(1.0 + FX_LOG_K)
	for i in FX_LAYER_MAX.size():
		var target: float = 0.0
		if in_game and i < sidx:
			# Сыгранный слой: дефолт + скромный рост (до 30% диапазона) к концу этапа.
			target = lerpf(FX_LAYER_DEFAULT[i], FX_LAYER_MAX[i], 0.3 * t)
		elif in_game and i == sidx:
			# Текущий фокус этапа: от seed до max логарифмом по прогрессу этапа.
			target = lerpf(FX_LAYER_SEED[i], FX_LAYER_MAX[i], t)
		var speed: float = FX_RISE_SPEED if target > _fx_layers[i] else FX_FALL_SPEED
		_fx_layers[i] = move_toward(_fx_layers[i], target, speed * delta)
	if _crt_material:
		_crt_material.set_shader_parameter("fx_scan", _fx_layers[1])
		_crt_material.set_shader_parameter("fx_glitch", _fx_layers[2])
		_crt_material.set_shader_parameter("fx_madness", _fx_layers[3])


# VU-метр: обновляется ступенями ~8 раз/с — «дискретная электроника», не OS-осциллограф.
func _tick_vu(delta: float) -> void:
	if vu_label == null or not vu_label.visible:
		return
	_vu_accum += delta
	if _vu_accum < 0.125:
		return
	_vu_accum = 0.0
	var b: float = fx.bass if _vu_live else 0.0
	var l: float = fx.lowmid if _vu_live else 0.0
	var m: float = fx.mid if _vu_live else 0.0
	var h: float = fx.highmid if _vu_live else 0.0
	var t: float = fx.treble if _vu_live else 0.0
	vu_label.text = "B%s L%s M%s H%s T%s" % [_vu_bars(b), _vu_bars(l), _vu_bars(m), _vu_bars(h), _vu_bars(t)]


func _vu_bars(v: float) -> String:
	var n: int = int(roundf(clampf(v, 0.0, 1.0) * 5.0))
	return "▓".repeat(n) + "░".repeat(5 - n)


# ---------- Применение настроек видео ----------
func apply_crt_setting() -> void:
	if is_instance_valid(_crt_layer):
		_crt_layer.visible = settings.crt_enabled


func apply_music_fx_setting(quadrants: Array) -> void:
	if _crt_material == null:
		return
	if not settings.music_fx_enabled:
		fx.reset_params(_crt_material)
		for q in quadrants:
			q.set_pulse(0.0)


# ---------- Фидбек верного ответа ----------
func trigger_correct_shake() -> void:
	if margin == null or not is_instance_valid(margin):
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	# Аутентичный стиль, смягчённый: горизонтальный срыв развёртки остался
	# дискретным, но амплитуда уменьшена — текст не «уезжает» при каждом ответе.
	var base_left: float = margin.offset_left
	_shake_tween = _host.create_tween()
	_shake_tween.tween_property(margin, "offset_left", base_left + 4.0, 0.0)
	_shake_tween.tween_interval(0.04)
	_shake_tween.tween_property(margin, "offset_left", base_left - 3.0, 0.0)
	_shake_tween.tween_interval(0.04)
	_shake_tween.tween_property(margin, "offset_left", base_left, 0.0)
