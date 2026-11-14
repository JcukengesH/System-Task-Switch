extends TerminalScreen
# Магазин улучшений «SYSTEM UPDATE». Покупки валидирует и применяет main.gd
# через buy_handler; после покупки main присылает свежий снапшот в apply_meta().
# Отдача 13: две колонки (модули этапов / механики), карточки из двух строк
# (что + почём), крупнее шрифт, псевдографические рамки.

signal back_requested
signal debug_free_requested

var buy_handler: Callable
var _meta: Dictionary = {}
# Дебаг-режим (F2, debug-сборки): карточки доступны всегда, покупка=цикл
# уровня/снятие без байтов. Значение передаёт main.gd через ScreenRouter.
var debug_free: bool = false

var _selected: int = 0
var _options: Array = []          # навигационный порядок: этапы, механики, НАЗАД
var _item_labels: Array = []      # заголовки карточек (по ним идёт rect-навигация)
var _status_labels: Array = []    # вторые строки карточек (цена/статус)
var _locked: bool = false

const COL_BG := Color(0.55, 0.55, 0.55)
const SEL_ON := Color(1.0, 0.85, 0.2)
const SEL_OFF := Color(1.0, 0.4, 0.4)
const DIM := Color(0.5, 0.5, 0.5)
const GOOD := Color(0.45, 1.0, 0.45)
const LOW := Color(1.0, 0.6, 0.3)


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


func _bytes() -> int:
	return int(_meta.get("bytes", 0))


# Истина только для отладочных сборок: в релизе флаг main.gd не ставится,
# но и экран не должен реагировать на чужое значение переменной.
func _debug_on() -> bool:
	return debug_free and OS.is_debug_build()


# Карточка: name — заголовок, status — вторая строка; enabled участвует в
# подсветке и в праве покупки; affordable красит цену.
func _card(name: String, status: String, enabled: bool, value: String,
		owned: bool = false, price: int = -1) -> Dictionary:
	return {"name": name, "status": status, "enabled": enabled,
		"value": value, "owned": owned, "price": price}


func _build_stage_cards() -> Array:
	var cards: Array = []
	for i in Meta.STAGE_ORDER.size():
		var s: String = Meta.STAGE_ORDER[i]
		var label: String = Meta.STAGE_LABELS[i + 1]
		var price: int = int(Meta.STAGE_PRICES[s])
		if _stage_owned(s):
			cards.append(_card("МОДУЛЬ: " + label, "УСТАНОВЛЕНО", false, "", true))
		else:
			var prev_ok: bool = i == 0 or _stage_owned(Meta.STAGE_ORDER[i - 1])
			if not prev_ok:
				cards.append(_card("МОДУЛЬ: " + label,
					"СНАЧАЛА: " + Meta.STAGE_LABELS[i], false, ""))
			else:
				cards.append(_card("МОДУЛЬ: " + label, "ЦЕНА: %d B" % price,
					true, "stage_" + s, false, price))
	return cards


