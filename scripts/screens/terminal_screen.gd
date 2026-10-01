class_name TerminalScreen
extends Control

const STAGE_NAMES := [
	"HEX-CYPHER",
	"POLYMETRY",
	"STROOPTEST",
	"MASTERBOOT",
]
var _vbox: VBoxContainer
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_vbox)


func set_terminal_font(font: Font) -> void:
	_font = font


func add_line(text: String, color: Color = Color.WHITE, font_size: int = 20) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	if _font:
		lbl.add_theme_font_override("font", _font)
	_vbox.add_child(lbl)
	return lbl


func clear_all() -> void:
	for c in _vbox.get_children():
		c.queue_free()


func type_lines(lines: Array, delay: float = 0.12) -> void:
	for line in lines:
		if not is_inside_tree():
			return
		var text: String
		var color: Color = Color.WHITE
		var fs: int = 20
		if typeof(line) == TYPE_DICTIONARY:
			text = str(line.get("text", ""))
			color = line.get("color", Color.WHITE)
			fs = line.get("size", 20)
		else:
			text = str(line)
		add_line(text, color, fs)
		await get_tree().create_timer(delay).timeout


func clear_animated(delay: float = 0.04) -> void:
	var kids := _vbox.get_children()
	for c in kids:
		if not is_inside_tree():
			return
		if is_instance_valid(c):
			c.queue_free()
		await get_tree().create_timer(delay).timeout
