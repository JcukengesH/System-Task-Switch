class_name SessionPresentation
extends RefCounted
# Презентация одного забега: содержимое квадрантов (ItemDisplay), числовые
# индикаторы HUD (таймер/комбо/прогресс/байты), полноэкранные баннеры и
# фидбек верного ответа. Правил забега не знает и состояния не держит —
# все значения передаёт SessionRules при каждом вызове. Единственная память —
# _mods_flashed: какие пороги модификаторов уже объявлены в текущем забеге
# (сбрасывается на старте и после отката, вызывает его SessionRules).
# Ноды не создаёт: витрина HUD нод — HudBuilder, квадранты приходят из сцены.

# Короткие имена модификаторов: вспыхивают на весь экран при включении
# (тот же приём, что большая цифра остатка ошибок).
const MOD_FLASH_NAMES := {
	"randomQuadrant": "ПОРЯДОК-",
	"flip": "ПЕРЕВОРОТ+",
	"inverse": "ИНВЕРСИЯ+",
	"garbage": "ПОМЕХИ+",
	"missingEdge": "ГРАНЬ-",
	"mathExpression": "ПРИМЕР+",
	"twoShapes": "ФИГУРА+",
	"shuffle": "ДИСЛЕКСИЯ+",
}

# Частота применения эффекта переворота к буквам (порог включения —
# в TaskGen.MOD_THRESHOLDS["letters"]["flip"]). Отдельный от Струпа рандома
# баланс-рычаг: в stroop-флипе своя частота внутри TaskGen.
const LETTERS_FX_CHANCE := 0.25

var hud: HudBuilder            # полосы/метки/оверлеи — вывод значений
var quadrants: Array = []      # ItemDisplay-узлы из Main.tscn
var fx_director: FxDirector    # тряска поля на верном ответе
var layout: StageLayout        # геометрия поля (2×2 / одно поле на экран)

# Пороги модификаторов, уже объявленные баннером в текущем забеге.
var _mods_flashed: Dictionary = {}


# ---------- Квадранты ----------
# Показывает задание в квадранте quad_index; prev_quadrant — квадрант прошлой
# задачи (-1, если первой). combo нужен только порогу «переворота» букв —
# отображение не принимает решений о правилах, величина приходит параметром.
# Возвращает true, если выпал «мусор»: таймер реакции и waiting_for_garbage —
# состояние забега, их заводит SessionRules.
func show_item(item: Dictionary, quad_index: int, prev_quadrant: int, combo: int) -> bool:
	# На одном поле виден только главный квадрант: задание в ином углу
	# просто исчезло бы с экрана. Правила (SessionRules) обязаны передать
	# нулевой индекс; чужой индекс = рассинхрон геометрии и правил, о нём кричим.
	if quad_index != 0 and field() == StageLayout.Field.FULL:
		push_warning("FULL-поле: квадрант %d невидим, взят главный 0" % quad_index)
		quad_index = 0

	# Оптимизация: раньше трогались все 4 квадранта на каждое задание.
	# Достаточно очистить предыдущий активный и подготовить новый.
	if prev_quadrant >= 0 and prev_quadrant < quadrants.size() and prev_quadrant != quad_index:
		_clear_quadrant(prev_quadrant)

	var quad: Variant = quadrants[quad_index]
	quad.clear_item()
	quad.set_transform_effect("none")
	quad.set_active(true)

	var is_garbage := false
	match item["type"]:
		"garbage":
			quad.show_text(item["text"], Color(0.55, 0.55, 0.55))
			SFX.corrupted()
			is_garbage = true
		"letter":
			if item["isRed"]:
				quad.show_text(item["display"], Color.BLACK, true)
			else:
				quad.show_text(item["display"], Color.WHITE, false)
			# Порог «переворота» букв берём из единой таблицы модификаторов
			# (TaskGen.MOD_THRESHOLDS), а не хардкодом; частота применения —
			# именованная константа LETTERS_FX_CHANCE.
			var flip_at: int = int(TaskGen.MOD_THRESHOLDS["letters"]["flip"])
			if combo >= flip_at and randf() < LETTERS_FX_CHANCE:
				quad.set_transform_effect(TaskGen.random_item(TaskGen.TRANSFORMS))
		"shape":
			var second: int = item["secondSides"] if item["twoShapes"] else -1
			var mf: bool = item.get("missingFirst", false)
			var ms: bool = item.get("missingSecond", false)
			var dt: String = item.get("digitText", "")
			quad.show_shape(item["sides"], item["digit"], dt, true, second, item["digitInFirst"], mf, ms)
		"stroop":
			var word_to_show: String = item["shuffledWord"] if item["shuffled"] else item["word"]
			quad.show_stroop(word_to_show, item["colorValue"], item["inverse"])
			if item["flip"]:
				quad.set_transform_effect(TaskGen.random_item(TaskGen.TRANSFORMS))

	# Короткий «терминальный бип»: символ не просто появился — он отпечатался.
	SFX.beep()
	return is_garbage


