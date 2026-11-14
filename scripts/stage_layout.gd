class_name StageLayout
extends RefCounted
# Геометрия игрового поля: сетка 2×2 (HEX-CYPHER и THE SEQUENCE — у буквы
# ответ зависит от «верх/низ») или одно поле на весь экран (POLYMETRY и
# STROOPTEST — привязка к углу ничего не значит, задание читается с одного
# большого знака).
# Узлы квадрантов приходят из Main.tscn, здесь только их rect'ы. Grid —
# обычный Control, а не GridContainer: контейнер переставил бы детей поверх
# нашей анимации и морфинг был бы невидим.
# Перестройка ступенчатая (STYLE.md: «анимации дискретные, без плавных
# фейдов/пружин»): рамки прыгают по 9 позициям, как переключение
# видеорежима на реальном VGA-терминале.

enum Field { GRID, FULL }

# px: зазор между квадрантами в сетке — унаследован от h/v_separation
# прежнего GridContainer (§10.4: число с источником, а не «на глаз»).
const CELL_SEP := 12.0
# шт.: дискретных положений морфинга и длительность одной ступени.
const MORPH_STEPS := 9
const STEP_TIME := 0.08
# с: вся перестройка поля.
const MORPH_TIME: float = float(MORPH_STEPS) * STEP_TIME
# с: на столько SessionRules держит таймер замороженным — MORPH_TIME плюс
# кадр запаса, чтобы анимация гарантированно завершилась до возврата в игру.
const FREEZE_TIME: float = MORPH_TIME + 0.05

var _grid: Control
var _quadrants: Array = []
var _field: int = Field.GRID
# Текущая анимация перестройки и её концы (номера Field), шаг квантования.
var _morph: Tween
var _morph_from: int = Field.GRID
var _morph_to: int = Field.GRID
var _step: int = -1


# Ставим квадранты «как есть» (anchors TOP_LEFT: position/size = честный
# rect, якоря не должны пересчитывать его за нас) и подписываемся на ресайз
# поля: изменение окна перекладывает сетку мгновенно.
func attach(grid: Control, quadrants: Array) -> void:
	_grid = grid
	_quadrants = quadrants
	if _grid == null:
		push_warning("StageLayout: узел Grid не найден — раскладка поля отключена")
		return
	for q in _quadrants:
		q.set_anchors_preset(Control.PRESET_TOP_LEFT)
		# StageLayout сам задаёт position/size напрямую, поэтому убираем
		# дизайн-таймовый custom_minimum_size из Main.tscn: иначе присвоение
		# smaller-размера движок клампит к 200x200 (проверено SIZEPROBE) —
		# в FULL-морфинге три рамки сходились бы не в точку, а в накладывающиеся
		# боксы, а в GRID при маленьком окне ячейки перекрывались бы.
		q.custom_minimum_size = Vector2.ZERO
	if not _grid.is_connected("resized", _apply_now):
		_grid.resized.connect(_apply_now)


func field() -> int:
	return _field


# Мгновенная перестройка: старт/рестарт забега, любое состояние вне игры.
func set_field(f: int) -> void:
	_kill_morph()
	_field = f
	_apply_now()


# Ступенчатая перестройка GRID <-> FULL. Длительность = MORPH_TIME;
# вызывающий (SessionRules) сам держит таймер замороженным на FREEZE_TIME.
func transition_to(f: int) -> void:
	if _grid == null or f == _field:
		return
	_kill_morph()
	_morph_from = _field
	_morph_to = f
	_field = f
	_step = -1
	# На время морфинга живы все четыре рамки: в FULL три доедут до центра
	# и исчезнут, в GRID — вырастут из центра в свои углы.
	for q in _quadrants:
		q.visible = true
	_morph = _grid.create_tween()
	_morph.tween_method(_set_k, 0.0, 1.0, MORPH_TIME)


# Один шаг твина -> квантованная позиция. Промежуточные значения отбрасываются:
# поле обязано стоять на месте между ступенями, а не скользить.
func _set_k(p: float) -> void:
	var idx: int = clampi(int(p * float(MORPH_STEPS)), 0, MORPH_STEPS)
	if idx == _step:
		return
	_step = idx
	var from := _rects(_morph_from)
	var to := _rects(_morph_to)
	var k: float = float(idx) / float(MORPH_STEPS)
	for i in _quadrants.size():
		_set_rect(_quadrants[i], _mix(from[i], to[i], k))
	if k >= 1.0:
		# Догнали: видимость и финальные rect'ы расставляет общая укладка.
		_morph = null
		_apply_now()


func _apply_now() -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	var rects := _rects(_field)
	for i in _quadrants.size():
		_set_rect(_quadrants[i], rects[i])
		# В FULL-поле остаётся только главный квадрант: три пустые рамки
		# поверх большого поля читались бы как артефакт, а не как поле.
		_quadrants[i].visible = _field == Field.GRID or i == 0


# Прямоугольники квадрантов для каждой геометрии, всегда от актуального
# размера поля — поэтому ресайз окна в середине анимации ничего не ломает.
func _rects(f: int) -> Array:
	var s: Vector2 = _grid.size
	var out: Array = []
	if f == Field.FULL:
		var mid: Vector2 = s / 2.0
		out.append(Rect2(Vector2.ZERO, s))
		for i in 3:
			out.append(Rect2(mid, Vector2.ZERO))
		return out
	var cw: float = maxf((s.x - CELL_SEP) / 2.0, 0.0)
	var ch: float = maxf((s.y - CELL_SEP) / 2.0, 0.0)
	out.append(Rect2(Vector2(0.0, 0.0), Vector2(cw, ch)))
	out.append(Rect2(Vector2(cw + CELL_SEP, 0.0), Vector2(cw, ch)))
	out.append(Rect2(Vector2(0.0, ch + CELL_SEP), Vector2(cw, ch)))
	out.append(Rect2(Vector2(cw + CELL_SEP, ch + CELL_SEP), Vector2(cw, ch)))
	return out


func _mix(a: Rect2, b: Rect2, k: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, k), a.size.lerp(b.size, k))


func _set_rect(q: Variant, r: Rect2) -> void:
	q.position = r.position
	q.size = r.size


func _kill_morph() -> void:
	if _morph != null and _morph.is_valid():
		_morph.kill()
	_morph = null
	_step = -1
