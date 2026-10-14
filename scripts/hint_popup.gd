class_name HintPopup
extends RefCounted
# Попап-подсказка в стиле «терминальное окно»: появляется по центру, не
# перекрывает символы в квадрантах и не принимает ввод (mouse_filter = IGNORE
# у всех узлов). Правила этапа висят до нескольких нажатий ответа.
# Включения модификаторов объявляет НЕ попап, а полноэкранный баннер в
# main.gd (flash_announcements) — по принципу большой цифры ошибки.
# main.gd: build(parent) в _ready; далее show_stage / on_answer_press /
# hide_popup / start_run.

const MODE_PRESSURES := 3   # попап правил висит до 3-х нажатий

var _panel: PanelContainer
var _title: Label
var _rule: Label
var _keys: Label
var _presses: int = 0       # >0: попап висит до N нажатий ответа


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
		_rule_text(mode), keys_line, MODE_PRESSURES)


# Новый забег: снять попап правил предыдущего (баннеры модификаторов — в main.gd).
func start_run() -> void:
	hide_popup()


func on_answer_press() -> void:
	if _presses > 0:
		_presses -= 1
		if _presses <= 0:
			hide_popup()


func hide_popup() -> void:
	_presses = 0
	if _panel == null or not is_instance_valid(_panel) or not _panel.visible:
		return
	# Дискретно: исчезает сразу, без угасания.
	_panel.modulate = Color(1, 1, 1, 1)
	_panel.visible = false


func _show(title: String, rule: String, keys_line: String, presses: int) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_title.text = title
	_rule.text = rule
	var has_keys: bool = keys_line != ""
	_keys.visible = has_keys
	if has_keys:
		_keys.text = keys_line
	_presses = presses
	_panel.visible = true
	# Аутентичный стиль: попап не проявляется фейдом — он либо есть, либо нет,
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
