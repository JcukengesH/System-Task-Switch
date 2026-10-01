import io, sys

TAB = "\t"
src = io.open("scripts/main.gd", encoding="utf-8").read()

def rep(old, new):
    global src
    assert old in src, "NOT FOUND: " + old[:60]
    src = src.replace(old, new, 1)

# 1. Вызовы _adaptive_norm -> state-словари
rep(
"\tvar bass_n: float   = _adaptive_norm(bass_db, _bass_hist, _bass_min, _bass_max)\n"
"\tvar mid_n: float    = _adaptive_norm(mid_db, _mid_hist, _mid_min, _mid_max)\n"
"\tvar treble_n: float = _adaptive_norm(treble_db, _treble_hist, _treble_min, _treble_max)",
"\tvar bass_n: float   = _adaptive_norm(bass_db, _bass_hist, _bass_state)\n"
"\tvar mid_n: float    = _adaptive_norm(mid_db, _mid_hist, _mid_state)\n"
"\tvar treble_n: float = _adaptive_norm(treble_db, _treble_hist, _treble_state)")

# 2. Debug-меню только в отладочных сборках
rep(
"func _on_debug_start_combo(c: int) -> void:\n"
"\tSFX.key()",
"func _on_debug_start_combo(c: int) -> void:\n"
"\t# Debug-функция доступна только в отладочных сборках (см. KEY_F3 в _unhandled_input).\n"
"\tif not OS.is_debug_build():\n"
"\t\treturn\n"
"\tSFX.key()")

# 3. START из меню — явно с нуля (не наследует debug_start_combo)
rep(
"\t_set_game_visible(true)\n"
"\tstart_game()\n"
"\n"
"\n"
"func _show_config_menu",
"\t_set_game_visible(true)\n"
"\t# Явно с нуля: иначе «START» из меню унаследует debug_start_combo после F3.\n"
"\tstart_game(0)\n"
"\n"
"\n"
"func _show_config_menu")

# 4. Рестарт после поражения — тоже с нуля
rep(
"func _on_lose_restart() -> void:\n"
"\tcurrent_state = State.GAME\n"
"\tif _current_screen and is_instance_valid(_current_screen):\n"
"\t\t_current_screen.queue_free()\n"
"\t\t_current_screen = null\n"
"\t_set_game_visible(true)\n"
"\tstart_game()",
"func _on_lose_restart() -> void:\n"
"\tcurrent_state = State.GAME\n"
"\tif _current_screen and is_instance_valid(_current_screen):\n"
"\t\t_current_screen.queue_free()\n"
"\t\t_current_screen = null\n"
"\t_set_game_visible(true)\n"
"\tstart_game(0)")

# 5. F3 — только debug-сборка
rep(
"\t\tif event.keycode == KEY_F3:\n"
"\t\t\tSFX.key()\n"
"\t\t\t_toggle_debug_menu()\n"
"\t\t\treturn",
"\t\tif event.keycode == KEY_F3:\n"
"\t\t\t# Debug-меню — только в отладочных сборках.\n"
"\t\t\tif OS.is_debug_build():\n"
"\t\t\t\tSFX.key()\n"
"\t\t\t\t_toggle_debug_menu()\n"
"\t\t\treturn")

# 6. Мёртвая ветка if not active в _unhandled_input
rep(
"\t\tif debug_menu and debug_menu.visible:\n"
"\t\t\treturn\n"
"\n"
"\tif not active:\n"
"\t\tif event is InputEventKey and event.pressed and not event.echo:\n"
"\t\t\tif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:\n"
"\t\t\t\tSFX.key()\n"
"\t\t\t\tstart_game()\n"
"\t\treturn\n"
"\n"
"\tif _event_matches(event, binding_answer1):",
"\t\tif debug_menu and debug_menu.visible:\n"
"\t\t\treturn\n"
"\n"
"\t# Здесь всегда active == true: end_game() мгновенно переводит current_state\n"
"\t# в CUTSCENE, а рестарт обрабатывает сам cutscene — мёртвая ветка убрана.\n"
"\n"
"\tif _event_matches(event, binding_answer1):")

# 7. _read_binding: fallback, если секции input нет
rep(
"func _read_binding(cfg: ConfigFile, key: String, fallback: InputEvent) -> InputEvent:\n"
"\tvar t: String = cfg.get_value(\"input\", key + \"_type\", \"key\")\n"
"\tvar v: int = cfg.get_value(\"input\", key + \"_value\", 0)",
"func _read_binding(cfg: ConfigFile, key: String, fallback: InputEvent) -> InputEvent:\n"
"\t# Если секции input в конфиге нет, берём значение из fallback,\n"
"\t# иначе keycode/button_index станет 0 и биндинг сломается.\n"
"\tvar t: String = cfg.get_value(\"input\", key + \"_type\", \"\")\n"
"\tvar v: Variant = cfg.get_value(\"input\", key + \"_value\", null)\n"
"\tif v == null:\n"
"\t\treturn fallback")

