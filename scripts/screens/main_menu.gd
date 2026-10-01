extends TerminalScreen

signal menu_action(action: String)

const ITEMS := ["START", "CONFIGURATION", "HELP", "EXIT"]

var _selected: int = 0
var _item_labels: Array = []
var _locked: bool = false


func _ready() -> void:
	super._ready()
	_show_menu()


func _show_menu() -> void:
	clear_all()
	add_line("", Color.WHITE, 22)
	add_line("  +======================================+", Color.WHITE, 22)
	add_line("  |     TERMINAL PROTOCOL  v1.0          |", Color.WHITE, 22)
	add_line("  |          > MAIN MENU <               |", Color.WHITE, 22)
	add_line("  +======================================+", Color.WHITE, 22)
	add_line("", Color.WHITE, 20)

	_item_labels.clear()
	for i in ITEMS.size():
		var lbl := add_line("", Color.WHITE, 24)
		_item_labels.append(lbl)

	add_line("", Color.WHITE, 20)
	add_line("  [W/S] NAVIGATE   [ENTER] SELECT   [MOUSE] CLICK   [ESC] QUIT",
		Color(0.6, 0.6, 0.6), 16)
	_update_selection()


func _update_selection() -> void:
	for i in _item_labels.size():
		var prefix := "  >> " if i == _selected else "     "
		_item_labels[i].text = prefix + ITEMS[i]
		_item_labels[i].add_theme_color_override("font_color",
			Color.WHITE if i == _selected else Color(0.7, 0.7, 0.7))


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
				_selected = (_selected - 1 + ITEMS.size()) % ITEMS.size()
				_update_selection()
				SFX.key()
			KEY_S, KEY_DOWN:
				_selected = (_selected + 1) % ITEMS.size()
				_update_selection()
				SFX.key()
			KEY_1, KEY_2, KEY_3, KEY_4:
				var idx: int = event.keycode - KEY_1
				if idx >= 0 and idx < ITEMS.size():
					_selected = idx
					_update_selection()
					SFX.key()
					_confirm()
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				SFX.key()
				_confirm()
			KEY_ESCAPE:
				SFX.key()
				_locked = true
				await clear_animated(0.03)
				menu_action.emit("exit")


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
		if lbl.get_global_rect().has_point(pos):
			_selected = i
			_update_selection()
			SFX.key()
			_confirm()
			return


func _confirm() -> void:
	_locked = true
	var action: String = String(ITEMS[_selected]).to_lower()
	await clear_animated(0.04)
	menu_action.emit(action)
