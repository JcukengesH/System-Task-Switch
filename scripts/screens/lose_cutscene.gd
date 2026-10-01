extends TerminalScreen

signal restart_requested
signal menu_requested

var reason: String = "errors_limit"
var failed_stage: int = 1
var progress_pct: int = 0

var _handled: bool = false
var _input_enabled: bool = false
var _input_delay_timer: SceneTreeTimer = null

func _ready() -> void:
	super._ready()
	_start_input_delay()
	_run()


func _start_input_delay() -> void:
	# Задержка 1 сек: игрок не должен случайно зарестартить
	# в запале после смерти.
	_input_delay_timer = get_tree().create_timer(1.0)
	await _input_delay_timer.timeout
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
			return "ОШИБКА В МАСТЕР-РЕЖИМЕ"
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

	await get_tree().create_timer(0.4).timeout
	if _handled:
		return

	add_line("", Color.WHITE, 20)
	add_line("> REINITIALIZE PROCEDURE?", Color.WHITE, 22)
	add_line("", Color.WHITE, 20)
	add_line("  [ESC] - CANCEL / RETURN TO MENU", Color(0.7, 0.7, 0.7), 22)
	add_line("  [ANY] - RESTART PROTOCOL", Color.WHITE, 24)


func _input(event: InputEvent) -> void:
	if _handled or not _input_enabled:
		return

	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		SFX.key()
		_handled = true
		if event.keycode == KEY_ESCAPE:
			_exit_to_menu()
		else:
			restart_requested.emit()
		return

	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if event.button_index not in [
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
			MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2
		]:
			return
		SFX.key()
		_handled = true
		restart_requested.emit()
		
func _exit_to_menu() -> void:
	# Визуальный переход. Рестарт остаётся мгновенным, а тут игрок
	# сам выбрал «выйти» — не торопимся.
	add_line("", Color.WHITE, 20)
	add_line("> RETURNING TO MAIN MENU...", Color(0.7, 0.7, 0.7), 20)
	await get_tree().create_timer(0.7).timeout
	await clear_animated(0.03)
	menu_requested.emit()
