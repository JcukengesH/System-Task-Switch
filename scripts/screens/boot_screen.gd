extends TerminalScreen

signal boot_finished


func _ready() -> void:
	super._ready()
	SFX.booting()
	_run_boot()


func _run_boot() -> void:
	await get_tree().create_timer(0.5).timeout
	var lines := [
		"AWARD BIOS v4.51PG (C) 1984-1998",
		"CPU: 486DX2-66  640K BASE MEMORY OK",
		"Memory test: 16384K OK",
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
