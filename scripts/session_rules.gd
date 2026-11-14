class_name SessionRules
extends RefCounted
# Правила одного забега: таймер, комбо, ошибки, этапы/модификаторы, экономика
# байтов. Нод не строит и экранами не рулит: зависимости (конфигурация,
# мета-хранилище, музыка) получает ссылками, сохранение конфига и показ
# катсцены запрашивает сигналами. Вся витрина (квадранты, индикаторы HUD,
# баннеры, фидбек ответа) — у SessionPresentation: здесь только решение,
# ЧТО показать, презентатор знает, КАК. Публичный контракт (handle_answer /
# start_game / end_game и обработчики сценных таймеров) остаётся фасадом в
# main.gd — сюда заходят только через него.

const START_TIME := 15
const MAX_TIME := 30.0          # верхний предел таймера (бар показывает честно)
const BONUS_PER_CORRECT := 1.0
const WIN_COMBO := 400
const GARBAGE_TIMEOUT := 0.75

const QUADRANT_ORDER := [0, 1, 3, 2]

# Этапы, играющие на одном поле вместо сетки 2×2: у фигур и Струпа привязка
# к углу ничего не значит, а у буквы (HEX-CYPHER и перемешка в THE SEQUENCE)
# ответ зависит от «верх/низ», поэтому им сетка обязана.
const FULL_FIELD_MODES := ["shapes", "stroop"]

const ANSWER_FEEDBACK_DELAY := 0.10
# Окно молчания после старта забега: клик-рестарт (или его второй такт
# двойного клика) не должен превращаться в ответ на первом символе.
const START_INPUT_GRACE := 0.35
# Откат урона 2-го уровня: столько комбо срезает ошибка. Синхронно с
# Meta.ROLLBACK_DESC[2] «ОТКАТ -20 ОЧКОВ» (числовой константы в Meta нет).
const ROLLBACK_POINTS := 20

# Шанс показать задание в случайном квадранте вместо циклического порядка.
const RANDOM_QUAD_CHANCE := 0.3

# Забег завершён: main.gd показывает катсцену (win/stage_complete/прочие).
signal run_finished(reason: String, stage_index: int, progress_pct: int)
# Конфиг с обновлённым балансом байтов нужно сохранить на диск.
signal save_requested()

# ---------- Зависимости (заполняет main.gd) ----------
var host: Node                 # владелец дерева: get_tree() для пауз/грейса
var settings: SettingsIO       # настройки ввода/звука забега
var meta: MetaStore            # байты/этапы/механики + правила покупок
var music: MusicDeck           # треки этапов
var presenter: SessionPresentation  # витрина забега: квадранты/HUD/баннеры
var countdown_timer: Timer
var garbage_timer: Timer

# Генератор заданий (режимы, модификаторы, антиповтор Струпа — внутри него).
var _gen := TaskGen.new()

# ---------- Состояние забега ----------
var active := false
var paused: bool = false
var timer_value: float = float(START_TIME)
var combo := 0
var max_combo := 0
var current_item: Dictionary = {}
var current_quadrant := -1
var order_index := 0
var waiting_for_garbage := false
# Пороги бонусов времени, уже выданных в текущей партии.
var _stage_bonus_given: Dictionary = {}
var mode := "letters"
var errors_in_stage: int = 0
var debug_start_combo: int = 0
var run_bytes: int = 0        # заработано в текущем забеге
var debug_run: bool = false   # F3-старт: обходит гейт «этап не куплен»
# Геометрия поля текущего этапа (StageLayout.Field) и флаг идущей
# перестройки: на морфинге блокируются ответы и пауза, таймер стоит.
var _field: int = StageLayout.Field.GRID
var _field_frozen: bool = false
# Поколение забега: корутина морфинга, дождавшаяся в чужом забеге, обязана
# отвалиться, а не перекраивать поле/гейты нового (вход через F3-меню).
var _run_seq := 0
var _answer_locked: bool = false

# Бонус времени за переход на новый этап (порог комбо, один раз на этап).
# Значения — начала этапов из Meta.STAGE_START_COMBO (§10.4), строятся при
# конструировании, а не литералом.
var _stage_bonuses: Dictionary = {}


func _init() -> void:
	for i in Meta.STAGE_ORDER.size():
		_stage_bonuses[str(Meta.STAGE_ORDER[i])] = int(Meta.STAGE_START_COMBO[i + 1])


