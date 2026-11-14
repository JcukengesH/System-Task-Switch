class_name DebugMenuUi
extends RefCounted
# Витрина F3 debug-меню «START COMBO»: сетка колонок по этапам × смещениям
# базового комбо. Отделена от HudBuilder по двум причинам: сам HUD остаёт
# единой точкой сборки игровых нод, а debug-контур перед релизом вычищается
# удалением ЭТОГО файла и одного вызова (docs/ARCHITECTURE.md, «Долги» п.6).
# Базы комбо — из Meta.STAGE_START_COMBO (единый источник, §10.4); короткие
# имена колонок — только витрина debug-меню (не баланс).


# Строит панель, вешает её на host и возвращает (HudBuilder keeps ссылку
# в debug_menu и крутит только видимость).
static func build(host: Node, on_pick: Callable) -> PanelContainer:
	var debug_menu := PanelContainer.new()
	debug_menu.name = "DebugMenu"
	debug_menu.visible = false
	debug_menu.set_anchors_preset(Control.PRESET_CENTER)
	debug_menu.offset_left = -270
	debug_menu.offset_right = 270
	debug_menu.offset_top = -150
	debug_menu.offset_bottom = 150

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color.WHITE
	style.set_border_width_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	debug_menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	debug_menu.add_child(vbox)

	var title := Label.new()
	title.text = "F3: START COMBO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "обходит гейт этапов · байты/очки не начисляются"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(sub)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	vbox.add_child(columns)

	var names := ["HEX", "POLY", "STROOP", "MASTER"]
	var stages: Array = []
	for i in Meta.STAGE_START_COMBO.size():
		stages.append({
			"name": names[i] if i < names.size() else str(i),
			"base": int(Meta.STAGE_START_COMBO[i]),
		})

	for stage in stages:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		columns.add_child(col)

		var header := Label.new()
		header.text = stage["name"]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 14)
		header.modulate = Color(0.7, 0.7, 0.7)
		col.add_child(header)

		var base: int = stage["base"]
		for offset in [0, 20, 40, 60, 80]:
			var value: int = base + offset
			var btn := Button.new()
			btn.text = str(value)
			btn.custom_minimum_size = Vector2(70, 28)
			_style_button(btn)
			btn.pressed.connect(on_pick.bind(value))
			col.add_child(btn)

	host.add_child(debug_menu)
	return debug_menu


static func _style_button(btn: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 1)
	box.border_color = Color(1, 1, 1, 1)
	box.set_border_width_all(2)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6

	var box_hover: StyleBoxFlat = box.duplicate()
	box_hover.bg_color = Color(1, 1, 1, 1)

	btn.add_theme_stylebox_override("normal", box)
	btn.add_theme_stylebox_override("hover", box_hover)
	btn.add_theme_stylebox_override("pressed", box_hover)
	btn.add_theme_stylebox_override("focus", box)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.BLACK)
	btn.add_theme_color_override("font_pressed_color", Color.BLACK)
