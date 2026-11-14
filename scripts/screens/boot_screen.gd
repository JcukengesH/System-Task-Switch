extends TerminalScreen

signal boot_finished

var _cursor_target: Label
var _skipped: bool = false


func _ready() -> void:
	super._ready()
	SFX.booting()
	_run_boot()


# Любая клавиша/клик форсирует конец POST: ~5 с непропускаемого ожидания
# раздражали (ревью 2026-11-14). Аутентичность пути остаётся — без нажатия
# POST идёт в своём темпе.
func _input(event: InputEvent) -> void:
	if _skipped:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed):
		_skipped = true
		get_viewport().set_input_as_handled()


# Курсор мигает только на финальной строке POST (как на реальном BIOS),
# до готовности цели — спрятан.
func _on_cursor_blink() -> void:
	super._on_cursor_blink()
	var ready_target: bool = _cursor_target != null and is_instance_valid(_cursor_target) \
		and _cursor_target.visible
	set_cursor_at(_cursor_target if ready_target else null, _cursor_on and ready_target)


func _wait(t: float) -> void:
	if _skipped:
		return
	await get_tree().create_timer(t).timeout


func _run_boot() -> void:
	await _wait(0.35)
	# Классический POST AWARD: шапка вываливается мгновенно блоком (BIOS не
	# «печатает» тексты — он их пишет в видеопамять сразу), память —
	# ступенчатый счётчик с «OK», устройства — короткие неровные паузы.
	add_line("AWARD Modular BIOS v4.51PG, Copyright (C) 1984-1998", Color.WHITE, 22)
	add_line("Award Software, Inc.", Color.WHITE, 22)
	await _wait(0.25)
	add_line("P6OP1029A.BA0  486/586", Color(0.85, 0.85, 0.85), 18)
	await _wait(0.3)
	add_line("CPU: Intel 486DX2-66MHz", Color.WHITE, 20)
	add_line("Internal Cache: 256KB  On", Color.WHITE, 20)
	await _wait(0.25)
	add_line("", Color.WHITE, 14)

	var base_lbl := add_line("Base Memory Test : 0K", Color.WHITE, 20)
	for kb in [128, 256, 384, 512, 640]:
		if not is_inside_tree():
			return
		base_lbl.text = "Base Memory Test : %dK" % kb
		await _wait(0.08)
	base_lbl.text = "Base Memory Test : 640K OK"
	await _wait(0.2)

	var ext_lbl := add_line("Extended Memory Test : 0K", Color.WHITE, 20)
	for kb in [1024, 2048, 4096, 8192, 12288, 16384]:
		if not is_inside_tree():
			return
		ext_lbl.text = "Extended Memory Test : %dK" % kb
		await _wait(0.07)
	ext_lbl.text = "Extended Memory Test : 16384K OK"
	await _wait(0.25)

	if not is_inside_tree():
		return
	var detect := [
		"",
		"Detecting IDE Primary Master   ... QUANTUM FIREBALL 540MB",
		"Detecting IDE Primary Slave    ... None",
		"Detecting IDE Secondary Master ... CD-ROM 24X",
		"",
		"Keyboard Controller ... 82H INT 5",
		"Press DEL to enter SETUP",
	]
	await type_lines(detect, 0.0 if _skipped else 0.13)
	if not is_inside_tree():
		return
	await _wait(0.7)

	var load := [
		"",
		"BOOTING FROM C:\\ ...",
		"  |###############################| 100%",
		"Loading SYSTEM.SYS ............ OK",
		"Loading TERMINAL.SYS .......... OK",
		"Mounting file systems ......... OK",
		"Starting terminal service ...",
	]
	await type_lines(load, 0.0 if _skipped else 0.1)
	if not is_inside_tree():
		return

	add_line("", Color.WHITE, 14)
	add_line("       TERMINAL READY", Color(0.4, 1.0, 0.4), 24)
	# Курсор — на пустой строке под заголовком, как мигающий ввод BIOS.
	_cursor_target = add_line("", Color.WHITE, 24)
	set_cursor_at(_cursor_target, true)
	await _wait(1.1)
	if _skipped:
		clear_instant()
	else:
		await clear_animated(0.025)
	boot_finished.emit()
