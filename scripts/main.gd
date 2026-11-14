extends Control
# Оркестратор сцены Main: состояние приложения (State), ввод, коммутация
# модулей и тонкие фасады публичного контракта (Main.tscn и проб
# tools/probe_state.md обращаются именно сюда).
# Правила забега — SessionRules (витрина забега — SessionPresentation),
# CRT/FX-слои — FxDirector, экраны — ScreenRouter, HUD-ноды — HudBuilder,
# конфиг user:// — SettingsIO.
# Мета-прогрессия — MetaStore, музыка — MusicDeck. Попапы-подсказки из игры
# убраны (фидбек 2026-11-14): объявление — только белыми баннерами (HudBuilder).

enum State { BOOT, MENU, CONFIG, HELP, GAME, CUTSCENE, SHOP }
var current_state: int = State.BOOT

@onready var quadrants: Array = [
	$Margin/VBox/Grid/Quadrant0,
	$Margin/VBox/Grid/Quadrant1,
	$Margin/VBox/Grid/Quadrant2,
	$Margin/VBox/Grid/Quadrant3
]
@onready var garbage_timer: Timer = $GarbageTimer
@onready var countdown_timer: Timer = $CountdownTimer

# Мета-прогрессия: байты, купленные модули/механики, очки за всё время.
var _meta := MetaStore.new()      # байты/этапы/механики + правила покупок

# Музыка (intro->loop плееры, трек-лист, громкость).
var _music := MusicDeck.new()

# Дебаг-режим магазина (F2, только OS.is_debug_build()): покупки и снятие
# улучшений без байтов, мимо правил MetaStore. Снимается вместе с F3/F4.
var _debug_free: bool = false

# Модули-хелперы (RefCounted): состояние живёт у них, общение — прямые
# типизированные вызовы и сигналы.
var _settings := SettingsIO.new()
var _hud := HudBuilder.new()
var _fxd := FxDirector.new()
var _router := ScreenRouter.new()
var _session := SessionRules.new()
var _presenter := SessionPresentation.new()

var _terminal_font: Font = null
var _terminal_font_bold: Font = null

var _margin: Control

# Менеджер экранов.
var _screen_layer: CanvasLayer


# ---------- Состояние забега для live-проб (tools/probe_state.md) ----------
# Живёт в SessionRules; read-only прокси сохраняют контракт отладки /root/Main.
var active: bool:
	get:
		return _session.active


var paused: bool:
	get:
		return _session.paused


var combo: int:
	get:
		return _session.combo


var timer_value: float:
	get:
		return _session.timer_value


var current_item: Dictionary:
	get:
		return _session.current_item


var current_quadrant: int:
	get:
		return _session.current_quadrant


var waiting_for_garbage: bool:
	get:
		return _session.waiting_for_garbage


var _debug_run: bool:
	get:
		return _session.debug_run


func _ready() -> void:
	_settings.load_settings(_meta)
	_apply_terminal_theme()

	_hud.attach(self)
	_hud.terminal_font = _terminal_font
	_hud.create_bars(SessionRules.MAX_TIME, float(SessionRules.WIN_COMBO))

	_fxd.settings = _settings
	_fxd.setup_overlay(self)
	_fxd.fx.attach_master_bus()
	_music.attach(self)
	_hud.build_debug_menu(_on_debug_start_combo)
	_hud.build_pause_indicator()
	_hud.build_error_overlay()
	_hud.build_announce_overlay()
	_hud.build_meta_hud()
	_fxd.vu_label = _hud.vu_label
	_set_game_input_transparent()
	_margin = get_node_or_null("Margin")
	_fxd.margin = _margin
	_music.set_volume(_settings.music_volume)
	_apply_sfx_volume()
	_fxd.apply_crt_setting()

	# Применяем шрифт ко ВСЕМУ дереву (включая динамически созданные ноды).
	if _terminal_font:
		_apply_font_recursive(self, _terminal_font)

	var margin: Node = _margin
	if margin is MarginContainer:
		margin.add_theme_constant_override("margin_top", 80)
		margin.add_theme_constant_override("margin_bottom", 40)

	_set_game_visible(false)

	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "ScreenLayer"
	_screen_layer.layer = 50
	add_child(_screen_layer)
	_router.build(_screen_layer, _terminal_font)
	_router.main_menu_requested.connect(_show_main_menu)
	_router.menu_action.connect(_on_menu_action)
	_router.restart_requested.connect(_on_lose_restart)
	_router.shop_requested.connect(_on_lose_shop)
	_router.bindings_changed.connect(_on_bindings_changed)
	_router.settings_changed.connect(_on_settings_changed)
	_router.debug_free_requested.connect(_on_debug_free_toggled)

	# Забег: зависимости + обработка завершения (катсцены) и сохранения.
	# Витрина забега (квадранты/HUD/баннеры) — у SessionPresentation, сессия
	# решает, что показать, презентатор знает как.
	_presenter.hud = _hud
	_presenter.quadrants = quadrants
	_presenter.fx_director = _fxd
	_session.presenter = _presenter
	_session.host = self
	_session.settings = _settings
	_session.meta = _meta
	_session.music = _music
	_session.countdown_timer = countdown_timer
	_session.garbage_timer = garbage_timer
	_session.save_requested.connect(_save_settings)
	_session.run_finished.connect(_on_run_finished)

	update_timer_display()
	update_combo_display()

	_show_boot_screen()


