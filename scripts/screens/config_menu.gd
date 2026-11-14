extends TerminalScreen

signal back_requested
signal bindings_changed(answer1: InputEvent, answer2: InputEvent)
signal settings_changed(volume: float, sfx_volume: float, crt: bool,
		music_fx: bool, reactivity: float)
# Экран не знает, где лежит прогресс: сброс выполняет main, результат
# возвращается сюда через on_progress_reset().
signal progress_reset_requested

var binding1: InputEvent
var binding2: InputEvent
var music_volume: float = 0.8
var sfx_volume: float = 0.8
var crt_enabled: bool = true
var music_fx_enabled: bool = true
var fx_reactivity: float = 0.3   # дефолт по STYLE.md: «кривая pow 1.5, дефолт 0.3»

var _selected: int = 0
var _options: Array = []
var _item_labels: Array = []
var _locked: bool = false
var _listening_for: int = -1  # -1 = не слушаем, 0 = answer1, 1 = answer2
var _hint_label: Label
var _dialog: ConfirmDialog

# Тексты нижней строки-подсказки: обычная, режим захвата клавиши, результат сброса.
const _HINT_DEFAULT := "  [W/S] NAV   [ENTER] SELECT   [<-/->] ADJUST   [MOUSE] CLICK   [ESC] BACK"
const _HINT_LISTENING := "  >> PRESS ANY KEY OR MOUSE BUTTON... [ESC] CANCEL"
const _HINT_RESET := "  PROGRESS CLEARED  [SETTINGS KEPT]"
const _HINT_RESET_SECONDS := 2.5
const _RESET_TITLE := "RESET PROGRESS?"
const _RESET_BODY := "BYTES, STAGES AND MECHANICS GO TO ZERO."
const _RESET_YES := "RESET"
const _RESET_NO := "KEEP"


func set_bindings(e1: InputEvent, e2: InputEvent) -> void:
	binding1 = e1
	binding2 = e2


func set_settings(volume: float, sfx_vol: float, crt: bool, music_fx: bool,
		reactivity: float = 0.3) -> void:
	music_volume = volume
	sfx_volume = sfx_vol
	crt_enabled = crt
	music_fx_enabled = music_fx
	fx_reactivity = reactivity


func _ready() -> void:
	super._ready()
	if binding1 == null:
		binding1 = InputEventKey.new()
		binding1.keycode = KEY_1
	if binding2 == null:
		binding2 = InputEventKey.new()
		binding2.keycode = KEY_2
	_dialog = ConfirmDialog.new()
	_dialog.confirmed.connect(_on_reset_confirmed)
	_dialog.cancelled.connect(_on_reset_cancelled)
	add_child(_dialog)
	_dialog.font = _font
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
		{"label": "FX REACTIVITY",       "value": "reactivity", "active": false, "suffix": "  [<] " + str(int(round(fx_reactivity * 100.0))) + "% [>]"},
		{"label": "CRT EFFECTS",         "value": "crt",        "active": crt_enabled, "suffix": ""},
		{"label": "MUSIC REACTIVE FX",   "value": "music_fx",   "active": music_fx_enabled, "suffix": ""},
		# Сброс прогресса — последний пункт перед выходом: про него нельзя
		# «промахнуться» колесом и он требует подтверждения.
		{"label": "RESET PROGRESS",      "value": "reset_progress", "active": false, "suffix": "  [ENTER]"},
		{"label": "BACK",                "value": "back",       "active": false, "suffix": ""},
	]

	_item_labels.clear()
	for i in _options.size():
		var lbl := add_line("", Color.WHITE, 22)
		_item_labels.append(lbl)

	add_line("", Color.WHITE, 20)
	_hint_label = add_line(_HINT_DEFAULT, Color(0.6, 0.6, 0.6), 14)
	_apply_hint()

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
		var mark := "  [x]" if opt["active"] else ""
		lbl.text = "  " + opt["label"] + opt["suffix"] + mark
		set_inverted(lbl, sel, Color(0.7, 0.7, 0.7), true)
		set_cursor_at(lbl, sel and _cursor_on)


func _on_cursor_blink() -> void:
	super._on_cursor_blink()
	if not _locked:
		_update_selection()