func _build_mech_cards() -> Array:
	var cards: Array = []
	var tol: int = _lvl("tolerance")
	if tol >= 3:
		cards.append(_card("ДОПУСК ОШИБОК  УР.3/3", "МАКСИМУМ", false, "", true))
	else:
		cards.append(_card("ДОПУСК ОШИБОК  УР.%d -> УР.%d" % [tol, tol + 1],
			"ЦЕНА: %d B" % Meta.TOLERANCE_PRICES[tol], true, "tolerance",
			false, Meta.TOLERANCE_PRICES[tol]))

	# Откат прогресса: линия заблокирована до допуска 1-го уровня.
	var rb: int = _lvl("rollback")
	if tol < 1:
		cards.append(_card("ОТКАТ ПРОГРЕССА", "НУЖЕН ДОПУСК УР.1", false, ""))
	elif rb >= 3:
		cards.append(_card("ОТКАТ  УР.3/3 (%s)" % Meta.ROLLBACK_DESC[3],
			"МАКСИМУМ", false, "", true))
	else:
		cards.append(_card("ОТКАТ  УР.%d -> УР.%d" % [rb, rb + 1],
			"ЦЕНА: %d B · %s" % [Meta.ROLLBACK_PRICES[rb], Meta.ROLLBACK_DESC[rb + 1]],
			true, "rollback", false, Meta.ROLLBACK_PRICES[rb]))

	# Пропуск этапа: ур.N требует этап N купленным + 300 очков в предыдущем.
	var sk: int = _lvl("skip")
	if sk >= 3:
		cards.append(_card("ПРОПУСК  УР.3/3  СТАРТ: THE SEQUENCE",
			"МАКСИМУМ", false, "", true))
	else:
		var need_stage: String = Meta.STAGE_ORDER[sk]
		var prev_stage: String = "letters" if sk == 0 else Meta.STAGE_ORDER[sk - 1]
		var life: int = int(_meta.get("life", {}).get(prev_stage, 0))
		var cond_ok: bool = _stage_owned(need_stage) and life >= Meta.SKIP_REQ_POINTS
		var head: String = "ПРОПУСК  УР.%d -> УР.%d" % [sk, sk + 1]
		if not cond_ok:
			var why: String
			if not _stage_owned(need_stage):
				why = "НУЖЕН МОДУЛЬ " + Meta.STAGE_LABELS[sk + 1]
			else:
				why = "НУЖНО ОЧКОВ: %d/%d В %s" % [life, Meta.SKIP_REQ_POINTS,
					Meta.STAGE_LABELS[sk]]
			cards.append(_card(head + " · СТАРТ: " + Meta.STAGE_LABELS[sk + 1], why, false, ""))
		else:
			cards.append(_card(head + " · СТАРТ: " + Meta.STAGE_LABELS[sk + 1],
				"ЦЕНА: %d B" % Meta.SKIP_PRICES[sk], true, "skip",
				false, Meta.SKIP_PRICES[sk]))
	return cards


func _rebuild() -> void:
	var prev_selected := _selected
	clear_all()
	add_line("", Color.WHITE, 12)
	add_line("  +==========================================+", Color.WHITE, 22)
	add_line("  |              SYSTEM UPDATE               |", Color.WHITE, 22)
	add_line("  +==========================================+", Color.WHITE, 22)
	add_line("  BYTES: %d" % _bytes(), GOOD, 22)
	add_line("", Color.WHITE, 8)

	# Две колонки: [модули этапов] | [механики]. Навигация линейная:
	# левая колонка сверху вниз, затем правая, затем НАЗАД.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(columns)

	var stage_cards := _build_stage_cards()
	var mech_cards := _build_mech_cards()
	if _debug_on():
		# Порядок массивов = Meta.STAGE_ORDER и [tolerance, rollback, skip]:
		# все карточки кликабельны, value проставляется принудительно.
		for i in stage_cards.size():
			var sc: Dictionary = stage_cards[i]
			sc["enabled"] = true
			sc["value"] = "stage_" + str(Meta.STAGE_ORDER[i])
			sc["status"] = "СНИТЬ (бесплатно)" if bool(sc.get("owned", false)) \
				else "УСТАНОВИТЬ (бесплатно)"
		var mech_values := ["tolerance", "rollback", "skip"]
		# Порядок _build_mech_cards жёстко связан с этим списком (см. также
		# комментарий у stage-цикла): любая правка секций обязана сохранить
		# три карточки в этом же порядке.
		assert(mech_cards.size() == mech_values.size())
		for i in mech_cards.size():
			var mc: Dictionary = mech_cards[i]
			mc["enabled"] = true
			mc["value"] = str(mech_values[i])
			mc["status"] = "ЦИКЛ УРОВНЯ +1 -> 0 (бесплатно)"
	var back := _card("НАЗАД", "В ГЛАВНОЕ МЕНЮ", false, "back")
	_options = stage_cards + mech_cards + [back]

	_item_labels.clear()
	_status_labels.clear()
	var left := _build_column(columns, "МОДУЛИ ЭТАПОВ", 32)
	var right := _build_column(columns, "МЕХАНИКИ СИСТЕМЫ", 32)
	for card in stage_cards:
		_add_card(left, card)
	for card in mech_cards:
		_add_card(right, card)
	_add_card(right, back)

	add_line("", Color.WHITE, 8)
	var life: Dictionary = _meta.get("life", {})
	add_line("  ОЧКИ ЗА ВСЁ ВРЕМЯ: HEX %d · POLY %d · STR %d · SEQ %d" % [
		int(life.get("letters", 0)), int(life.get("shapes", 0)),
		int(life.get("stroop", 0)), int(life.get("master", 0)),
	], Color(0.6, 0.6, 0.6), 17)
	if OS.is_debug_build():
		add_line("  [F2] DEBUG FREE: %s — без байтов, в обход правил и гейтов" %
			("ВКЛ" if debug_free else "ВЫКЛ"),
			SEL_ON if debug_free else Color(0.6, 0.6, 0.6), 16)
	add_line("  [W/S] NAV   [ENTER] BUY   [MOUSE] CLICK   [ESC] BACK",
		Color(0.6, 0.6, 0.6), 16)

	_selected = clampi(prev_selected, 0, _options.size() - 1)
	_update_selection()


