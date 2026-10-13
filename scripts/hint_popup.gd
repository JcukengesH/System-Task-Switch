class_name HintPopup
extends RefCounted
# Попапы-подсказки в стиле «терминальное окно»: появляются по центру, не
# перекрывают символы в квадрантах и не принимают ввод (mouse_filter = IGNORE
# у всех узлов). Правила этапа висят до нескольких нажатий ответа, подсказка
# модификатора — несколько секунд.
# main.gd: build(parent) в _ready; далее show_stage / show_modifier_hint /
# on_answer_press / tick / hide_popup / start_run.

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

const MODE_PRESSURES := 3   # попап правил висит до 3-х нажатий
const HINT_SECONDS := 5.0   # попап модификатора висит 5 секунд

var _panel: PanelContainer
var _title: Label
var _rule: Label
var _keys: Label
var _fade: Tween
var _presses: int = 0     # >0: попап висит до N нажатий ответа
var _time: float = 0.0    # >0: попап висит N секунд
var _hinted: Dictionary = {}  # уже показанные модификаторы за партию


# Создаёт панель попапа и вешает её на parent (порядок в дереве = поверх игры).
func build(parent: Node) -> void:
	_panel = PanelContainer.new()
	_panel.name = "AnswerPopup"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.88)
	style.border_color = Color(1, 1, 1, 0.9)
	style.set_border_width_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	vbox.add_child(_title)

	_rule = Label.new()
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule.add_theme_font_size_override("font_size", 15)
	_rule.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_rule)

	_keys = Label.new()
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keys.add_theme_font_size_override("font_size", 13)
	_keys.add_theme_color_override("font_color", Color(0.45, 1, 0.45))
	vbox.add_child(_keys)

	_panel.modulate = Color(1, 1, 1, 0)
	parent.add_child(_panel)


# Попап правил этапа. keys_line — строка с биндингами ответов (форматирует
# вызывающий: про клавиатуру игрока HintPopup ничего не знает).
func show_stage(mode: String, keys_line: String) -> void:
	var idx := clampi(TaskGen.get_stage_index(mode), 1, TerminalScreen.STAGE_NAMES.size())
	_show("ЭТАП %d — %s" % [idx, TerminalScreen.STAGE_NAMES[idx - 1]],
		_rule_text(mode), keys_line, MODE_PRESSURES, 0.0)


# Первый переход порога модификатора за партию — одночасовое напоминание.
func show_modifier_hint(submode: String, combo: int) -> void:
	var thresholds: Dictionary = TaskGen.MOD_THRESHOLDS.get(submode, {})
	var hints: Dictionary = MOD_HINTS.get(submode, {})
	for key in thresholds:
		var tag := str(submode) + "/" + str(key)
		if _hinted.has(tag):
			continue
		if combo >= int(thresholds[key]):
			_hinted[tag] = true
			_show("МОДИФИКАТОР: " + str(MOD_NAMES.get(key, key)),
				str(hints.get(key, "")), "", 0, HINT_SECONDS)
			return


# Новый забег: сброс показанных подсказок с предпометкой уже пройденных
# порогов (F3-старт с высоким комбо не должен сыпать подсказками подряд).
func start_run(upto_combo: int) -> void:
	_hinted = {}
	for submode in TaskGen.MOD_THRESHOLDS:
		for key in TaskGen.MOD_THRESHOLDS[submode]:
			if upto_combo >= int(TaskGen.MOD_THRESHOLDS[submode][key]):
				_hinted[str(submode) + "/" + str(key)] = true
	hide_popup()


func on_answer_press() -> void:
	if _presses > 0:
		_presses -= 1
		if _presses <= 0:
			hide_popup()


func tick(delta: float, paused: bool) -> void:
	# Таймер подсказки-модификатора (на паузе не тратится).
	if _time > 0.0 and not paused:
		_time -= delta
		if _time <= 0.0:
			hide_popup()


func hide_popup() -> void:
	_presses = 0
	_time = 0.0
	if _panel == null or not is_instance_valid(_panel) or not _panel.visible:
		return
	if _fade and _fade.is_valid():
		_fade.kill()
	# Дискретно: исчезает сразу, без угасания.
	_panel.modulate = Color(1, 1, 1, 1)
	_panel.visible = false


func _show(title: String, rule: String, keys_line: String, presses: int, seconds: float) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_title.text = title
	_rule.text = rule
	var has_keys: bool = keys_line != ""
	_keys.visible = has_keys
	if has_keys:
		_keys.text = keys_line
	_presses = presses
	_time = seconds
	_panel.visible = true
	# Аутентичный стиль: попап не проявывается фейдом — он либо есть, либо нет,
	# как напечатанная строка на терминале.
	_panel.modulate = Color(1, 1, 1, 1)


func _rule_text(m: String) -> String:
	match m:
		"letters":
			return "ВВЕРХУ:  [2] ГЛАСНАЯ · [1] СГЛАСНАЯ\nВНИЗУ:   [2] ЧЁТНАЯ · [1] НЕЧЁТНАЯ\n+1 B ЗА ВЕРНЫЙ ОТВЕТ"
		"shapes":
			return "СРАВНИ ЧИСЛО ГРАНЕЙ С ЦИФРОЙ\n[2] = РАВНО · [1] = НЕ РАВНО\n+2 B ЗА ВЕРНЫЙ ОТВЕТ"
		"stroop":
			return "СРАВНИ ЦВЕТ ТЕКСТА С ЕГО НАЗВАНИЕМ\n[2] = СОВПАДАЕТ · [1] = НЕТ\n+3 B ЗА ВЕРНЫЙ ОТВЕТ"
	return "ВСЕ ТИПЫ ЗАДАНИЙ ВПЕРЕМЕШКУ\nБАЙТОВ НЕТ · ЛЮБАЯ ОШИБКА — КОНЕЦ ИГРЫ"
