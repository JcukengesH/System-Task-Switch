extends TerminalScreen

signal restart_requested
signal menu_requested
signal shop_requested

var reason: String = "errors_limit"
var failed_stage: int = 1
var progress_pct: int = 0
var bytes_earned: int = 0
var bytes_balance: int = 0

const ITEMS := ["RESTART PROTOCOL", "OPEN SYSTEM UPDATE", "RETURN TO MAIN MENU"]

var _handled: bool = false
var _input_enabled: bool = false
var _item_labels: Array = []
var _selected: int = 0
var _menu_ready: bool = false

func _ready() -> void:
	super._ready()
	_start_input_delay()
	_run()


func _start_input_delay() -> void:
	# Задержка 1 сек: игрок не должен случайно зарестартить
	# в запале после смерти.
	await get_tree().create_timer(1.0).timeout
	# Если экран уже закрыли (handled), НЕ включаем ввод: иначе этот
	# «висячий» await через секунду повторно эмитировал бы restart/menu.
	if not _handled and is_inside_tree():
		_input_enabled = true


func _reason_code() -> String:
	match reason:
		"timeout":
			return "CONNECTION TIMEOUT / SIGNAL LOST"
		"master_error":
			return "AUTHORIZATION REJECTED / CRITICAL FAULT"
		"aborted":
			return "SEQUENCE ABORTED"
		_:
			return "TOO MANY FAILURES / OPERATOR UNRELIABLE"


func _reason_ru() -> String:
	match reason:
		"timeout":
			return "ВРЕМЯ ИСТЕКЛО"
		"master_error":
			return "ОШИБКА В THE SEQUENCE"
		"aborted":
			return "ПРОЦЕСС ОСТАНОВЛЕН ПОЛЬЗОВАТЕЛЕМ"
		_:
			return "ПРЕВЫШЕН ЛИМИТ ОШИБОК"


func _run() -> void:
	await get_tree().create_timer(0.4).timeout

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

	if _handled:
		return

	var total: int = STAGE_NAMES.size()
	for i in range(total):
		var stage_num: int = i + 1
		if stage_num < failed_stage:
			add_line("  [STAGE %d/%d]  %s >> OK" % [stage_num, total, STAGE_NAMES[i]],
				Color(0.4, 1.0, 0.4), 20)
		elif stage_num == failed_stage:
			add_line("  [STAGE %d/%d]  %s >> >>> ERROR <<<" % [stage_num, total, STAGE_NAMES[i]],
				Color(1, 0.3, 0.3), 22)
			break
		else:
			break
		await get_tree().create_timer(0.35).timeout
		if _handled:
			return

	add_line("", Color.WHITE, 20)
	add_line("  *** *** *** *** *** *** *** *** ***", Color(1, 0.1, 0.1), 22)
	add_line("  !!!   PROTOCOL INTERRUPTED    !!!", Color(1, 0.1, 0.1), 26)
	add_line("  *** *** *** *** *** *** *** *** ***", Color(1, 0.1, 0.1), 22)
	await get_tree().create_timer(0.5).timeout
	if _handled:
		return

	add_line("", Color.WHITE, 20)
	add_line("> ERROR CODE : " + _reason_code(), Color(1, 0.6, 0.2), 20)
	add_line("> REASON     : " + _reason_ru(), Color(1, 0.6, 0.2), 20)
	add_line("> STATUS     : TERMINATED  (PROGRESS: %d%%)" % progress_pct, Color(1, 0.6, 0.2), 20)
	if bytes_earned > 0:
		add_line("> SALARY     : +%d BYTES" % bytes_earned, Color(0.45, 1.0, 0.45), 20)
	add_line("> BALANCE    : %d BYTES" % bytes_balance, Color(0.45, 1.0, 0.45), 20)

	await get_tree().create_timer(0.4).timeout
	if _handled:
		return

	add_line("", Color.WHITE, 20)
	add_line("> REINITIALIZE PROCEDURE?", Color.WHITE, 22)
	add_line("", Color.WHITE, 20)
	_build_menu()


func _build_menu() -> void:
	_item_labels.clear()
	for i in ITEMS.size():
		_item_labels.append(add_line("", Color.WHITE, 24))
	add_line("", Color.WHITE, 20)
	add_line("  [W/S] SELECT   [ENTER] CONFIRM   [MOUSE] HOVER+CLICK   [ANY] QUICK RESTART",
		Color(0.6, 0.6, 0.6), 16)
	_update_selection()
	_menu_ready = true


func _update_selection() -> void:
	for i in _item_labels.size():
		var prefix: String = ("  >> [%d] " % (i + 1)) if i == _selected else ("     [%d] " % (i + 1))
		_item_labels[i].text = prefix + ITEMS[i]
		_item_labels[i].add_theme_color_override("font_color",
			Color.WHITE if i == _selected else Color(0.7, 0.7, 0.7))


func _move(delta: int) -> void:
	_selected = (_selected + delta + ITEMS.size()) % ITEMS.size()
	_update_selection()


func _item_at(pos: Vector2) -> int:
	for i in _item_labels.size():
		if _item_labels[i].get_global_rect().has_point(pos):
			return i
	return -1


func _hover_at(pos: Vector2) -> void:
	var idx := _item_at(pos)
	if idx >= 0 and _selected != idx:
		_selected = idx
		_update_selection()
		SFX.key()


func _activate(idx: int) -> void:
	if _handled or not _menu_ready:
		return
	_handled = true
	# Гасим событие: клик-рестарт (он же кнопка ответа) не должен долететь
	# до _unhandled_input игры после синхронного emit.
	get_viewport().set_input_as_handled()
	SFX.key()
	match idx:
		1:
			shop_requested.emit()
		2:
			_exit_to_menu()
		_:
			restart_requested.emit()


func _input(event: InputEvent) -> void:
	if _handled or not _input_enabled or not _menu_ready:
		return

	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		match event.keycode:
			KEY_W, KEY_UP:
				SFX.key()
				_move(-1)
			KEY_S, KEY_DOWN:
				SFX.key()
				_move(1)
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				_activate(_selected)
			KEY_1, KEY_2, KEY_3:
				_activate(event.keycode - KEY_1)
			KEY_ESCAPE:
				_activate(2)
			_:
				# Наследие старого экрана: любая прочая клавиша = быстрый рестарт.
				_activate(0)
		return

	if event is InputEventMouseMotion:
		_hover_at(event.position)
		return

	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			SFX.key()
			_move(-1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			SFX.key()
			_move(1)
			return
		if event.button_index not in [
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
			MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2
		]:
			return
		var idx := _item_at(event.position)
		if idx >= 0:
			_activate(idx)
		else:
			# Клик по пустому месту = быстрый рестарт, как раньше.
			_activate(0)


func _exit_to_menu() -> void:
	# Визуальный переход. Рестарт остаётся мгновенным, а тут игрок
	# сам выбрал «выйти» — не торопимся.
	add_line("", Color.WHITE, 20)
	add_line("> RETURNING TO MAIN MENU...", Color(0.7, 0.7, 0.7), 20)
	await get_tree().create_timer(0.7).timeout
	await clear_animated(0.03)
	menu_requested.emit()
