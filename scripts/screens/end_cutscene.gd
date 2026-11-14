extends TerminalScreen

signal cutscene_finished

const CANCEL_TIMEOUT := 5.0
const PASSWORD := "0778518456"


var _waiting_for_input: bool = false
var _entered: String = ""
var bytes_earned: int = 0
var _password_label: Label
var _timer_label: Label
var _time_left: float = CANCEL_TIMEOUT
var _abort_requested: bool = false
# Кликабельная цифровая панель (фидбек: мышью должно быть можно играть везде).
# Строки рисуем одной Label-строкой, хит-тест — по моноширинной ячейке,
# как в config_menu._volume_click: новых контейнеров в _vbox не появляется.
const KEYPAD_ROWS: Array[String] = [
	"  [1] [2] [3] [4] [5]",
	"  [6] [7] [8] [9] [0]",
	"  [DEL]   [CLR]   [OK]",
]
const KEYPAD_DIM := Color(0.7, 0.7, 0.7)
const KEYPAD_LIT := Color(1.0, 0.85, 0.2)

var _keypad_labels: Array[Label] = []
var _keypad_hover := -1  # индекс подсвеченной строки, -1 = никто


func _ready() -> void:
	super._ready()
	_run()


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	# Страховка: экран мог быть снят (queue_free) во время паузы — тогда
	# продолжать печатать нельзя.
	if not is_inside_tree():
		return

	var lines: Array = [
		"> ACCESSING SECURE NODE 0x7F...",
		"> AUTH: [OK]",
		"> DECRYPTING PAYLOAD...",
		"  [||||||||||||||||||||] 100%",
		"> LOADING PROTOCOL: << IMPERATOR >>",
		"",
		"  +----------------------------------+",
		"  |      PROJECT IMPERATOR           |",
		"  |      CLASSIFIED // TOP SECRET    |",
		"  +----------------------------------+",
		"",
		"> INITIATING SEQUENCE...",
	]
	await type_lines(lines, 0.13)
	if not is_inside_tree():
		return

	# Все этапы пройдены — выводим OK для каждого.
	var total: int = STAGE_NAMES.size()
	for i in range(total):
		add_line("  [STAGE %d/%d]  %s >> OK" % [i + 1, total, STAGE_NAMES[i]],
			Color(0.4, 1.0, 0.4), 20)
		await get_tree().create_timer(0.35).timeout
		if not is_inside_tree():
			return

	add_line("", Color.WHITE, 20)
	add_line("  *** *** *** *** *** *** *** *** ***", Color(0.4, 1.0, 0.4), 22)
	add_line("  !!!   PROTOCOL ARMED         !!!", Color(0.4, 1.0, 0.4), 26)
	add_line("  *** *** *** *** *** *** *** *** ***", Color(0.4, 1.0, 0.4), 22)
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return

	add_line("", Color.WHITE, 20)
	add_line("> STATUS     : ARMED       (PROGRESS: 100%)", Color(1, 0.85, 0.2), 20)
	if bytes_earned > 0:
		add_line("> SALARY     : +%d BYTES" % bytes_earned, Color(0.45, 1.0, 0.45), 20)
	add_line("> IMPERATOR PROTOCOL IS READY FOR LAUNCH.", Color(1, 0.85, 0.2), 20)
	add_line("> WARNING: THIS ACTION CANNOT BE UNDONE.", Color(1, 0.6, 0.2), 20)

	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return

	add_line("", Color.WHITE, 20)
	add_line("> AUTHORIZATION REQUIRED TO ABORT.", Color.WHITE, 22)

	_password_label = add_line("> PASSWORD: _", Color(1, 0.85, 0.2), 22)
	_timer_label = add_line("> TIME TO ENTER: 5.0 s", Color(0.7, 0.7, 0.7), 18)
	_build_keypad()

	_waiting_for_input = true
	await _countdown_loop()


func _countdown_loop() -> void:
	while _time_left > 0.0 and not _abort_requested:
		if not is_inside_tree():
			return
		await get_tree().create_timer(0.05).timeout
		_time_left -= 0.05
		if _timer_label and is_instance_valid(_timer_label):
			_timer_label.text = "> TIME TO ENTER: %.1f s" % maxf(0.0, _time_left)

	# Фаза ввода закончилась (таймаут или принятый пароль): панель больше
	# не кликабельна — гасим её, чтобы не выглядела активной.
	_waiting_for_input = false
	_set_keypad_active(false)
	if _abort_requested:
		if _timer_label and is_instance_valid(_timer_label):
			_timer_label.visible = false
		add_line("", Color.WHITE, 20)
		add_line("> PASSWORD ACCEPTED.", Color(0.4, 1.0, 0.4), 22)
		add_line("> OPERATION ABORTED BY USER.", Color(1, 0.8, 0.2), 22)
		add_line("> RETURNING TO MAIN MENU...", Color(0.7, 0.7, 0.7), 20)
		await get_tree().create_timer(1.8).timeout
		await clear_animated(0.03)
		cutscene_finished.emit()
	else:
		add_line("", Color.WHITE, 20)
		add_line("> AUTHENTICATION FAILED.", Color(1, 0.4, 0.4), 22)
		add_line("> IMPERATOR PROTOCOL IS NOW ACTIVE.", Color(1, 0.2, 0.2), 24)
		add_line("> GOD SAVE THE EMPEROR.", Color(0.9, 0.1, 0.1), 24)
		await get_tree().create_timer(2.8).timeout
		await clear_animated(0.03)
		cutscene_finished.emit()


