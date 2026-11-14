class_name TaskGen
extends RefCounted
# Генерация заданий и правила режимов. Чистая логика: не знает про узлы,
# получает mode/combo параметрами. Единственное состояние — антиповтор
# слова в Струпе (_last_stroop_word).
# main.gd использует этот класс как единственный источник правил генерации.

# ---------- Данные режимов ----------
const VOWELS := ["A", "E", "I", "O"]
const CONSONANTS := ["G", "K", "M", "R"]
const EVEN := ["2", "4", "6", "8"]
const ODD := ["3", "5", "7", "9"]
const GARBAGE_SYMBOLS := ["!", "@", "#", "$", "%", "^", "&", "*", "?", "+", "_", "№"]

const FIGURE_TYPES := ["circle", "triangle", "square", "pentagon", "hexagon", "octagon"]
const SIDES_MAP := {
	"circle": 0, "triangle": 3, "square": 4,
	"pentagon": 5, "hexagon": 6, "octagon": 8
}

const COLOR_WORDS := [
	{"name": "КРАСНЫЙ", "color": Color(0.85, 0.1, 0.1)},
	{"name": "СИНИЙ", "color": Color(0.15, 0.25, 0.95)},
	{"name": "ЗЕЛЕНЫЙ", "color": Color(0.15, 0.75, 0.15)},
	{"name": "ЖЕЛТЫЙ", "color": Color(0.95, 0.8, 0.0)},
	{"name": "БЕЛЫЙ", "color": Color(1, 1, 1)},
	{"name": "ФИОЛЕТОВЫЙ", "color": Color(0.55, 0.15, 0.75)},
	{"name": "ГОЛУБОЙ", "color": Color(0.1, 0.85, 0.9)}
]

# Пороги включения модификаторов по под-режимам (ключ — имя мода).
const MOD_THRESHOLDS := {
	"letters": {"randomQuadrant": 20, "flip": 40, "inverse": 60, "garbage": 80},
	"shapes": {"missingEdge": 120, "mathExpression": 140, "twoShapes": 160, "garbage": 180},
	"stroop": {"inverse": 220, "flip": 240, "shuffle": 260, "garbage": 280},
}

# Случайный поворот/переворот символа (используется и отрисовкой).
const TRANSFORMS := ["flip-h", "flip-v", "rotate-180"]

# ---------- Правила режимов (статические) ----------
# Границы этапов берутся из Meta.STAGE_START_COMBO — единый источник правды
# (§10.4), здесь больше нет хардкода 100/200/300. Порядок этапов:
# ["letters"] + Meta.STAGE_ORDER.

static func stage_modes() -> Array:
	return ["letters"] + Meta.STAGE_ORDER


static func _stage_index(c: int) -> int:
	var idx: int = 0
	for i in Meta.STAGE_START_COMBO.size():
		if c >= int(Meta.STAGE_START_COMBO[i]):
			idx = i
	return idx


static func get_main_mode(c: int) -> String:
	return String(stage_modes()[_stage_index(c)])


static func get_mode_reset_value(c: int) -> int:
	return int(Meta.STAGE_START_COMBO[_stage_index(c)])


static func get_stage_index(m: String) -> int:
	var i: int = stage_modes().find(m)
	return (i + 1) if i >= 0 else 1


static func correct_answer(item: Dictionary, quadrant: int) -> Variant:
	# quadrant < 2 — верхние квадранты (буква), иначе — цифра.
	if item["type"] == "garbage":
		return null
	if item["type"] == "letter":
		var is_top := quadrant < 2
		var correct: int = (2 if item["isVowel"] else 1) if is_top else (2 if item["isEven"] else 1)
		if item["isRed"]:
			correct = 1 if correct == 2 else 2
		return correct
	if item["type"] == "shape":
		return item["correct"]
	if item["type"] == "stroop":
		return item["correct"]
	return null


static func random_item(arr: Array) -> Variant:
	return arr[randi() % arr.size()]


static func shuffle_letters(s: String) -> String:
	var letters: Array = []
	for i in range(s.length()):
		letters.append(s[i])
	letters.shuffle()
	return "".join(PackedStringArray(letters))


# ---------- Генерация (инстанс: помнит последнее слово Струпа) ----------
var _last_stroop_word: String = ""


func modifiers_for(submode: String, combo: int) -> Dictionary:
	# Модификаторы описаны данными (MOD_THRESHOLDS), а не if-цепочкой.
	var mods := {}
	var thresholds: Dictionary = MOD_THRESHOLDS.get(submode, {})
	for key in thresholds:
		if combo >= int(thresholds[key]):
			mods[key] = true
	return mods


func choose_submode(mode: String) -> String:
	if mode == "master":
		return random_item(["letters", "shapes", "stroop"])
	return mode


