extends TerminalScreen

signal cutscene_finished

const CANCEL_TIMEOUT := 5.0
const PASSWORD := "0778518456"


var _waiting_for_input: bool = false
var _entered: String = ""
var _password_label: Label
var _timer_label: Label
var _time_left: float = CANCEL_TIMEOUT
var _abort_requested: bool = false


func _ready() -> void:
	super._ready()
	_run()


func _run() -> void:
	await get_tree().create_timer(0.5).timeout

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

	# Все этапы пройдены — выводим OK для каждого.
	var total: int = STAGE_NAMES.size()
	for i in range(total):
		add_line("  [STAGE %d/%d]  %s >> OK" % [i + 1, total, STAGE_NAMES[i]],
			Color(0.4, 1.0, 0.4), 20)
		await get_tree().create_timer(0.35).timeout

	add_line("", Color.WHITE, 20)
	add_line("  *** *** *** *** *** *** *** *** ***", Color(0.4, 1.0, 0.4), 22)
	add_line("  !!!   PROTOCOL ARMED         !!!", Color(0.4, 1.0, 0.4), 26)
	add_line("  *** *** *** *** *** *** *** *** ***", Color(0.4, 1.0, 0.4), 22)
	await get_tree().create_timer(0.8).timeout

	add_line("", Color.WHITE, 20)
	add_line("> STATUS     : ARMED       (PROGRESS: 100%)", Color(1, 0.85, 0.2), 20)
	add_line("> IMPERATOR PROTOCOL IS READY FOR LAUNCH.", Color(1, 0.85, 0.2), 20)
	add_line("> WARNING: THIS ACTION CANNOT BE UNDONE.", Color(1, 0.6, 0.2), 20)

	await get_tree().create_timer(1.0).timeout

	add_line("", Color.WHITE, 20)
	add_line("> AUTHORIZATION REQUIRED TO ABORT.", Color.WHITE, 22)

	_password_label = add_line("> PASSWORD: _", Color(1, 0.85, 0.2), 22)
	_timer_label = add_line("> TIME TO ENTER: 5.0 s", Color(0.7, 0.7, 0.7), 18)

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


func _input(event: InputEvent) -> void:
	if not _waiting_for_input or _abort_requested:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var digit: int = event.keycode - KEY_0
			_entered += str(digit)
			SFX.key()
			_refresh_password_label()
			_check_password()
			return
		if event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
			var digit: int = event.keycode - KEY_KP_0
			_entered += str(digit)
			SFX.key()
			_refresh_password_label()
			_check_password()
			return
		if event.keycode == KEY_BACKSPACE:
			if _entered.length() > 0:
				_entered = _entered.substr(0, _entered.length() - 1)
				SFX.key()
				_refresh_password_label()
			return


func _check_password() -> void:
	if _entered == PASSWORD:
		_abort_requested = true
	elif _entered.length() >= PASSWORD.length():
		_entered = ""
		_refresh_password_label()