func _refresh_password_label() -> void:
	if _password_label == null or not is_instance_valid(_password_label):
		return
	_password_label.text = "> PASSWORD: " + _entered + "_"


func _build_keypad() -> void:
	_keypad_labels.clear()
	_keypad_hover = -1
	for row: String in KEYPAD_ROWS:
		var lbl := add_line(row, KEYPAD_DIM, 20)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_keypad_labels.append(lbl)
	# Подсказка: мышь дублирует клавиатуру, таймер идёт своим чередом.
	add_line("  [KEYS 0-9] / [MOUSE] CLICK   [BACKSPACE] DELETE", Color(0.6, 0.6, 0.6), 16)


# Токен под курсором в строке: "[1]" -> "1", "[DEL]" -> "DEL", вне кнопки -> "".
func _keypad_token(text: String, column: int) -> String:
	var open_at := text.find("[")
	while open_at >= 0:
		var close_at: int = text.find("]", open_at)
		if close_at < 0:
			break
		if column >= open_at and column <= close_at:
			return text.substr(open_at + 1, close_at - open_at - 1)
		open_at = text.find("[", close_at)
	return ""


func _keypad_row_index(pos: Vector2) -> int:
	for i: int in _keypad_labels.size():
		var lbl: Label = _keypad_labels[i]
		if lbl != null and is_instance_valid(lbl) and lbl.get_global_rect().has_point(pos):
			return i
	return -1


func _keypad_token_at(pos: Vector2) -> String:
	var index := _keypad_row_index(pos)
	if index < 0:
		return ""
	var lbl: Label = _keypad_labels[index]
	var cell: float = _cell_width(lbl)
	if cell <= 0.0:
		return ""
	var column := int(floor((pos.x - lbl.get_global_rect().position.x) / cell))
	return _keypad_token(lbl.text, column)


func _update_keypad_hover(pos: Vector2) -> void:
	var hover_row := _keypad_row_index(pos)
	if hover_row == _keypad_hover:
		return  # цвет уже верный: движение мыши не перекрашивает 3 строки
	_keypad_hover = hover_row
	for i: int in _keypad_labels.size():
		var lbl: Label = _keypad_labels[i]
		if lbl == null or not is_instance_valid(lbl):
			continue
		lbl.add_theme_color_override("font_color", KEYPAD_LIT if i == hover_row else KEYPAD_DIM)


# Панель неактивна: после таймаута/принятого пароля она остаётся на экране
# как часть расшифровки, но не выглядит clickable (без анимации — modulate
# скачком, по STYLE.md переходы дискретны).
func _set_keypad_active(active: bool) -> void:
	for lbl: Label in _keypad_labels:
		if lbl == null or not is_instance_valid(lbl):
			continue
		lbl.modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.3)


func _keypad_press(token: String) -> void:
	match token:
		"":
			return
		"DEL":
			_delete_digit()
		"CLR":
			_entered = ""
			SFX.key()
			_refresh_password_label()
		"OK":
			SFX.key()
			_check_password()
		_:
			_enter_digit(token.to_int())


func _enter_digit(digit: int) -> void:
	_entered += str(digit)
	SFX.key()
	_refresh_password_label()
	_check_password()


func _delete_digit() -> void:
	if _entered.is_empty():
		return
	_entered = _entered.substr(0, _entered.length() - 1)
	SFX.key()
	_refresh_password_label()


func _input(event: InputEvent) -> void:
	if not _waiting_for_input or _abort_requested:
		return
	# Мышь: наведение подсвечивает ряд, клик по кнопке вводит символ.
	if event is InputEventMouseMotion:
		_update_keypad_hover(event.position)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			_delete_digit()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var token := _keypad_token_at(event.position)
		if token.is_empty():
			return
		get_viewport().set_input_as_handled()
		_keypad_press(token)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# Ввод пароля: экран — единственный потребитель.
		get_viewport().set_input_as_handled()
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_enter_digit(event.keycode - KEY_0)
			return
		if event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
			_enter_digit(event.keycode - KEY_KP_0)
			return
		if event.keycode == KEY_BACKSPACE:
			_delete_digit()
			return


func _check_password() -> void:
	if _entered == PASSWORD:
		_abort_requested = true
	elif _entered.length() >= PASSWORD.length():
		_entered = ""
		_refresh_password_label()
