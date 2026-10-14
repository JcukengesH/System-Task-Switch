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
const RED := Color(1.0, 0.4, 0.4)
const GRAY := Color(0.6, 0.6, 0.6)
const DIM := Color(0.85, 0.85, 0.85)


func _show_page_1() -> void:
	# Кратко: как отвечать + по одной строке на этап. Модификаторы — стр. 2.
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
		{"text": "  ЭТАПЫ", "size": 22, "color": YELLOW},
		{"text": "    1 HEX-CYPHER   буква: гласная -> [2]; цифра: чётная -> [2]", "size": 19, "color": GREEN},
		{"text": "    2 POLYMETRY    граней vs цифра: равно -> [2]. Круг — 0", "size": 19, "color": GREEN},
		{"text": "    3 STROOPTEST   чернила против названия слова:", "size": 19, "color": GREEN},
		{"text": "        КРАСНЫЙ", "size": 22, "color": Color(0.15, 0.25, 0.95)},
		{"text": "        ^ синие чернила — не совпало -> [1]", "size": 16, "color": GRAY},
		{"text": "    4 THE SEQUENCE все задания вперемешку", "size": 19, "color": RED},
		{"text": "", "size": 8},
		{"text": "    Модификаторы по ходу забега — на стр. 2.", "size": 19},
		{"text": "  [2] / [->] — далее    [ESC] / [ENTER] — назад", "size": 16, "color": GRAY},
	]
	_render(lines)


func _show_page_2() -> void:
	# Страница модификаторов: имена те же, что вспыхивают на весь экран
	# при включении (см. MOD_FLASH_NAMES в main.gd).
	var lines: Array = [
		{"text": "  +==================================================+", "size": 20},
		{"text": "  |              HELP  --  PAGE 2/2                  |", "size": 20},
		{"text": "  +==================================================+", "size": 20},
		{"text": "", "size": 8},
		{"text": "  МОДИФИКАТОРЫ", "size": 22, "color": YELLOW},
		{"text": "    Включаются по ходу забега — имя вспыхнет на весь экран.", "size": 19},
		{"text": "    ПОРЯДОК-    задание в случайном углу (этап 1)", "size": 19},
		{"text": "    ПЕРЕВОРОТ+  знак перевёрнут — на ответ не влияет (1, 3)", "size": 19},
		{"text": "    ИНВЕРСИЯ+   ЖИРНЫЙ знак = ответ наоборот, 1<->2 (1, 3)", "size": 19},
		{"text": "    ГРАНЬ-      фигуре не хватает грани — считай видимые (2)", "size": 19},
		{"text": "    ПРИМЕР+     вместо цифры пример «5+3» — посчитай (2)", "size": 19},
		{"text": "    ФИГУРА+     две фигуры — сравнивай СУММУ граней (2)", "size": 19},
		{"text": "    ДИСЛЕКСИЯ+  буквы слова перемешаны — сравнивай как есть (3)", "size": 19},
		{"text": "    ПОМЕХИ+     мусор «@ # $ %» — НИЧЕГО не жми, пережди (все)", "size": 19, "color": RED},
		{"text": "    ВСЁ+        этап 4: все режимы вперемешку", "size": 19, "color": RED},
		{"text": "    ОШИБКИ = 0  этап 4: любая ошибка — конец игры", "size": 19, "color": RED},
		{"text": "", "size": 8},
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