# 8. Кэш set_shader_parameter
rep(
"var _beat_punch: float = 0.0\n"
"var _pulse_sent: float = -1.0",
"var _beat_punch: float = 0.0\n"
"var _pulse_sent: float = -1.0\n"
"# Кэш последних отправленных в шейдер значений: не дёргать\n"
"# set_shader_parameter каждый кадр одинаковыми числами.\n"
"var _shader_cache: Dictionary = {}")

rep(
"\t_crt_material.set_shader_parameter(\"music_bass\",   bass_trans)\n"
"\t_crt_material.set_shader_parameter(\"music_mid\",    mid_trans)\n"
"\t_crt_material.set_shader_parameter(\"music_treble\", treble_trans)\n"
"\t_crt_material.set_shader_parameter(\"music_pulse\",  _beat_punch)",
"\t_set_shader_param_cached(\"music_bass\",   bass_trans)\n"
"\t_set_shader_param_cached(\"music_mid\",    mid_trans)\n"
"\t_set_shader_param_cached(\"music_treble\", treble_trans)\n"
"\t_set_shader_param_cached(\"music_pulse\",  _beat_punch)")

rep(
"func _env(current: float, target: float, delta: float, rate: float) -> float:",
"func _set_shader_param_cached(pname: String, value: float) -> void:\n"
"\tvar rounded: float = roundf(value * 1000.0) / 1000.0\n"
"\tif _shader_cache.get(pname) == rounded:\n"
"\t\treturn\n"
"\t_shader_cache[pname] = rounded\n"
"\t_crt_material.set_shader_parameter(pname, rounded)\n"
"\n"
"\n"
"func _env(current: float, target: float, delta: float, rate: float) -> float:")

# 9. added100/200/300 -> словарь STAGE_BONUSES + множество выданных бонусов
rep(
"const MOD_THRESHOLDS := {",
"# Бонус времени за переход на новый этап (порог комбо, один раз на этап).\n"
"const STAGE_BONUSES := {\"shapes\": 100, \"stroop\": 200, \"master\": 300}\n"
"\n"
"const MOD_THRESHOLDS := {")

rep(
"\t\t# Бонус времени за переход на новый этап (один раз на этап).\n"
"\t\tvar bonus_threshold := 0\n"
"\t\tmatch new_mode:\n"
"\t\t\t\"shapes\": bonus_threshold = 100\n"
"\t\t\t\"stroop\": bonus_threshold = 200\n"
"\t\t\t\"master\": bonus_threshold = 300\n"
"\t\tif bonus_threshold > 0 and combo >= bonus_threshold:\n"
"\t\t\tmatch bonus_threshold:\n"
"\t\t\t\t100:\n"
"\t\t\t\t\tif not added100:\n"
"\t\t\t\t\t\tadded100 = true\n"
"\t\t\t\t\t\ttimer_value += STAGE_TIME_BONUS\n"
"\t\t\t\t200:\n"
"\t\t\t\t\tif not added200:\n"
"\t\t\t\t\t\tadded200 = true\n"
"\t\t\t\t\t\ttimer_value += STAGE_TIME_BONUS\n"
"\t\t\t\t300:\n"
"\t\t\t\t\tif not added300:\n"
"\t\t\t\t\t\tadded300 = true\n"
"\t\t\t\t\t\ttimer_value += STAGE_TIME_BONUS\n"
"\t\t\tupdate_timer_display()",
"\t\t# Бонус времени за переход на новый этап (один раз на этап).\n"
"\t\tvar threshold: int = STAGE_BONUSES.get(new_mode, 0)\n"
"\t\tif threshold > 0 and combo >= threshold and not _stage_bonus_given.has(threshold):\n"
"\t\t\t_stage_bonus_given[threshold] = true\n"
"\t\t\ttimer_value += STAGE_TIME_BONUS\n"
"\t\t\tupdate_timer_display()")

# Переменные added100/200/300 -> одно множество
rep(
"var added100 := false\nvar added200 := false\nvar added300 := false",
"# Пороги бонусов времени, уже выданных в текущей партии.\nvar _stage_bonus_given: Dictionary = {}")

rep(
"\t\tadded100 = initial_combo >= 100\n"
"\t\tadded200 = initial_combo >= 200\n"
"\t\tadded300 = initial_combo >= 300",
"\t\t_stage_bonus_given = {}\n"
"\tfor t in STAGE_BONUSES.values():\n"
"\t\tif initial_combo >= t:\n"
"\t\t\t_stage_bonus_given[t] = true")

io.open("scripts/main.gd", "w", encoding="utf-8", newline="\n").write(src)
print("main.gd OK")