func _process(delta: float) -> void:
	_fxd.process(delta, current_state == State.GAME, _session.combo, _session.mode, quadrants)


func _apply_sfx_volume() -> void:
	# ВАЖНО: только применение громкости. Ранее сюда ошибочно попал хвост
	# _ready(), из-за чего любое изменение настроек перезапускало boot-экран.
	SFX.set_volume(_settings.sfx_volume)


# ---------- Обработчики сцены (коннекты в Main.tscn) ----------
func _on_countdown_tick() -> void:
	_session.tick_countdown()


func _on_garbage_timeout() -> void:
	_session.tick_garbage()


# ---------- Публичный контракт забега (фасады в SessionRules) ----------
# F4 — дебаг-пауза: гейта `if paused: return` здесь НЕТ намеренно
# (решение владельца 2026-11-14) — засчитывание ответов на паузе нужно для
# ручного тестирования. Фича removal при релизе, вместе с debug-меню F3.
func handle_answer(button: int) -> void:
	_session.handle_answer(button)


func start_game(initial_combo: int = -1, debug: bool = false) -> void:
	_session.start_game(initial_combo, debug)


func end_game(reason: String) -> void:
	_session.end_game(reason)


func update_timer_display() -> void:
	_session.update_timer_display()


func update_combo_display() -> void:
	_session.update_combo_display()


# ---------- Ввод ----------
func _unhandled_input(event: InputEvent) -> void:
	if current_state != State.GAME:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			# Debug-меню — только в отладочных сборках.
			if OS.is_debug_build():
				SFX.key()
				_toggle_debug_menu()
			return
		if event.keycode == KEY_F4:
			SFX.key()
			_session.toggle_pause()
			return
		if event.keycode == KEY_ESCAPE:
			SFX.key()
			_abort_game()
			return
		if _hud.debug_menu and _hud.debug_menu.visible:
			return

	# Здесь всегда active == true: end_game() мгновенно переводит current_state
	# в CUTSCENE, а рестарт обрабатывает сам cutscene — мёртвая ветка убрана.

	if _event_matches(event, _settings.binding_answer1):
		handle_answer(1)
		get_viewport().set_input_as_handled()
		return
	if _event_matches(event, _settings.binding_answer2):
		handle_answer(2)
		get_viewport().set_input_as_handled()
		return


func _event_matches(event: InputEvent, binding: InputEvent) -> bool:
	if binding == null:
		return false
	if binding is InputEventKey and event is InputEventKey:
		return event.pressed and not event.echo and event.keycode == binding.keycode
	if binding is InputEventMouseButton and event is InputEventMouseButton:
		return event.pressed and event.button_index == binding.button_index
	return false


func _toggle_debug_menu() -> void:
	if _hud.debug_menu == null:
		return
	_hud.debug_menu.visible = not _hud.debug_menu.visible


func _on_debug_start_combo(c: int) -> void:
	# Debug-функция доступна только в отладочных сборках (см. KEY_F3 в _unhandled_input).
	if not OS.is_debug_build():
		return
	SFX.key()
	if _hud.debug_menu:
		_hud.debug_menu.visible = false
	start_game(c, true)


