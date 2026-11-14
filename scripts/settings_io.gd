class_name SettingsIO
extends RefCounted
# Конфигурация терминала в user://: биндинги ответов, громкости, видеонастройки.
# Чистое хранилище с загрузкой/сохранением: про узлы и игру ничего не знает.
# Применение значений (MusicDeck/SFX/FxDirector) — забота main.gd; секция [meta]
# принадлежит MetaStore — сюда передаётся ссылкой для чтения/записи cfg.

const SETTINGS_PATH := "user://terminal_settings.cfg"

# Шрифтовые привязки (пользовательские клавиши/кнопки мыши для ответов).
var binding_answer1: InputEvent = null
var binding_answer2: InputEvent = null
# Настройки пользователя (сохраняются в SETTINGS_PATH).
var music_volume: float = 0.8      # 0.0..1.0
var sfx_volume: float = 0.8
var fx_reactivity: float = 0.3     # «дёрганость» графики от музыки, 0..1 (debug-слайдер)
var crt_enabled: bool = true
var music_fx_enabled: bool = true


# ---------- Настройки управления ----------
func load_settings(meta: MetaStore) -> void:
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
		fx_reactivity = clampf(cfg.get_value("video", "reactivity", 0.3), 0.0, 1.0)
		meta.load_from_cfg(cfg)


func save_settings(meta: MetaStore) -> void:
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
	cfg.set_value("video", "reactivity", fx_reactivity)
	meta.save_to_cfg(cfg)
	cfg.save(SETTINGS_PATH)


func _default_key_binding(keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	return e


func _read_binding(cfg: ConfigFile, key: String, fallback: InputEvent) -> InputEvent:
	# Если секции input в конфиге нет, берём значение из fallback,
	# иначе keycode/button_index станет 0 и биндинг сломается.
	# Guard до get_value: без него движок печатает свою
	# "ERROR: Couldn't find the given section "input"" у нового пользователя.
	if not cfg.has_section_key("input", key + "_value"):
		return fallback
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


# Строка клавиш для попапа правил этапа (биндинги игрока). БЕЗ ПОТРЕБИТЕЛЕЙ
# с 14.11: попапы HintPopup сняты с игры (R-021); хелпер удалится в F-зачистке.
func format_answer_keys() -> String:
	return "ОТВЕТ: [1] → %s   [2] → %s" % [
		_format_binding(binding_answer1), _format_binding(binding_answer2)
	]
