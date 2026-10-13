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


func _show_page_1() -> void:
	var lines: Array = [
		{"text": "  +==============================================+", "size": 16},
		{"text": "  |              HELP  --  PAGE 1/2              |", "size": 16},
		{"text": "  +==============================================+", "size": 16},
		{"text": "", "size": 14},
		{"text": "  ОБЩЕЕ", "size": 16, "color": Color(1.0, 0.9, 0.4)},
		{"text": "    Каждый верный ответ: комбо +1, время +1 сек,", "size": 14},
		{"text": "    байты +1..+3 (курс растёт с этапом).", "size": 14},
		{"text": "    Цель — набрать комбо 400.", "size": 14},
		{"text": "    Байты тратятся в SYSTEM UPDATE: там продаются", "size": 14},
		{"text": "    этапы-модули и механики (допуск/откат/пропуск).", "size": 14},
		{"text": "    Без купленного следующего этапа забег завер-", "size": 14},
		{"text": "    шается на границе — с выплатой байтов.", "size": 14},
		{"text": "", "size": 14},
		{"text": "  ЭТАП 1 — HEX-CYPHER  (буквы + цифры)", "size": 16, "color": Color(0.4, 1.0, 0.4)},
		{"text": "    ВЕРХНИЕ 2 сектора  :  буква", "size": 14},
		{"text": "       1 — согласная      2 — гласная", "size": 14},
		{"text": "    НИЖНИЕ 2 сектора   :  цифра", "size": 14},
		{"text": "       1 — нечётная       2 — чётная", "size": 14},
		{"text": "    ЖИРНЫЙ шрифт = инверсия ответа (1 <-> 2).", "size": 14, "color": Color(1.0, 0.7, 0.4)},
		{"text": "    Отражение символа на ответ НЕ влияет.", "size": 14},
		{"text": "", "size": 14},
		{"text": "  ЭТАП 2 — POLYMETRY  (фигуры)", "size": 16, "color": Color(0.4, 1.0, 0.4)},
		{"text": "    1 — граней НЕ равно цифре внутри", "size": 14},
		{"text": "    2 — граней РАВНО цифре внутри", "size": 14},
		{"text": "    Вместо цифры может быть пример (5+3).", "size": 14},
		{"text": "    Сначала посчитайте, потом сравните.", "size": 14},
		{"text": "    Две фигуры — сравнивается СУММА их граней.", "size": 14},
		{"text": "    Пропавшая грань — считаются ВИДИМЫЕ грани.", "size": 14, "color": Color(1.0, 0.7, 0.4)},
		{"text": "", "size": 14},
		{"text": "  [1]/[2] или [<-]/[->] — стр.   [ESC]/[ENTER] — назад", "size": 14, "color": Color(0.6, 0.6, 0.6)},
	]
	_render(lines)


func _show_page_2() -> void:
	var lines: Array = [
		{"text": "  +==============================================+", "size": 16},
		{"text": "  |              HELP  --  PAGE 2/2              |", "size": 16},
		{"text": "  +==============================================+", "size": 16},
		{"text": "", "size": 14},
		{"text": "  ЭТАП 3 — STROOPTEST  (тест Струпа)", "size": 16, "color": Color(0.4, 1.0, 0.4)},
		{"text": "    Показано НАЗВАНИЕ цвета, но текст окрашен", "size": 14},
		{"text": "    в ДРУГОЙ цвет. Сравнивайте цвет и название.", "size": 14},
		{"text": "    1 — цвет НЕ совпадает с названием", "size": 14},
		{"text": "    2 — цвет СОВПАДАЕТ с названием", "size": 14},
		{"text": "    ЖИРНЫЙ шрифт = инверсия ответа (1 <-> 2).", "size": 14, "color": Color(1.0, 0.7, 0.4)},
		{"text": "    Перемешанные буквы (ИСИЙН) — на ответ не влияют.", "size": 14},
		{"text": "", "size": 14},
		{"text": "  ЭТАП 4 — THE SEQUENCE  (финал)", "size": 16, "color": Color(1.0, 0.4, 0.4)},
		{"text": "    Все три режима вперемешку.", "size": 14},
		{"text": "    Байты НЕ начисляются.", "size": 14},
		{"text": "    ЛЮБАЯ ошибка — немедленный конец игры.", "size": 14, "color": Color(1.0, 0.4, 0.4)},
		{"text": "", "size": 14},
		{"text": "  ОШИБКИ И ОТКАТ", "size": 16, "color": Color(1.0, 0.9, 0.4)},
		{"text": "    Этапы 1-3 :  допуск ошибок (0..3 на этап) покупается", "size": 14},
		{"text": "                 в SYSTEM UPDATE. Без покупки любая", "size": 14},
		{"text": "                 ошибка фатальна.", "size": 14},
		{"text": "                 Нефатальная ошибка откатывает прогресс", "size": 14},
		{"text": "                 (сила отката — тоже покупка).", "size": 14},
		{"text": "    Этап  4   :  1 ошибка — конец.", "size": 14, "color": Color(1.0, 0.4, 0.4)},
		{"text": "", "size": 14},
		{"text": "  СБОЙ СИСТЕМЫ", "size": 16, "color": Color(1.0, 0.4, 0.4)},
		{"text": "    На экране — мусорные символы (@ # $ %).", "size": 14},
		{"text": "    НЕ НАЖИМАЙТЕ ничего. Любая кнопка = ошибка.", "size": 14, "color": Color(1.0, 0.4, 0.4)},
		{"text": "    Просто подождите секунду.", "size": 14},
		{"text": "", "size": 14},
		{"text": "  УПРАВЛЕНИЕ", "size": 16, "color": Color(1.0, 0.9, 0.4)},
		{"text": "    Ответ 1 :  [" + _binding_text_1 + "]     Ответ 2 :  [" + _binding_text_2 + "]", "size": 14},
		{"text": "    Изменить привязки — в CONFIGURATION.", "size": 14, "color": Color(0.6, 0.6, 0.6)},
		{"text": "    [F3] — debug-старт с заданного комбо", "size": 14, "color": Color(0.6, 0.6, 0.6)},
		{"text": "    [F4] — пауза", "size": 14, "color": Color(0.6, 0.6, 0.6)},
		{"text": "", "size": 14},
		{"text": "  [1]/[2] или [<-]/[->] — стр.   [ESC]/[ENTER] — назад", "size": 14, "color": Color(0.6, 0.6, 0.6)},
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