func _abort_game() -> void:
	if not _session.active:
		return
	# Дальше всё делает end_game — он остановит таймеры, очистит поле
	# и покажет lose_cutscene с причиной "aborted".
	end_game("aborted")


# ---------- Экраны: оркестрация состояний поверх ScreenRouter ----------
func _set_game_visible(v: bool) -> void:
	if _margin:
		_margin.visible = v
	_hud.set_game_nodes_visible(v, _settings.music_fx_enabled)
	if not v:
		# F3-меню живёт только в геймплее: при любом выходе из него
		# (проигрыш, катсцена, меню) убираем — фидбек 2026-11-14: меню
		# переживало поражение и висело даже над главным меню.
		if _hud.debug_menu:
			_hud.debug_menu.visible = false
	elif _hud.debug_menu and _hud.debug_menu.visible:
		# F3-меню модально блокирует клавиши-ответы (гейт в _unhandled_input);
		# при новом забеге оно обязано быть закрыто — иначе ESC-прерывание с
		# открытым меню оставляло следующий забег «глухим» к клавишам 1/2.
		_hud.debug_menu.visible = false


func _show_boot_screen() -> void:
	current_state = State.BOOT
	_router.show_boot()


func _show_main_menu() -> void:
	current_state = State.MENU
	_music.play("menu")
	_set_game_visible(false)
	_router.show_main_menu()


func _on_menu_action(action: String) -> void:
	match action:
		"start":          _start_game_from_menu()
		"configuration":  _show_config_menu()
		"system update":  _show_system_update()
		"help":           _show_help_screen()
		"exit":           _quit_with_sound()


func _quit_with_sound() -> void:
	_router.clear_screen()
	SFX.shutdown()
	# Слышен только «щелчок» выключения: полный хвост ShutDown.ogg ждать
	# незачем (фидбек: игра закрывалась несколько секунд). Ставим крест на
	# аудио и выходим через 0.6 c.
	var wait: float = minf(SFX.shutdown_length(), 0.6)
	if wait <= 0.0:
		wait = 0.4
	await get_tree().create_timer(wait).timeout
	_stop_all_audio()
	get_tree().quit()


func _stop_all_audio() -> void:
	SFX.stop_all()
	_music.stop_all()


func _notification(what: int) -> void:
	# Крестик окна / Alt+F4: гасим звук до выхода, иначе закрытие висит,
	# пока аудио-драйвер досылает буферы (гул БП играл в цикле).
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_all_audio()
		get_tree().quit()


func _exit_tree() -> void:
	# Страховка от утечек аудио при выходе мимо NOTIFICATION_WM_CLOSE_REQUEST
	# (get_tree().quit() из пробника/катсцены-экрана). SFX — autoload-ребёнок
	# root, при остановке движка он мог быть удалён раньше этой сцены, поэтому
	# за ним смотрим через get_node_or_null: у себя в _exit_tree он гасит всё
	# сам, здесь важен музыкальный дек MusicDeck (он живёт вместе с main).
	if get_node_or_null("/root/SFX") != null:
		SFX.stop_all()
	_music.stop_all()


func _start_game_from_menu() -> void:
	current_state = State.GAME
	_router.clear_screen()
	_set_game_visible(true)
	# Старт с учётом купленного «пропуска этапа»; не наследует debug_start_combo.
	start_game(_meta.skip_start_combo())


func _show_config_menu() -> void:
	current_state = State.CONFIG
	_router.show_config(_settings)


func _on_settings_changed(volume: float, sfx_vol: float, crt: bool,
		music_fx: bool, reactivity: float) -> void:
	_settings.music_volume = clampf(volume, 0.0, 1.0)
	_settings.sfx_volume = clampf(sfx_vol, 0.0, 1.0)
	_settings.fx_reactivity = clampf(reactivity, 0.0, 1.0)
	_settings.crt_enabled = crt
	_settings.music_fx_enabled = music_fx
	_music.set_volume(_settings.music_volume)
	_apply_sfx_volume()
	_fxd.apply_crt_setting()
	_fxd.apply_music_fx_setting(quadrants)
	_save_settings()


func _on_bindings_changed(e1: InputEvent, e2: InputEvent) -> void:
	_settings.binding_answer1 = e1
	_settings.binding_answer2 = e2
	_save_settings()


func _show_help_screen() -> void:
	current_state = State.HELP
	_router.show_help(_settings)