# ---------- Старт ----------
func start_game(initial_combo: int = -1, debug: bool = false) -> void:
	_run_seq += 1
	debug_run = debug
	run_bytes = 0
	if initial_combo < 0:
		initial_combo = debug_start_combo
	debug_start_combo = maxi(initial_combo, 0)
	# Вне F3 забег не может начаться с некупленного этапа: страховка на
	# случай, если высокий комбо придёт из skip/F3-наследия/внешнего вызова.
	if not debug and not meta.stage_owned(TaskGen.get_main_mode(initial_combo)):
		initial_combo = 0

	countdown_timer.stop()
	garbage_timer.stop()
	countdown_timer.paused = false
	garbage_timer.paused = false
	paused = false
	presenter.set_pause_visible(false)
	# Окно молчания на старт: клик, которым рестартнули игру (он же кнопка
	# ответа), и второй такт двойного клика не должны стать ответом.
	_answer_locked = true
	var grace := host.get_tree().create_timer(START_INPUT_GRACE)
	grace.timeout.connect(func() -> void: _answer_locked = false)

	active = true
	timer_value = float(START_TIME)
	combo = initial_combo
	max_combo = initial_combo
	order_index = 0
	current_quadrant = -1
	current_item = {}
	waiting_for_garbage = false
	errors_in_stage = 0
	_stage_bonus_given = {}
	for t in _stage_bonuses.values():
		if initial_combo >= t:
			_stage_bonus_given[t] = true
	mode = TaskGen.get_main_mode(combo)
	# Геометрия поля берётся из этапа сразу: старт с высоким комбо (skip из
	# магазина или F3) обязан увидеть то же поле, в котором будет играть.
	_field = _field_for(mode)
	_field_frozen = false
	presenter.set_field(_field)
	music.play_for_mode(mode)

	# Подсказки: при старте с высоким комбо (F3) баннеры пропущенных
	# модификаторов не сыпем — помечаем их уже объявленными. Попап правил
	# этапа из игры убран (фидбек 2026-11-14), остались только баннеры.
	presenter.reset_mod_flashes(initial_combo)
	if mode == "master":
		presenter.flash_master_intro()

	update_timer_display()
	update_combo_display()
	_update_bytes_display()

	var first_item := _gen.generate_item(mode, combo)
	current_item = first_item
	var first_quad: int = QUADRANT_ORDER[0]
	_apply_item(first_item, first_quad)
	order_index = 1
	countdown_timer.start(1.0)


# ---------- Обработка ответа ----------
# F4 — дебаг-пауза: гейта `if paused: return` здесь НЕТ намеренно
# (решение владельца 2026-11-14) — засчитывание ответов на паузе нужно для
# ручного тестирования. Фича removal при релизе, вместе с debug-меню F3.
func handle_answer(button: int) -> void:
	if not active:
		return
	if _answer_locked:
		return

	if waiting_for_garbage:
		garbage_timer.stop()
		waiting_for_garbage = false
		SFX.error()
		if mode == "master":
			end_game("master_error")
			return
		if _register_error_and_flash():
			end_game("errors_limit")
			return
		show_next_item()
		return

	if current_quadrant == -1 or current_item.is_empty():
		return
	if current_item["type"] == "garbage":
		return

	# correct_answer возвращает null (нет ответа/мусор) либо номер кнопки.
	var correct: Variant = TaskGen.correct_answer(current_item, current_quadrant)
	if correct == null:
		return

	if button == correct:
		SFX.key()
		combo += 1
		if combo > max_combo:
			max_combo = combo
		# Экономика забега: байты по курсу этапа (The Sequence — 0) и
		# «очки за всё время» в статистику этого этапа. F3-забег — вне
		# прогрессии: ни байтов, ни очков, чтобы обход гейта этапов
		# нельзя было перепутать с честным забегом.
		var rate: int = 0 if debug_run else int(Meta.BYTE_RATES.get(mode, 0))
		if not debug_run:
			meta.record_answer(mode)
		if rate > 0:
			run_bytes += rate
		update_combo_display()
		_flash_byte_gain(rate)
		if combo >= WIN_COMBO:
			end_game("win")
			return
		timer_value += BONUS_PER_CORRECT
		update_timer_display()

		# Фидбек: вдавливаем символ и слегка крутим экран.
		_answer_locked = true
		presenter.play_correct_feedback(current_quadrant)

		await host.get_tree().create_timer(ANSWER_FEEDBACK_DELAY).timeout
		# host жив (normal path: main не удаляется во время забега), но после
		# await дерево могло быть освобождено при выходе из игры.
		if not is_instance_valid(host):
			return
		_answer_locked = false
		if not active:
			return
		show_next_item()
	else:
		SFX.error()
		if mode == "master":
			end_game("master_error")
			return
		if _register_error_and_flash():
			end_game("errors_limit")
			return
		show_next_item()