func _build_column(parent: Control, title: String, width: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	var rule := "+" + "-".repeat(width - 2) + "+"
	box.add_child(_col_label("  " + rule, COL_BG, 18))
	box.add_child(_col_label("  |" + (" " + title).rpad(width - 2, " ") + "|",
		Color(1.0, 0.9, 0.4), 18))
	box.add_child(_col_label("  " + rule, COL_BG, 18))
	box.add_child(_col_label("", Color.WHITE, 8))
	return box


func _add_card(box: VBoxContainer, card: Dictionary) -> void:
	_item_labels.append(_col_label("", Color.WHITE, 20))
	_status_labels.append(_col_label("", Color.WHITE, 17))
	box.add_child(_item_labels[_item_labels.size() - 1])
	box.add_child(_status_labels[_status_labels.size() - 1])
	box.add_child(_col_label("", Color.WHITE, 6))


func _col_label(text: String, color: Color, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _update_selection() -> void:
	for i in _options.size():
		var card: Dictionary = _options[i]
		var lbl: Label = _item_labels[i]
		var stat: Label = _status_labels[i]
		if not is_instance_valid(lbl) or not is_instance_valid(stat):
			continue
		var sel: bool = i == _selected
		var enabled: bool = card.get("enabled", false)
		lbl.text = ">> " + str(card["name"]) if sel else "   " + str(card["name"])
		if sel:
			var is_back: bool = str(card.get("value", "")) == "back"
			lbl.add_theme_color_override("font_color",
				SEL_ON if (enabled or is_back) else SEL_OFF)
		elif enabled:
			lbl.add_theme_color_override("font_color", Color.WHITE)
		else:
			lbl.add_theme_color_override("font_color", DIM)
		stat.text = "   " + str(card["status"])
		var price: int = int(card.get("price", -1))
		if card.get("owned", false):
			stat.add_theme_color_override("font_color", GOOD)
		elif price >= 0:
			stat.add_theme_color_override("font_color", GOOD if _bytes() >= price else LOW)
		else:
			stat.add_theme_color_override("font_color", DIM)


func _try_buy() -> void:
	var card: Dictionary = _options[_selected]
	var v: String = str(card.get("value", ""))
	if v == "back":
		_locked = true
		SFX.key()
		clear_instant()
		back_requested.emit()
		return
	if v == "" or not card.get("enabled", false):
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
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Экран — единственный потребитель: не даём ивенту долететь до игры.
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
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				_try_buy()
			KEY_F2:
				# Бесплатный дебаг-режим витрины (только debug-сборки,
				# гейт и на main-стороне в _on_debug_free_toggled).
				if OS.is_debug_build():
					debug_free_requested.emit()
			KEY_ESCAPE:
				_locked = true
				SFX.key()
				clear_instant()
				back_requested.emit()


# Оба лейбла карточки ведут на один индекс навигации.
func _nav_at(pos: Vector2) -> int:
	for i in _options.size():
		var lbl: Label = _item_labels[i]
		var stat: Label = _status_labels[i]
		if is_instance_valid(lbl) and lbl.get_global_rect().has_point(pos):
			return i
		if is_instance_valid(stat) and stat.get_global_rect().has_point(pos):
			return i
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