func generate_item(mode: String, combo: int) -> Dictionary:
	var submode := choose_submode(mode)
	var mods := modifiers_for(submode, combo)

	if mods.get("garbage", false) and randf() < 0.15:
		var length := 3 + randi() % 3
		var text := ""
		for i in range(length):
			text += random_item(GARBAGE_SYMBOLS)
		return {"type": "garbage", "text": text, "submode": submode}

	if submode == "letters":
		return generate_letters_item(mods)
	elif submode == "shapes":
		return generate_shapes_item(mods)
	return generate_stroop_item(mods)


func generate_letters_item(mods: Dictionary) -> Dictionary:
	var is_vowel := randf() < 0.5
	var is_even := randf() < 0.5
	var letter: String = random_item(VOWELS) if is_vowel else random_item(CONSONANTS)
	var digit: String = random_item(EVEN) if is_even else random_item(ODD)
	var is_red: bool = mods.get("inverse", false) and randf() < 0.2
	return {
		"type": "letter", "letter": letter, "digit": digit,
		"isVowel": is_vowel, "isEven": is_even, "isRed": is_red,
		"display": letter + digit, "submode": "letters"
	}


func _generate_math_expression() -> Dictionary:
	if randf() < 0.5:
		var a: int = randi() % 5 + 1
		var b: int = randi() % 5 + 1
		return {"text": "%d+%d" % [a, b], "value": a + b}
	var a: int = randi() % 7 + 4
	var b: int = randi() % (a - 1) + 1
	return {"text": "%d-%d" % [a, b], "value": a - b}


func generate_shapes_item(mods: Dictionary) -> Dictionary:
	var figure_type: String = random_item(FIGURE_TYPES)
	var sides: int = SIDES_MAP[figure_type]

	var two_shapes := false
	var second_sides: int = 0
	if mods.get("twoShapes", false) and randf() < 0.2:
		two_shapes = true
		var fig2: String = random_item(FIGURE_TYPES)
		second_sides = SIDES_MAP[fig2]

	var missing_first := false
	var missing_second := false
	if mods.get("missingEdge", false):
		if sides >= 3 and randf() < 0.35:
			missing_first = true
		if two_shapes and second_sides >= 3 and randf() < 0.35:
			missing_second = true

	var visible_first: int = sides - 1 if missing_first else sides
	var visible_second: int = second_sides - 1 if missing_second else second_sides
	var total_visible: int = visible_first + (visible_second if two_shapes else 0)

	var digit_value: int
	var digit_text: String = ""
	var use_expr: bool = mods.get("mathExpression", false) and randf() < 0.35
	if use_expr:
		var expr := _generate_math_expression()
		digit_value = expr["value"]
		digit_text = expr["text"]
	else:
		if two_shapes:
			if randf() < 0.5:
				digit_value = min(total_visible, 16)
			else:
				digit_value = randi() % 17
		else:
			if randf() < 0.5:
				digit_value = min(visible_first, 9)
			else:
				digit_value = randi() % 10

	var digit_in_first := true
	if two_shapes:
		digit_in_first = randf() < 0.5

	var correct: int
	if two_shapes:
		correct = 2 if total_visible == digit_value else 1
	else:
		correct = 2 if visible_first == digit_value else 1

	return {
		"type": "shape", "sides": sides, "digit": digit_value,
		"digitText": digit_text,
		"twoShapes": two_shapes, "secondSides": second_sides,
		"digitInFirst": digit_in_first, "correct": correct,
		"missingFirst": missing_first, "missingSecond": missing_second,
		"submode": "shapes"
	}


func generate_stroop_item(mods: Dictionary) -> Dictionary:
	var word_obj: Dictionary
	var color_obj: Dictionary
	var match_flag: bool

	var word_pool: Array = []
	for w in COLOR_WORDS:
		if w["name"] != _last_stroop_word:
			word_pool.append(w)
	if word_pool.is_empty():
		word_pool = COLOR_WORDS.duplicate()

	if randf() < 0.5:
		word_obj = random_item(word_pool)
		color_obj = word_obj
		match_flag = true
	else:
		word_obj = random_item(word_pool)
		var filtered: Array = []
		for c in COLOR_WORDS:
			if c["name"] != word_obj["name"]:
				filtered.append(c)
		color_obj = random_item(filtered)
		match_flag = false

	_last_stroop_word = word_obj["name"]

	var inverse: bool = mods.get("inverse", false) and randf() < 0.2
	var shuffled := false
	var shuffled_word: String = word_obj["name"]
	if mods.get("shuffle", false) and randf() < 0.2:
		shuffled = true
		shuffled_word = shuffle_letters(word_obj["name"])

	var correct := 2 if match_flag else 1
	if inverse:
		correct = 1 if correct == 2 else 2

	var flip: bool = mods.get("flip", false) and randf() < 0.25

	return {
		"type": "stroop", "word": word_obj["name"], "colorValue": color_obj["color"],
		"match": match_flag, "inverse": inverse, "shuffled": shuffled,
		"shuffledWord": shuffled_word, "flip": flip, "correct": correct, "submode": "stroop"
	}
