extends TerminalScreen

signal back_requested
signal bindings_changed(answer1: InputEvent, answer2: InputEvent)
signal settings_changed(volume: float, sfx_volume: float, crt: bool, music_fx: bool)

var binding1: InputEvent
var binding2: InputEvent
var music_volume: float = 0.8
var sfx_volume: float = 0.8
var crt_enabled: bool = true
var music_fx_enabled: bool = true

var _selected: int = 0
var _options: Array = []
var _item_labels: Array = []
var _locked: bool = false
var _listening_for: int = -1  # -1 = не слушаем, 0 = answer1, 1 = answer2
var _hint_label: Label


func set_bindings(e1: InputEvent, e2: InputEvent) -> void:
	binding1 = e1
	binding2 = e2


func set_settings(volume: float, sfx_vol: float, crt: bool, music_fx: bool) -> void:
	music_volume = volume
	sfx_volume = sfx_vol
	crt_enabled = crt
	music_fx_enabled = music_fx


func _ready() -> void:
	super._ready()
	if binding1 == null:
		binding1 = InputEventKey.new()
		binding1.keycode = KEY_1
	if binding2 == null:
		binding2 = InputEventKey.new()
		binding2.keycode = KEY_2
	_rebuild()


func _rebuild() -> void:
	var prev_selected := _selected
	clear_all()
	add_line("", Color.WHITE, 22)
	add_line("  +======================================+", Color.WHITE, 22)
	add_line("  |            CONFIGURATION             |", Color.WHITE, 22)
	add_line("  +======================================+", Color.WHITE, 22)
	add_line("", Color.WHITE, 20)

	# Оба fullscreen-режима (оконный и эксклюзивный) считаем «FULLSCREEN»;
	# MAXIMIZED (дефолт проекта) показывается как оконный режим.
	var mode: int = DisplayServer.window_get_mode()
	var is_full: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_options = [
		{"label": "DISPLAY: FULLSCREEN", "value": "fullscreen", "active": is_full, "suffix": ""},
		{"label": "DISPLAY: WINDOWED",   "value": "windowed",   "active": not is_full, "suffix": ""},
		{"label": "ANSWER 1",            "value": "bind1",      "active": false, "suffix": " [" + _format_event(binding1) + "]"},
		{"label": "ANSWER 2",            "value": "bind2",      "active": false, "suffix": " [" + _format_event(binding2) + "]"},
		{"label": "MUSIC VOLUME",        "value": "volume",     "active": false, "suffix": "  [<] " + str(int(round(music_volume * 100.0))) + "% [>]"},
		{"label": "SFX VOLUME",          "value": "sfx_volume", "active": false, "suffix": "  [<] " + str(int(round(sfx_volume * 100.0))) + "% [>]"},
		{"label": "CRT EFFECTS",         "value": "crt",        "active": crt_enabled, "suffix": ""},
		{"label": "MUSIC REACTIVE FX",   "value": "music_fx",   "active": music_fx_enabled, "suffix": ""},
		{"label": "BACK",                "value": "back",       "active": false, "suffix": ""},
	]

	_item_labels.clear()
	for i in _options.size():
		var lbl := add_line("", Color.WHITE, 22)
		_item_labels.append(lbl)

	add_line("", Color.WHITE, 20)
	_hint_label = add_line("  [W/S] NAV   [ENTER] SELECT   [<-/->] ADJUST   [MOUSE] CLICK   [ESC] BACK",
		Color(0.6, 0.6, 0.6), 14)

	_selected = prev_selected
	if _selected >= _options.size():
		_selected = 0
	_update_selection()


func _format_event(e: InputEvent) -> String:
	if e == null:
		return "?"
	if e is InputEventKey:
		var s := OS.get_keycode_string(e.keycode)
		return s if s != "" else "?"
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT:     return "MOUSE L"
			MOUSE_BUTTON_RIGHT:    return "MOUSE R"
			MOUSE_BUTTON_MIDDLE:   return "MOUSE M"
			MOUSE_BUTTON_XBUTTON1: return "MOUSE 4"
			MOUSE_BUTTON_XBUTTON2: return "MOUSE 5"
		return "MOUSE " + str(e.button_index)
	return "?"


func _update_selection() -> void:
	for i in _item_labels.size():
		var lbl: Label = _item_labels[i]
		if not is_instance_valid(lbl):
			continue
		var opt: Dictionary = _options[i]
		var sel: bool = i == _selected
		var cursor := "█" if (sel and _cursor_on) else " "
		var mark := "  [x]" if opt["active"] else ""
		lbl.text = "  " + opt["label"] + opt["suffix"] + mark + cursor
		set_inverted(lbl, sel)