# Итог забега / прерывание: снять содержимое со всех квадрантов.
func clear_quadrants() -> void:
	for q in quadrants:
		# Тип — Variant: у item_display.gd нет class_name (файл чужой, не правим),
		# точный тип элемента недоступен анализатору — храним Variant.
		q.clear_item()
		q.set_active(false)
		q.set_transform_effect("none")


func play_correct_feedback(quad_index: int) -> void:
	if quad_index >= 0 and quad_index < quadrants.size():
		var q: Variant = quadrants[quad_index]
		if q:
			q.play_correct_feedback()
	fx_director.trigger_correct_shake()


func _clear_quadrant(index: int) -> void:
	var prev: Variant = quadrants[index]
	prev.clear_item()
	prev.set_active(false)
	prev.set_transform_effect("none")


# ---------- Геометрия поля (2×2 / одно поле на весь экран) ----------
# Что за геометрия нужна этапу — решает SessionRules; здесь только «как»:
# снять содержимое и переложить рамки.
func field() -> int:
	if layout == null:
		return StageLayout.Field.GRID
	return layout.field()


func set_field(f: int) -> void:
	if layout == null:
		return
	clear_quadrants()
	layout.set_field(f)


# Ступенчатый морфинг поля. Длительность витрина не ждёт: вызывающий
# сам держит таймер замороженным на StageLayout.FREEZE_TIME.
func play_field_transition(f: int) -> void:
	if layout == null:
		return
	clear_quadrants()
	layout.transition_to(f)


# ---------- Индикаторы HUD (тексты готовит здесь, значения даёт SessionRules) ----------
func set_pause_visible(v: bool) -> void:
	if hud.pause_indicator:
		hud.pause_indicator.visible = v


func push_timer(value: float) -> void:
	hud.set_timer_value(value)


func push_combo(combo: int, progress_pct: int) -> void:
	hud.set_combo_value(float(combo))
	hud.set_progress_text("ПРОГРЕСС: %d%%" % progress_pct)


func push_bytes(balance: int, run: int, debug_run: bool) -> void:
	hud.set_bytes_text(bytes_line(balance, run, debug_run))


# Всплывающий «+N B» + пульс счётчика (amount <= 0 — только переклейка строки,
# поведение унаследовано от прежнего _flash_byte_gain).
func flash_byte_gain(amount: int, balance: int, run: int, debug_run: bool) -> void:
	hud.flash_byte_gain(amount, bytes_line(balance, run, debug_run))


func flash_error_left(remaining: int) -> void:
	hud.flash_error_number(remaining)


func bytes_line(balance: int, run: int, debug_run: bool) -> String:
	var text: String = "BYTES: %d" % (balance + run)
	if debug_run:
		text += "   [F3-DEBUG: БЕЗ ПРОГРЕССА]"
	return text


# ---------- Баннеры ----------
# Первый переход порога модификатора за забег — белый баннер на весь экран.
# Пороги, уже перескоченные на старте (F3-комбо), помечены объявленными
# заранее и не сыпят баннерами подряд.
func flash_new_modifiers(submode: String, c: int) -> void:
	var thresholds: Dictionary = TaskGen.MOD_THRESHOLDS.get(submode, {})
	var items: Array = []
	for key in thresholds:
		var tag := submode + "/" + str(key)
		if _mods_flashed.has(tag) or c < int(thresholds[key]):
			continue
		_mods_flashed[tag] = true
		items.append({
			"text": str(MOD_FLASH_NAMES.get(key, str(key))),
			"color": Color.WHITE,
			"size": 150,
		})
	if not items.is_empty():
		hud.flash_announcements(items)


# Отметить объявленными все пороги на уровне upto_combo и ниже: после
# старта с высоким комбо и после отката урона (пороги выше текущего комбо
# объявятся заново при следующем переходе — фидбек 2026-11-14).
func reset_mod_flashes(upto_combo: int) -> void:
	_mods_flashed = {}
	for submode in TaskGen.MOD_THRESHOLDS:
		for key in TaskGen.MOD_THRESHOLDS[submode]:
			if upto_combo >= int(TaskGen.MOD_THRESHOLDS[submode][key]):
				_mods_flashed[str(submode) + "/" + str(key)] = true


# Начало финального этапа: белый «ВСЁ+», затем красное «ОШИБКИ = 0».
func flash_master_intro() -> void:
	hud.flash_announcements([
		{"text": "ВСЁ+", "color": Color.WHITE, "size": 220},
		{"text": "ОШИБКИ = 0", "color": Color(0.9, 0.1, 0.1), "size": 150},
	])
