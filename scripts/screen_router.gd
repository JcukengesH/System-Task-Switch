class_name ScreenRouter
extends RefCounted
# Менеджер экранов: boot, главное меню, конфигурация, help, магазин, катсцены.
# Владеет ScreenLayer, текущим экраном и его коммутацией: создаёт экран,
# вешает шрифт, подключает сигналы экрана к своим. Переключение current_state,
# музыка и запуск забега — ответственность main.gd (слушает сигналы ниже).
#
# Экраны поднимаются load(), а не preload(): preload тянет компиляцию самих
# экранов, а они ссылаются на autoload SFX — в --check-only (без autoload)
# это давало бы ложный "Failed to compile depended scripts". Поведение в
# рантайме идентично: экраны и раньше создавались .new() по показу.

signal main_menu_requested()
signal menu_action(action: String)
signal restart_requested()
signal shop_requested()
signal bindings_changed(answer1: InputEvent, answer2: InputEvent)
signal settings_changed(volume: float, sfx_volume: float, crt: bool,
		music_fx: bool, reactivity: float)
signal debug_free_requested()

var _layer: CanvasLayer
var _font: Font
var _current_screen: TerminalScreen


func build(layer: CanvasLayer, font: Font) -> void:
	_layer = layer
	_font = font


func transition_to(screen: TerminalScreen) -> void:
	if _current_screen and is_instance_valid(_current_screen):
		_current_screen.queue_free()
	_current_screen = screen
	screen.set_terminal_font(_font)
	_layer.add_child(screen)


# Текущий экран или null (магазин обновляет витрину через has_method("apply_meta")).
func current_screen() -> TerminalScreen:
	return _current_screen


# Снять экран (перед прямым входом в игру из signal-обработчика).
func clear_screen() -> void:
	if _current_screen and is_instance_valid(_current_screen):
		_current_screen.queue_free()
		_current_screen = null


func show_boot() -> void:
	# Тип — Variant: load() не даёт анализатору класса экрана (preload ложно
	# валил --check-only, см. заголовок файла).
	var boot: Variant = load("res://scripts/screens/boot_screen.gd").new()
	boot.boot_finished.connect(main_menu_requested.emit)
	transition_to(boot)


func show_main_menu() -> void:
	var m: Variant = load("res://scripts/screens/main_menu.gd").new()
	m.menu_action.connect(menu_action.emit)
	transition_to(m)


func show_config(settings: SettingsIO) -> void:
	var m: Variant = load("res://scripts/screens/config_menu.gd").new()
	m.set_bindings(settings.binding_answer1, settings.binding_answer2)
	m.set_settings(settings.music_volume, settings.sfx_volume, settings.crt_enabled, settings.music_fx_enabled, settings.fx_reactivity)
	m.back_requested.connect(main_menu_requested.emit)
	m.bindings_changed.connect(bindings_changed.emit)
	m.settings_changed.connect(settings_changed.emit)
	transition_to(m)


func show_help(settings: SettingsIO) -> void:
	var m: Variant = load("res://scripts/screens/help_screen.gd").new()
	m.set_bindings(settings.binding_answer1, settings.binding_answer2)
	m.back_requested.connect(main_menu_requested.emit)
	transition_to(m)


func show_system_update(snapshot: Dictionary, buy_handler: Callable,
		debug_free: bool = false) -> void:
	var m: Variant = load("res://scripts/screens/system_update.gd").new()
	m.buy_handler = buy_handler
	m.debug_free = debug_free
	m.back_requested.connect(main_menu_requested.emit)
	m.debug_free_requested.connect(debug_free_requested.emit)
	# apply_meta до add_child: _ready() построит витрину уже с данными.
	m.apply_meta(snapshot)
	transition_to(m)


func show_end_cutscene(bytes_earned: int) -> void:
	var m: Variant = load("res://scripts/screens/end_cutscene.gd").new()
	m.bytes_earned = bytes_earned
	m.cutscene_finished.connect(main_menu_requested.emit)
	transition_to(m)


func show_lose_cutscene(reason: String, failed_stage: int, progress_pct: int,
		bytes_earned: int, bytes_balance: int) -> void:
	var m: Variant = load("res://scripts/screens/lose_cutscene.gd").new()
	m.reason = reason
	m.failed_stage = failed_stage
	m.progress_pct = progress_pct
	m.bytes_earned = bytes_earned
	m.bytes_balance = bytes_balance
	m.restart_requested.connect(restart_requested.emit)
	m.menu_requested.connect(main_menu_requested.emit)
	m.shop_requested.connect(shop_requested.emit)
	transition_to(m)


func show_shift_complete(completed_stages: int, progress_pct: int, bytes_earned: int) -> void:
	var m: Variant = load("res://scripts/screens/shift_complete.gd").new()
	m.completed_stages = completed_stages
	m.progress_pct = progress_pct
	m.bytes_earned = bytes_earned
	m.restart_requested.connect(restart_requested.emit)
	m.menu_requested.connect(main_menu_requested.emit)
	transition_to(m)