func _on_cursor_blink() -> void:
	super._on_cursor_blink()
	if not _locked:
		_update_selection()


func _input(event: InputEvent) -> void:
	if _locked:
		return
	if _listening_for >= 0:
		# Режим переназначения: съедаем весь ввод, включая тики колеса,
		# пока не получим новую клавишу/кнопку.
		get_viewport().set_input_as_handled()
		_handle_capture(event)
		return

	if event is InputEventMouseMotion:
		_hover_at(event.position)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click_at(event.position)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		match event.keycode:
			KEY_W, KEY_UP:
				_selected = (_selected - 1 + _options.size()) % _options.size()
				_update_selection()
				SFX.key()
			KEY_S, KEY_DOWN:
				_selected = (_selected + 1) % _options.size()
				_update_selection()
				SFX.key()
			KEY_LEFT:
				SFX.key()
				_adjust_current(-1)
			KEY_RIGHT:
				SFX.key()
				_adjust_current(1)
			KEY_ESCAPE:
				SFX.key()
				_locked = true
				await _exit()
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				SFX.key()
				_select_option()


func _hover_at(pos: Vector2) -> void:
	for i in _item_labels.size():
		var lbl: Label = _item_labels[i]
		if lbl.get_global_rect().has_point(pos):
			if _selected != i:
				_selected = i
				_update_selection()
				SFX.key()
			return


func _click_at(pos: Vector2) -> void:
	for i in _item_labels.size():
		var lbl: Label = _item_labels[i]
		var r: Rect2 = lbl.get_global_rect()
		if r.has_point(pos):
			var opt: Dictionary = _options[i]
			_selected = i
			_update_selection()
			SFX.key()
			if opt["value"] == "volume" or opt["value"] == "sfx_volume":
				# Левая половина строки = -, правая = +.
				var mid: float = r.position.x + r.size.x * 0.5
				_adjust_current(-1 if pos.x < mid else 1)
			else:
				_select_option()
			return


func _adjust_current(dir: int) -> void:
	var v: String = _options[_selected]["value"]
	var delta: float = 0.10 * float(dir)
	if v == "volume":
		music_volume = clampf(music_volume + delta, 0.0, 1.0)
		emit_settings()
		_rebuild()
	elif v == "sfx_volume":
		sfx_volume = clampf(sfx_volume + delta, 0.0, 1.0)
		emit_settings()
		_rebuild()


func _handle_capture(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_listening_for = -1
			_rebuild()
			return
		var k := InputEventKey.new()
		k.keycode = event.keycode
		_apply_binding(k)
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, \
			MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2:
				var mb := InputEventMouseButton.new()
				mb.button_index = event.button_index
				_apply_binding(mb)
			_:
				pass


func _apply_binding(new_event: InputEvent) -> void:
	SFX.key()
	if _listening_for == 0:
		binding1 = new_event
	elif _listening_for == 1:
		binding2 = new_event
	_listening_for = -1
	bindings_changed.emit(binding1, binding2)
	_rebuild()


func _select_option() -> void:
	var v: String = _options[_selected]["value"]
	if v == "back":
		_locked = true
		await _exit()
		return
	if v == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_rebuild()
		return
	if v == "windowed":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_rebuild()
		return
	if v == "bind1":
		_listening_for = 0
		_show_listening_hint()
		return
	if v == "bind2":
		_listening_for = 1
		_show_listening_hint()
		return
	if v == "crt":
		crt_enabled = not crt_enabled
		emit_settings()
		_rebuild()
		return
	if v == "music_fx":
		music_fx_enabled = not music_fx_enabled
		emit_settings()
		_rebuild()
		return
	if v == "volume" or v == "sfx_volume":
		# Нажатие ENTER на строках громкости ничего не делает,
		# регулировка — только через ←/→ или клик. Игнорируем.
		return


func emit_settings() -> void:
	settings_changed.emit(music_volume, sfx_volume, crt_enabled, music_fx_enabled)


func _show_listening_hint() -> void:
	if _hint_label and is_instance_valid(_hint_label):
		_hint_label.text = "  >> PRESS ANY KEY OR MOUSE BUTTON... [ESC] CANCEL"
		_hint_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))


func _exit() -> void:
	await clear_animated(0.03)
	back_requested.emit()