# ---------- Магазин SYSTEM UPDATE ----------
func _show_system_update() -> void:
	current_state = State.SHOP
	_router.show_system_update(_meta.snapshot(), _meta_buy, _debug_free)


func _on_debug_free_toggled() -> void:
	# Дебаг-функция магазина (F2): только отладочные сборки, вместе с F3/F4
	#-remove при релизе. Пересоздаём экран — витрина перестроится с флагом.
	if not OS.is_debug_build():
		return
	_debug_free = not _debug_free
	SFX.key()
	_show_system_update()


func _meta_buy(item: String) -> bool:
	# Правила покупки — в MetaStore; здесь звук, сохранение и обновление витрины.
	# В дебаг-«бесплатном» режиме — перевыбор уровня/снятие без байтов и гейтов.
	var free_dbg: bool = _debug_free and OS.is_debug_build()
	var ok := _meta.debug_toggle(item) if free_dbg else _meta.try_buy(item)
	if ok:
		_save_settings()
		SFX.key()
	else:
		SFX.error()
	# Обновляем витрину свежим снапшотом (покупка/отказ).
	var screen: TerminalScreen = _router.current_screen()
	if screen and is_instance_valid(screen) and screen.has_method("apply_meta"):
		screen.apply_meta(_meta.snapshot())
	return ok


# ---------- Катсцены (показывает ScreenRouter, данные — из забега) ----------
func _on_run_finished(reason: String, stage_index: int, progress_pct: int) -> void:
	if reason == "win":
		_show_end_cutscene()
	elif reason == "stage_complete":
		_show_shift_complete(stage_index, progress_pct)
	else:
		_show_lose_cutscene(reason, stage_index, progress_pct)


func _show_end_cutscene() -> void:
	_music.play("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	_router.show_end_cutscene(_session.run_bytes)


func _show_lose_cutscene(reason: String, failed_stage: int, progress_pct: int) -> void:
	_music.play("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	_router.show_lose_cutscene(reason, failed_stage, progress_pct, _session.run_bytes, _meta.balance())


func _on_lose_shop() -> void:
	# Магазин прямо с экрана поражения: байты забега уже зачислены в
	# end_game(), так что баланс на витрине актуален. «Назад» -> main menu.
	_show_system_update()


func _show_shift_complete(completed_stages: int, progress_pct: int) -> void:
	_music.play("outro")
	current_state = State.CUTSCENE
	_set_game_visible(false)
	_router.show_shift_complete(completed_stages, progress_pct, _session.run_bytes)


func _on_lose_restart() -> void:
	current_state = State.GAME
	_router.clear_screen()
	_set_game_visible(true)
	# Рестарт с учётом купленного «пропуска этапа» (ур.0 -> с нуля).
	start_game(_meta.skip_start_combo())


# ---------- Сохранение конфигурации ----------
func _save_settings() -> void:
	_settings.save_settings(_meta)


# ---------- Оформление ----------
func _apply_terminal_theme() -> void:
	var font: Font = null
	var font_bold: Font = null
	var font_path := "res://fonts/HomeVideo-Regular.otf"
	var font_bold_path := "res://fonts/HomeVideo-Bold.otf"

	if ResourceLoader.exists(font_path):
		font = load(font_path)
	if ResourceLoader.exists(font_bold_path):
		font_bold = load(font_bold_path)

	if font == null:
		push_warning("HomeVideo-Regular не найден, использую системный моноширинный.")
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Courier New", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		font = mono
	if font_bold == null:
		font_bold = font

	_terminal_font = font
	_terminal_font_bold = font_bold

	for q in quadrants:
		q.set_fonts(font, font_bold)


# Рекурсивно ставим IGNORE на игровое поддерево, чтобы клики доходили до _unhandled_input.
func _set_game_input_transparent() -> void:
	# Корневой Control тоже должен пропускать мышь, иначе он перехватит
	# все клики раньше, чем они дойдут до _unhandled_input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := get_node_or_null("Background")
	if bg:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := get_node_or_null("Margin")
	if margin:
		_make_subtree_ignore_mouse(margin)


func _make_subtree_ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_make_subtree_ignore_mouse(c)


func _apply_font_recursive(node: Node, font: Font) -> void:
	if node is Control:
		node.add_theme_font_override("font", font)
	for child in node.get_children():
		_apply_font_recursive(child, font)