# ---------- Таймеры ----------
func tick_countdown() -> void:
	timer_value -= 1.0
	update_timer_display()
	if timer_value <= 0.0:
		timer_value = 0.0
		update_timer_display()
		end_game("timeout")


func tick_garbage() -> void:
	waiting_for_garbage = false
	show_next_item()


# ---------- Пауза ----------
func toggle_pause() -> void:
	# F4 — дебаг-пауза: засчитывание ответов на паузе намеренно не блокируется
	# (см. комментарий над handle_answer); removal вместе с F3 при релизе.
	if not active:
		return
	# На перестройке поля пауза не нужна: таймер и так стоит, а индикатор
	# показывал бы неверное состояние (ответы в это время тоже закрыты).
	if _field_frozen:
		return
	paused = not paused
	countdown_timer.paused = paused
	garbage_timer.paused = paused
	presenter.set_pause_visible(paused)


# ---------- Отображение ----------
# Решение, ЧТО показать, остаётся здесь; как именно оно ложится на квадранты —
# SessionPresentation.show_item. Возвращает флаг «мусора»: таймер ожидания
# реакции — состояние забега, поэтому заводим его тут, а не в витрине.
func _apply_item(item: Dictionary, quad_index: int) -> void:
	current_item = item
	if presenter.show_item(item, quad_index, current_quadrant, combo):
		waiting_for_garbage = true
		garbage_timer.start(GARBAGE_TIMEOUT)
	current_quadrant = quad_index


func show_next_item() -> void:
	if waiting_for_garbage:
		return

	const STAGE_TIME_BONUS := 5.0
	var new_mode := TaskGen.get_main_mode(combo)
	if new_mode != mode:
		# Гейт мета-прогрессии: следующий этап не куплен — забег успешно
		# завершается на границе установленных модулей (F3-старт обходит).
		if not debug_run and not meta.stage_owned(new_mode):
			end_game("stage_complete")
			return
		mode = new_mode
		errors_in_stage = 0
		music.play_for_mode(mode)
		if new_mode == "master":
			presenter.flash_master_intro()
		# Бонус времени за переход на новый этап (один раз на этап).
		var threshold: int = _stage_bonuses.get(new_mode, 0)
		if threshold > 0 and combo >= threshold and not _stage_bonus_given.has(threshold):
			_stage_bonus_given[threshold] = true
			timer_value += STAGE_TIME_BONUS
			update_timer_display()
		# Новая геометрия поля (2×2 <-> одно поле на весь экран) — ступенчатой
		# анимацией. Пока поле перестраивается, таймер стоит и ответы закрыты:
		# игрок не теряет секунды на переход, которого сам не вызывал.
		var new_field := _field_for(new_mode)
		if new_field != _field:
			await _morph_field(new_field)
			if not active:
				return

	var item := _gen.generate_item(mode, combo)
	current_item = item

	_apply_item(item, _take_quadrant())
	presenter.flash_new_modifiers(str(item.get("submode", mode)), combo)


# Угол показа следующего задания (побочно двигает круговой индекс).
# На одном поле угла нет — всегда главный квадрант 0. В сетке: «ПОРЯДОК-»
# на первом этапе подкидывает случайность с шансом RANDOM_QUAD_CHANCE,
# в THE SEQUENCE случайность — базовое правило этапа (фидбек 2026-11-14:
# круговой порядок в финале читался как заученный).
func _take_quadrant() -> int:
	if _field == StageLayout.Field.FULL:
		return 0
	if _random_quadrant_next():
		return QUADRANT_ORDER[randi() % QUADRANT_ORDER.size()]
	var quad: int = QUADRANT_ORDER[order_index]
	order_index = (order_index + 1) % QUADRANT_ORDER.size()
	return quad


func _random_quadrant_next() -> bool:
	if mode == "master":
		return true
	if mode == "letters":
		var mods := _gen.modifiers_for("letters", combo)
		return bool(mods.get("randomQuadrant", false)) and randf() < RANDOM_QUAD_CHANCE
	return false


# Какое поле нужно этапу: буквы судят по «верх/низ», поэтому им сетка;
# фигуры и Струп читаются с одного большого знака.
static func _field_for(m: String) -> int:
	return StageLayout.Field.FULL if FULL_FIELD_MODES.has(m) else StageLayout.Field.GRID


