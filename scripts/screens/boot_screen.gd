extends TerminalScreen

signal boot_finished


func _ready() -> void:
	super._ready()
	SFX.booting()
	_run_boot()


func _run_boot() -> void:
	await get_tree().create_timer(0.5).timeout
	# Шапка печатается мгновенно (как в настоящем BIOS), а тест памяти —
	# ступенчатый счётчик, не «набор текста».
	add_line("AWARD BIOS v4.51PG (C) 1984-1998", Color.WHITE, 22)
	add_line("CPU: 486DX2-66  640K BASE MEMORY OK", Color.WHITE, 22)
	var mem_lbl := add_line("Memory test: 0K", Color.WHITE, 22)
	for kb in [256, 640, 2048, 8192, 16384]:
		if not is_inside_tree():
			return
		mem_lbl.text = "Memory test: %dK" % kb
		await get_tree().create_timer(0.14).timeout
	if not is_inside_tree():
		return
	mem_lbl.text = "Memory test: 16384K OK"
	var lines := [
		"",
		"Detecting IDE drives...",
		"  Primary Master   : 540MB",
		"  Primary Slave    : None",
		"  Secondary Master : CD-ROM 2X",
		"",
		"Loading OS kernel from C:\\SYSTEM\\...",
		"  |################################| 100%",
		"",
		"Initializing video adapter...",
		"Initializing keyboard controller...",
		"Mounting file systems...",
		"Starting terminal service...",
		"",
		"       TERMINAL READY",
	]
	await type_lines(lines, 0.14)
	await get_tree().create_timer(1.2).timeout
	await clear_animated(0.025)
	boot_finished.emit()
