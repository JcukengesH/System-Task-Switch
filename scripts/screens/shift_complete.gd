extends TerminalScreen
# Забег дошёл до границы установленных модулей: следующий этап не куплен.
# Позитивная развязка: зарплата в байтах и намёк на SYSTEM UPDATE.

signal restart_requested
signal menu_requested

var completed_stages: int = 1   # сколько этапов пройдено (1..4)
var progress_pct: int = 0
var bytes_earned: int = 0

var _handled: bool = false
var _input_enabled: bool = false


func _ready() -> void:
	super._ready()
	_start_input_delay()
	_run()


func _start_input_delay() -> void:
	# Как в lose_cutscene: секунда, чтобы не «зарестартить» в запале.
	await get_tree().create_timer(1.0).timeout
	if not _handled and is_inside_tree():
		_input_enabled = true


func _run() -> void:
	await get_tree().create_timer(0.4).timeout

	var lines: Array = [
		"> PROCESSING QUEUE...",
		"> ALL INSTALLED MODULES VERIFIED",
		"",
	]
	await type_lines(lines, 0.12)
	if _handled:
		return

	var total: int = Meta.STAGE_LABELS.size()
	for i in range(completed_stages):
		add_line("  [STAGE %d/%d]  %s >> OK" % [i + 1, total, Meta.STAGE_LABELS[i]],
			Color(0.4, 1.0, 0.4), 20)
		await get_tree().create_timer(0.3).timeout
		if _handled:
			return
	for i in range(completed_stages, total):
		add_line("  [STAGE %d/%d]  %s >> NOT INSTALLED" % [i + 1, total, Meta.STAGE_LABELS[i]],
			Color(0.5, 0.5, 0.5), 18)

	add_line("", Color.WHITE, 20)
	add_line("  +----------------------------------+", Color(1, 0.85, 0.2), 20)
	add_line("  |   HARDWARE LIMIT REACHED         |", Color(1, 0.85, 0.2), 20)
	add_line("  +----------------------------------+", Color(1, 0.85, 0.2), 20)
	await get_tree().create_timer(0.4).timeout
	if _handled:
		return

	add_line("", Color.WHITE, 20)
	add_line("> SALARY     : +%d BYTES" % bytes_earned, Color(0.45, 1, 0.45), 22)
	add_line("> PROGRESS   : %d%%" % progress_pct, Color(1, 0.85, 0.2), 20)
	add_line("> NEW MODULES AVAILABLE IN [SYSTEM UPDATE]", Color(1, 0.85, 0.2), 20)

	await get_tree().create_timer(0.4).timeout
	if _handled:
		return

	add_line("", Color.WHITE, 20)
	add_line("  [ESC] - RETURN TO MENU", Color(0.7, 0.7, 0.7), 22)
	add_line("  [ANY] - RUN AGAIN", Color.WHITE, 24)


func _input(event: InputEvent) -> void:
	if _handled or not _input_enabled:
		return

	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		SFX.key()
		_handled = true
		# Не даём тому же press долететь до игры после мгновенного рестарта.
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE:
			_exit_to_menu()
		else:
			restart_requested.emit()
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, \
			MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2:
				SFX.key()
				_handled = true
				get_viewport().set_input_as_handled()
				restart_requested.emit()


func _exit_to_menu() -> void:
	add_line("", Color.WHITE, 20)
	add_line("> RETURNING TO MAIN MENU...", Color(0.7, 0.7, 0.7), 20)
	await get_tree().create_timer(0.7).timeout
	await clear_animated(0.03)
	menu_requested.emit()
