extends TerminalScreen

signal back_requested

const PAGES := 2

var _page: int = 0
var _locked: bool = false
var _binding_text_1: String = "1"
var _binding_text_2: String = "2"


func set_bindings(e1: InputEvent, e2: InputEvent) -> void:
	_binding_text_1 = _format_event(e1)
	_binding_text_2 = _format_event(e2)


func _format_event(e: InputEvent) -> String:
	if e == null:
		return "?"
	if e is InputEventKey:
		var s := OS.get_keycode_string(e.keycode)
		return s if s != "" else "?"
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT:     return "LMB"
			MOUSE_BUTTON_RIGHT:    return "RMB"
			MOUSE_BUTTON_MIDDLE:   return "MMB"
			MOUSE_BUTTON_XBUTTON1: return "MB4"
			MOUSE_BUTTON_XBUTTON2: return "MB5"
		return "M" + str(e.button_index)
	return "?"


func _ready() -> void:
	super._ready()
	_show_page()


func _show_page() -> void:
	clear_all()
	if _page == 0:
		_show_page_1()
	else:
		_show_page_2()


func _render(lines: Array) -> void:
	for line in lines:
		if typeof(line) == TYPE_DICTIONARY:
			add_line(
				str(line.get("text", "")),
				line.get("color", Color.WHITE),
				int(line.get("size", 20))
			)
		else:
			add_line(str(line))


const GREEN := Color(0.4, 1.0, 0.4)
const YELLOW := Color(1.0, 0.9, 0.4)
const ORANGE := Color(1.0, 0.7, 0.4)
const RED := Color(1.0, 0.4, 0.4)
const GRAY := Color(0.6, 0.6, 0.6)
const DIM := Color(0.85, 0.85, 0.85)


func _show_page_1() -> void:
	# Отдача 12: крупнее шрифт, схема квадрантов вместо сухих списков,
	# правила — одной строкой каждое.
	var lines: Array = [
		{"text": "  +==================================================+", "size": 20},
		{"text": "  |              HELP  --  PAGE 1/2                  |", "size": 20},
		{"text": "  +==================================================+", "size": 20},
		{"text": "", "size": 8},
		{"text": "  КАК ОТВЕЧАТЬ", "size": 22, "color": YELLOW},
		{"text": "    Квадрант даёт задание. Ответь [1] или [2]:", "size": 19},
		{"text": "    твои клавиши:  [1]=" + _binding_text_1 + "   [2]=" + _binding_text_2
			+ "   (смена — в CONFIG)", "size": 19, "color": GREEN},
		{"text": "    Одно и то же задание читается по-разному сверху и снизу:", "size": 19},
		{"text": "    +----------+----------+      ВВЕРХУ  — судим БУКВУ", "size": 18, "color": DIM},
		{"text": "    |    K4    |          |      K4: К — согласная -> [1]", "size": 18, "color": DIM},
		{"text": "    +----------+----------+", "size": 18, "color": DIM},
		{"text": "    |    K4    |          |      ВНИЗУ   — судим ЦИФРУ", "size": 18, "color": DIM},
		{"text": "    |          |          |      K4: 4 — чётная    -> [2]", "size": 18, "color": DIM},
		{"text": "    +----------+----------+", "size": 18, "color": DIM},
		{"text": "", "size": 8},
		{"text": "  ЭТАП 1 — HEX-CYPHER  (буква + цифра)", "size": 22, "color": GREEN},
		{"text": "    БУКВА:  A E I O  — гласная -> [2],  любая другая -> [1]", "size": 19},
		{"text": "    ЦИФРА:  2 4 6 8  — чётная  -> [2],  нечётная     -> [1]", "size": 19},
		{"text": "    ЖИРНЫЙ знак = ответ НАОБОРОТ (1 <-> 2).", "size": 19, "color": ORANGE},
		{"text": "    Перевёрнутый символ — только трюк: черточка под 6/9", "size": 19},
		{"text": "    подсказывает, где верх. Отражение на ответ не влияет.", "size": 19},
		{"text": "", "size": 8},
		{"text": "  [2] / [->] — далее    [ESC] / [ENTER] — назад", "size": 16, "color": GRAY},
	]
	_render(lines)


func _show_page_2() -> void:
	var lines: Array = [
		{"text": "  +==================================================+", "size": 20},
		{"text": "  |              HELP  --  PAGE 2/2                  |", "size": 20},
		{"text": "  +==================================================+", "size": 20},
		{"text": "", "size": 8},
		{"text": "  ЭТАП 2 — POLYMETRY  (фигуры)", "size": 22, "color": GREEN},
		{"text": "    Сравни цифру внутри с числом граней фигуры.", "size": 19},
		{"text": "    Треугольник и цифра 3 : граней 3 = 3 -> [2]", "size": 19},
		{"text": "    Квадрат и цифра 5     : граней 4 != 5 -> [1]", "size": 19},
		{"text": "    ( ) + цифра: круг НЕ имеет граней — 0 против цифры.", "size": 19},
		{"text": "    Две фигуры — сравни СУММУ граней. «5+3» — сначала посчитай.", "size": 19},
		{"text": "    Пропала грань — считай ВИДИМЫЕ.", "size": 19, "color": ORANGE},
		{"text": "", "size": 8},
		{"text": "  ЭТАП 3 — STROOPTEST  (цвета)", "size": 22, "color": GREEN},
		{"text": "    Сравни ЦВЕТ надписи с её НАЗВАНИЕМ:", "size": 19},
		{"text": "      КРАСНЫЙ", "size": 24, "color": Color(0.15, 0.25, 0.95)},
		{"text": "      ^ нарисовано синим: не совпало -> [1]", "size": 16, "color": GRAY},
		{"text": "    Совпало -> [2]. ЖИРНЫЙ = наоборот.", "size": 19},
		{"text": "    Перемешанные буквы (ИСИЙН) не влияют на ответ.", "size": 19},
		{"text": "", "size": 8},
		{"text": "  ЭТАП 4 — THE SEQUENCE: все режимы вперемешку,", "size": 22, "color": RED},
		{"text": "    ЛЮБАЯ ошибка — конец. Байтов не даёт.", "size": 19, "color": RED},
		{"text": "", "size": 8},
		{"text": "  СБОЙ И ОШИБКИ", "size": 22, "color": YELLOW},
		{"text": "    Мусор на экране (@ # $ %) — НИЧЕГО не жми, пережди.", "size": 19, "color": RED},
		{"text": "    Допуск ошибок и откат покупаются в SYSTEM UPDATE;", "size": 19},
		{"text": "    без допуска любая ошибка фатальна. Комбо 400 = победа.", "size": 19},
		{"text": "", "size": 8},
		{"text": "  [1] / [<-] — назад    [ESC] / [ENTER] — выход", "size": 16, "color": GRAY},
	]
	_render(lines)


func _input(event: InputEvent) -> void:
	if _locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# Экран — единственный потребитель: не даём ивенту долететь до игры.
		get_viewport().set_input_as_handled()
		match event.keycode:
			KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
				SFX.key()
				_locked = true
				await clear_animated(0.03)
				back_requested.emit()
			KEY_1:
				SFX.key()
				_page = 0
				_show_page()
			KEY_2:
				SFX.key()
				_page = 1
				_show_page()
			KEY_LEFT:
				SFX.key()
				_page = (_page - 1 + PAGES) % PAGES
				_show_page()
			KEY_RIGHT:
				SFX.key()
				_page = (_page + 1) % PAGES
				_show_page()