# Перестройка поля: витрина знает, как анимировать геометрию, правила —
# замораживают таймер и закрывают ответы на время морфинга.
func _morph_field(new_field: int) -> void:
	var seq := _run_seq
	_field_frozen = true
	_answer_locked = true
	countdown_timer.paused = true
	presenter.play_field_transition(new_field)
	await host.get_tree().create_timer(StageLayout.FREEZE_TIME).timeout
	if seq != _run_seq:
		# Новый забег стартовал в середине анимации (F3-меню): его геометрию
		# и гейты установил start_game, старой корутине здесь делать нечего.
		return
	_field = new_field
	_field_frozen = false
	if not is_instance_valid(host) or not active:
		# Забег оборвался в середине анимации (ESC, таймаут, поражение).
		# Таймер остаётся остановленным; start_game всегда поднимает его
		# с paused = false, чинить здесь нечего.
		return
	countdown_timer.paused = paused
	_answer_locked = false


# ---------- Завершение ----------
func end_game(reason: String) -> void:
	if not active:
		return
	active = false
	countdown_timer.stop()
	garbage_timer.stop()
	# Снять заморозку перестройки поля: таймер всё равно остановлен, но
	# оставленный paused = true запутал бы следующий старт, если бы он
	# пришёлся в обход start_game (внешние провы).
	countdown_timer.paused = false
	waiting_for_garbage = false
	presenter.clear_quadrants()

	var stage_idx: int = TaskGen.get_stage_index(mode)
	var progress_pct: int = _progress_pct()

	# Зарплата забега уходит в общий кошелёк и сохраняется. run_bytes не
	# обнуляем: катсцены печатают её как «SALARY», старт нового забега сбросит.
	if run_bytes > 0:
		meta.add_bytes(run_bytes)
	save_requested.emit()

	run_finished.emit(reason, stage_idx, progress_pct)


# ---------- Обновление верхних полосок (формат и вывод — у SessionPresentation) ----------
func update_timer_display() -> void:
	# Ограничиваем и отображаемое значение, и само поле: иначе бар (max_value)
	# «врал» бы при накоплении времени выше предела.
	timer_value = clampf(timer_value, 0.0, MAX_TIME)
	presenter.push_timer(timer_value)


func update_combo_display() -> void:
	presenter.push_combo(combo, _progress_pct())


func _progress_pct() -> int:
	return clampi(int(round(float(combo) * 100.0 / float(WIN_COMBO))), 0, 100)


# ---------- Экономика байтов на HUD (формат строки — у витрины) ----------
func _update_bytes_display() -> void:
	presenter.push_bytes(meta.balance(), run_bytes, debug_run)


func _flash_byte_gain(amount: int) -> void:
	presenter.flash_byte_gain(amount, meta.balance(), run_bytes, debug_run)


# ---------- Ошибки и откат ----------
# Инкрементирует счётчик ошибок; возвращает true, если лимит исчерпан.
# Лимит = купленный «допуск ошибок» (0 ур. — любая ошибка фатальна).
# Если ошибка не фатальна — применяется купленный уровень отката.
func _register_error_and_flash() -> bool:
	errors_in_stage += 1
	var allowed: int = meta.tolerance()
	if errors_in_stage > allowed:
		return true
	presenter.flash_error_left(allowed - errors_in_stage)
	_apply_rollback()
	return false


func _apply_rollback() -> void:
	# 0: в начало игры · 1: в начало этапа · 2: -20 очков · 3: без отката.
	match meta.rollback_level():
		0:
			combo = 0
		1:
			combo = TaskGen.get_mode_reset_value(combo)
		2:
			combo = maxi(0, combo - ROLLBACK_POINTS)
		_:
			pass
	update_combo_display()
	var new_mode := TaskGen.get_main_mode(combo)
	if new_mode != mode:
		# Откат уронил игрока на предыдущий этап: музыка и бюджет ошибок — новые.
		mode = new_mode
		errors_in_stage = 0
		music.play_for_mode(mode)
	# Откат — это новый проход сквозь те же пороги: пересобираем список
	# «объявленных» баннеров (всё, что ниже текущего комбо, объявится заново
	# при следующем переходе; уже взятые пороги остаются объявленными).
	# Фидбек 2026-11-14: после отката надписи больше не появлялись.
	presenter.reset_mod_flashes(combo)


# ---------- Баннеры модификаторов и этапов ----------
# (пороги, имена и учёт «уже объявлено» — у SessionPresentation)
