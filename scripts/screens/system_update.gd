extends TerminalScreen
# Магазин улучшений «SYSTEM UPDATE». Покупки валидирует и применяет main.gd
# через buy_handler; после покупки main присылает свежий снапшот в apply_meta().

signal back_requested

var buy_handler: Callable
var _meta: Dictionary = {}

var _selected: int = 0
var _options: Array = []
var _item_labels: Array = []
var _locked: bool = false


# NOTE: не set_meta — имя занято Object.set_meta(StringName, Variant) в Godot.
func apply_meta(m: Dictionary) -> void:
	_meta = m.duplicate(true)
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	super._ready()
	_rebuild()


func _stage_owned(s: String) -> bool:
	if s == "letters":
		return true
	return bool(_meta.get("stages", {}).get(s, false))


func _lvl(key: String) -> int:
	return int(_meta.get(key, 0))


func _build_rows() -> Array:
	var rows: Array = []
	var bytes: int = int(_meta.get("bytes", 0))

	rows.append({"header": true, "text": "  -- МОДУЛИ ЭТАПОВ ------------------"})
	for i in Meta.STAGE_ORDER.size():
		var s: String = Meta.STAGE_ORDER[i]
		var label: String = Meta.STAGE_LABELS[i + 1]
		var price: int = int(Meta.STAGE_PRICES[s])
		if _stage_owned(s):
			rows.append({"text": "  МОДУЛЬ: %-13s" % label, "suffix": "[УСТАНОВЛЕНО]",
				"enabled": false, "value": ""})
		else:
			var prev_ok: bool = i == 0 or _stage_owned(Meta.STAGE_ORDER[i - 1])
			if not prev_ok:
				rows.append({"text": "  МОДУЛЬ: %-13s" % label,
					"suffix": "[НУЖЕН %s]" % Meta.STAGE_LABELS[i],
					"enabled": false, "value": ""})
			else:
				rows.append({"text": "  МОДУЛЬ: %-13s" % label,
					"suffix": "%d B" % price, "enabled": true, "value": "stage_" + s})

	rows.append({"header": true, "text": "  -- МЕХАНИКИ -----------------------"})

	# Допуск ошибок.
	var tol: int = _lvl("tolerance")
	if tol >= 3:
		rows.append({"text": "  ДОПУСК ОШИБОК: УР.3/3", "suffix": "[МАКС]",
			"enabled": false, "value": ""})
	else:
		rows.append({"text": "  ДОПУСК ОШИБОК: УР.%d/3 -> УР.%d" % [tol, tol + 1],
			"suffix": "%d B" % Meta.TOLERANCE_PRICES[tol],
			"enabled": true, "value": "tolerance"})

	# Откат прогресса: линия заблокирована до допуска 1-го уровня.
	var rb: int = _lvl("rollback")
	if tol < 1:
		rows.append({"text": "  ОТКАТ ПРОГРЕССА", "suffix": "[НУЖЕН ДОПУСК УР.1]",
			"enabled": false, "value": ""})
	elif rb >= 3:
		rows.append({"text": "  ОТКАТ: УР.3/3 (%s)" % Meta.ROLLBACK_DESC[3],
			"suffix": "[МАКС]", "enabled": false, "value": ""})
	else:
		rows.append({"text": "  ОТКАТ: УР.%d/3 -> УР.%d (%s)" % [rb, rb + 1, Meta.ROLLBACK_DESC[rb + 1]],
			"suffix": "%d B" % Meta.ROLLBACK_PRICES[rb],
			"enabled": true, "value": "rollback"})

	# Пропуск этапа: ур.N требует этап N купленным + 300 очков в предыдущем.
	var sk: int = _lvl("skip")
	if sk >= 3:
		rows.append({"text": "  ПРОПУСК: УР.3/3 (СТАРТ: THE SEQUENCE)", "suffix": "[МАКС]",
			"enabled": false, "value": ""})
	else:
		var need_stage: String = Meta.STAGE_ORDER[sk]
		var prev_stage: String = "letters" if sk == 0 else Meta.STAGE_ORDER[sk - 1]
		var life: int = int(_meta.get("life", {}).get(prev_stage, 0))
		var cond_ok: bool = _stage_owned(need_stage) and life >= Meta.SKIP_REQ_POINTS
		if not cond_ok:
			var why: String = ""
			if not _stage_owned(need_stage):
				why = "[НУЖЕН МОДУЛЬ %s]" % Meta.STAGE_LABELS[sk + 1]
			else:
				why = "[НУЖНО %d/%d ОЧКОВ: %s]" % [life, Meta.SKIP_REQ_POINTS, Meta.STAGE_LABELS[sk]]
			rows.append({"text": "  ПРОПУСК: УР.%d/3 -> УР.%d (СТАРТ: %s)" % [sk, sk + 1, Meta.STAGE_LABELS[sk + 1]],
				"suffix": why, "enabled": false, "value": ""})
		else:
			rows.append({"text": "  ПРОПУСК: УР.%d/3 -> УР.%d (СТАРТ: %s)" % [sk, sk + 1, Meta.STAGE_LABELS[sk + 1]],
				"suffix": "%d B" % Meta.SKIP_PRICES[sk], "enabled": true, "value": "skip"})

	rows.append({"text": "  НАЗАД", "suffix": "", "enabled": false, "value": "back"})
	# Байты показываем в шапке, но строка нужна для единообразия навигации.
	return rows