func _input(event: InputEvent) -> void:
	# Пока открыта плашка подтверждения, она — единственный адресат ввода:
	# делегируем ей до своих обработчиков (у диалога собственного _input()
	# нет намеренно, иначе он перехватывал бы события раньше экрана).
	if _dialog != null and _dialog.is_open():
		_dialog.handle_input(event)
		return
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
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_click_at(event.position)
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_WHEEL_UP:
				_wheel_adjust(event.position, 1)
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_wheel_adjust(event.position, -1)
				get_viewport().set_input_as_handled()
				return
			_:
				pass

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
			if opt["value"] in ["volume", "sfx_volume", "reactivity"]:
				_volume_click(lbl, pos, r)
			else:
				_select_option()
			return


# Хит-зоны реальных [<] и [>], а не «левая/правая половина»: раньше обе
# стрелки стояли в правой половине длинной строки, и клик по [ < ] тоже
# добавлял громкость (фидбек: мышь только увеличивает).
func _volume_click(lbl: Label, pos: Vector2, r: Rect2) -> void:
	var cell: float = _cell_width(lbl)
	if cell <= 0.0:
		return
	var rel: float = pos.x - r.position.x
	var t: String = lbl.text
	var li: int = t.find("[<]")
	var ri: int = t.find("[>]")
	if li >= 0 and rel >= float(li) * cell - cell * 0.6 and rel <= float(li + 3) * cell + cell * 0.6:
		_adjust_current(-1)
	elif ri >= 0 and rel >= float(ri) * cell - cell * 0.6 and rel <= float(ri + 3) * cell + cell * 0.6:
		_adjust_current(1)


# Колесо мыши над строкой громкости — крутит её (±10%).
func _wheel_adjust(pos: Vector2, dir: int) -> void:
	for i in _item_labels.size():
		var lbl: Label = _item_labels[i]
		if not lbl.get_global_rect().has_point(pos):
			continue
		var v: String = _options[i]["value"]
		if v != "volume" and v != "sfx_volume" and v != "reactivity":
			return
		_selected = i
		_update_selection()
		SFX.key()
		_adjust_current(dir)
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
	elif v == "reactivity":
		fx_reactivity = clampf(fx_reactivity + delta, 0.0, 1.0)
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
	if v == "reset_progress":
		# Только через подтверждение: ENTER открывает плашку, в ней выбран отказ.
		SFX.error()
		_dialog.open(_RESET_TITLE, _RESET_BODY, _RESET_YES, _RESET_NO)
		return
	if v == "volume" or v == "sfx_volume" or v == "reactivity":
		# Нажатие ENTER на строках-слайдерах ничего не делает,
		# регулировка — только через ←/→, колесо или клик по [<]/[>].
		return


func emit_settings() -> void:
	settings_changed.emit(music_volume, sfx_volume, crt_enabled,
		music_fx_enabled, fx_reactivity)


func _show_listening_hint() -> void:
	_set_hint(_HINT_LISTENING, Color(1, 0.85, 0.2))


# ---------- Нижняя строка статуса ----------
func _set_hint(text: String, color: Color) -> void:
	if _hint_label == null or not is_instance_valid(_hint_label):
		return
	_hint_label.text = text
	_hint_label.add_theme_color_override("font_color", color)


# Актуальный текст по состоянию экрана: пересборка строк или таймер возврата
# не должны терять режим (захват клавиши, сообщение о сбросе).
func _apply_hint() -> void:
	if _listening_for >= 0:
		_show_listening_hint()
	else:
		_set_hint(_HINT_DEFAULT, Color(0.6, 0.6, 0.6))


# Подтверждение в плашке: экран не знает, где лежит прогресс, — просит main.
func _on_reset_confirmed() -> void:
	progress_reset_requested.emit()


func _on_reset_cancelled() -> void:
	SFX.key()


# Колбэк main: прогресс обнулён и сохранён, настройки не тронуты.
func on_progress_reset() -> void:
	SFX.corrupted()
	_set_hint(_HINT_RESET, Color(1.0, 0.45, 0.35))
	var timer: SceneTreeTimer = get_tree().create_timer(_HINT_RESET_SECONDS)
	timer.timeout.connect(_apply_hint)


func _exit() -> void:
	# Без анимации выхода: навигационное нажатие не должно попадать
	# в мёртвое окно экрана (см. clear_instant).
	clear_instant()
	back_requested.emit()
