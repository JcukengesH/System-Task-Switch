extends TerminalScreen

signal back_requested

const PAGES := 2

var _page: int = 0
var _locked: bool = false
var _binding_text_1: String = "1"
var _binding_text_2: String = "2"
# Кликабельные строки навигации: {"label": Label, "kind": "prev"|"next"|"back"}.
var _nav_rows: Array[Dictionary] = []
var _hovered: int = -1


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
	_build_nav()


# Кликабельная навигация (фидбек 2026-11-14: мышью должно быть можно
# пользоваться везде). Две строки: переключение страниц (левая половина —
# назад, правая — вперёд) и выход. Хит-зоны считаются по моноширинной
# ячейке, как в config_menu._volume_click.
func _build_nav() -> void:
	_nav_rows.clear()
	_hovered = -1
	var prev_next := add_line("  < PREV PAGE        NEXT PAGE >  ", Color(0.7, 0.7, 0.7), 18)
	var back := add_line("        [ ESC ]  BACK TO MENU         ", Color(0.7, 0.7, 0.7), 18)
	_nav_rows = [
		{"label": prev_next, "kind": "paging"},
		{"label": back, "kind": "back"},
	]


func _nav_hit(pos: Vector2) -> int:
	for i: int in _nav_rows.size():
		var lbl: Label = _nav_rows[i]["label"]
		if lbl != null and is_instance_valid(lbl) and lbl.get_global_rect().has_point(pos):
			return i
	return -1


func _nav_action(index: int, pos: Vector2) -> void:
	var kind := String(_nav_rows[index]["kind"])
	SFX.key()
	if kind == "back":
		_go_back()
		return
	# Строка paging: левая половина — предыдущая страница, правая — следующая.
	var lbl: Label = _nav_rows[index]["label"]
	var cell: float = _cell_width(lbl)
	var rel_columns: float = (pos.x - lbl.get_global_rect().position.x) / cell if cell > 0.0 else 0.0
	if rel_columns < float(lbl.text.find("NEXT")) * 0.5:
		_flip_page(-1)
	else:
		_flip_page(1)


func _flip_page(step: int) -> void:
	_page = (_page + step + PAGES) % PAGES
	_show_page()


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
		{"text": "    4 THE SEQUENCE вперемешку, угол случайный", "size": 19, "color": RED},
		{"text": "", "size": 8},
		{"text": "    Модификаторы по ходу забега — на стр. 2.", "size": 19},
		{"text": "  [2] / [->] / КОЛЕСО — далее    [ESC] / [ENTER] — назад", "size": 16, "color": GRAY},
	]
	_render(lines)


func _show_page_2() -> void:
	# Страница модификаторов: имена те же, что вспыхивают на весь экран
	# при включении (см. MOD_FLASH_NAMES в session_presentation.gd).
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
		{"text": "  [1] / [<-] — назад    [ESC] / [ENTER] — выход    МЫШЬ: клик по строкам", "size": 16, "color": GRAY},
	]
	_render(lines)


func _input(event: InputEvent) -> void:
	if _locked:
		return
	# Мышь: наведение подсвечивает строку, ЛКМ срабатывает, колесо листает.
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var index := _nav_hit(event.position)
				if index >= 0:
					get_viewport().set_input_as_handled()
					_nav_action(index, event.position)
				return
			MOUSE_BUTTON_WHEEL_UP:
				get_viewport().set_input_as_handled()
				_flip_page(-1)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				get_viewport().set_input_as_handled()
				_flip_page(1)
				return
			_:
				return

	if event is InputEventKey and event.pressed and not event.echo:
		# Экран — единственный потребитель: не даём ивенту долететь до игры.
		get_viewport().set_input_as_handled()
		match event.keycode:
			KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
				SFX.key()
				_go_back()
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
				_flip_page(-1)
			KEY_RIGHT:
				SFX.key()
				_flip_page(1)


func _go_back() -> void:
	_locked = true
	clear_instant()
	back_requested.emit()


func _update_hover(pos: Vector2) -> void:
	var index := _nav_hit(pos)
	if index == _hovered:
		return
	_hovered = index
	for i: int in _nav_rows.size():
		var lbl: Label = _nav_rows[i]["label"]
		if lbl != null and is_instance_valid(lbl):
			set_inverted(lbl, i == index)