func _rebuild() -> void:
	var prev_selected := _selected
	clear_all()
	add_line("", Color.WHITE, 20)
	add_line("  +======================================+", Color.WHITE, 20)
	add_line("  |            SYSTEM UPDATE             |", Color.WHITE, 20)
	add_line("  +======================================+", Color.WHITE, 20)
	add_line("  BYTES: %d" % int(_meta.get("bytes", 0)), Color(0.45, 1, 0.45), 20)
	add_line("", Color.WHITE, 12)

	_options = _build_rows()
	_item_labels.clear()
	for row in _options:
		if row.get("header", false):
			add_line(str(row.get("text", "")), Color(0.55, 0.55, 0.55), 18)
			continue
		_item_labels.append(add_line("", Color.WHITE, 18))

	add_line("", Color.WHITE, 12)
	var life: Dictionary = _meta.get("life", {})
	add_line("  ОЧКИ ЗА ВСЁ ВРЕМЯ: HEX %d · POLY %d · STR %d · SEQ %d" % [
		int(life.get("letters", 0)), int(life.get("shapes", 0)),
		int(life.get("stroop", 0)), int(life.get("master", 0)),
	], Color(0.6, 0.6, 0.6), 16)
	add_line("  [W/S] NAV   [ENTER] BUY   [MOUSE] CLICK   [ESC] BACK",
		Color(0.6, 0.6, 0.6), 14)

	# Индекс выбора — среди navigable-строк.
	_selected = clampi(prev_selected, 0, _nav_count() - 1)
	_update_selection()


func _nav_count() -> int:
	var n := 0
	for row in _options:
		if not row.get("header", false):
			n += 1
	return n


# _selected хранит индекс среди navigable-строк; переводим в индекс _options.
func _option_index(nav_idx: int) -> int:
	var n := -1
	for i in _options.size():
		if not _options[i].get("header", false):
			n += 1
			if n == nav_idx:
				return i
	return 0


func _update_selection() -> void:
	var nav := 0
	for i in _options.size():
		var row: Dictionary = _options[i]
		if row.get("header", false):
			continue
		var lbl: Label = _item_labels[nav]
		var prefix := ">> " if nav == _selected else "   "
		lbl.text = "  " + prefix + str(row.get("text", "")).substr(2) + "  " + str(row.get("suffix", ""))
		var color: Color = Color.WHITE
		if nav == _selected:
			color = Color(1, 0.85, 0.2) if row.get("enabled", false) else Color(1, 0.4, 0.4)
		elif not row.get("enabled", false):
			color = Color(0.5, 0.5, 0.5)
		lbl.add_theme_color_override("font_color", color)
		nav += 1


func _try_buy() -> void:
	var row: Dictionary = _options[_option_index(_selected)]
	var v: String = str(row.get("value", ""))
	if v == "back":
		_locked = true
		SFX.key()
		await clear_animated(0.03)
		back_requested.emit()
		return
	if v == "":
		SFX.error()
		return
	if buy_handler.is_valid():
		buy_handler.call(v)


func _input(event: InputEvent) -> void:
	if _locked:
		return

	if event is InputEventMouseMotion:
		_hover_at(event.position)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click_at(event.position)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W, KEY_UP:
				_selected = (_selected - 1 + _nav_count()) % _nav_count()
				_update_selection()
				SFX.key()
			KEY_S, KEY_DOWN:
				_selected = (_selected + 1) % _nav_count()
				_update_selection()
				SFX.key()
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				_try_buy()
			KEY_ESCAPE:
				_locked = true
				SFX.key()
				await clear_animated(0.03)
				back_requested.emit()


func _nav_at(pos: Vector2) -> int:
	var nav := 0
	for i in _options.size():
		if _options[i].get("header", false):
			continue
		var lbl: Label = _item_labels[nav]
		if lbl.get_global_rect().has_point(pos):
			return nav
		nav += 1
	return -1


func _hover_at(pos: Vector2) -> void:
	var nav := _nav_at(pos)
	if nav >= 0 and nav != _selected:
		_selected = nav
		_update_selection()
		SFX.key()


func _click_at(pos: Vector2) -> void:
	var nav := _nav_at(pos)
	if nav < 0:
		return
	_selected = nav
	_update_selection()
	SFX.key()
	_try_buy()
