class_name MetaStore
extends RefCounted
# Состояние мета-прогрессии (кошелёк, купленные модули, уровни механик),
# правила покупок и сериализация секции [meta] конфига. Каталог цен и
# курсов — Meta; здесь только хранение и валидация покупок. Покупка
# атомарна: либо списывает байты и применяет эффект, либо не делает ничего.
# save()/SFX/обновление витрины остаются у контроллера (main.gd).

# Ключи см. Meta.default_meta(): bytes, stages, tolerance, rollback, skip, life.
var data: Dictionary = Meta.default_meta()


# Глубокая копия для экранов (apply_meta нигде не пишущий).
func snapshot() -> Dictionary:
	return data.duplicate(true)


func balance() -> int:
	return int(data["bytes"])


func add_bytes(amount: int) -> void:
	data["bytes"] = balance() + amount


func spend(price: int) -> bool:
	if balance() < price:
		return false
	data["bytes"] = balance() - price
	return true


func stage_owned(s: String) -> bool:
	if s == "letters":
		return true
	return bool(data["stages"].get(s, false))


func tolerance() -> int:
	return int(data["tolerance"])


func rollback_level() -> int:
	return int(data["rollback"])


func skip_start_combo() -> int:
	return int(Meta.STAGE_START_COMBO[clampi(int(data["skip"]), 0, Meta.MAX_LEVEL)])


func record_answer(stage: String) -> void:
	# «Очки за всё время» этапа — условие покупки пропуска следующего.
	data["life"][stage] = int(data["life"].get(stage, 0)) + 1


# Возвращает true, если покупка прошла (деньги списаны, эффект применён).
func try_buy(item: String) -> bool:
	match item:
		"stage_shapes", "stage_stroop", "stage_master":
			var stage: String = item.substr(6)
			if stage_owned(stage):
				return false
			var idx: int = Meta.STAGE_ORDER.find(stage)
			if idx > 0 and not stage_owned(str(Meta.STAGE_ORDER[idx - 1])):
				return false
			if not spend(int(Meta.STAGE_PRICES[stage])):
				return false
			data["stages"][stage] = true
		"tolerance":
			var lvl: int = tolerance()
			if lvl >= Meta.MAX_LEVEL or not spend(int(Meta.TOLERANCE_PRICES[lvl])):
				return false
			data["tolerance"] = lvl + 1
		"rollback":
			# Линия заблокирована, пока допуск ошибок не куплен хотя бы в 1 ур.
			if tolerance() < 1:
				return false
			var rb: int = rollback_level()
			if rb >= Meta.MAX_LEVEL or not spend(int(Meta.ROLLBACK_PRICES[rb])):
				return false
			data["rollback"] = rb + 1
		"skip":
			var sk: int = int(data["skip"])
			if sk >= Meta.MAX_LEVEL:
				return false
			var need_stage: String = str(Meta.STAGE_ORDER[sk])
			var prev_stage: String = "letters" if sk == 0 else str(Meta.STAGE_ORDER[sk - 1])
			if not stage_owned(need_stage):
				return false
			if int(data["life"].get(prev_stage, 0)) < Meta.SKIP_REQ_POINTS:
				return false
			if not spend(int(Meta.SKIP_PRICES[sk])):
				return false
			data["skip"] = sk + 1
		_:
			return false
	return true


# Чтение секции [meta] из уже загруженного ConfigFile (формат прежний).
func load_from_cfg(cfg: ConfigFile) -> void:
	data = Meta.default_meta()
	data["bytes"] = maxi(0, int(cfg.get_value("meta", "bytes", 0)))
	for s in Meta.STAGE_ORDER:
		data["stages"][s] = bool(cfg.get_value("meta", "stage_" + str(s), false))
	data["tolerance"] = clampi(int(cfg.get_value("meta", "tolerance", 0)), 0, Meta.MAX_LEVEL)
	data["rollback"] = clampi(int(cfg.get_value("meta", "rollback", 0)), 0, Meta.MAX_LEVEL)
	data["skip"] = clampi(int(cfg.get_value("meta", "skip", 0)), 0, Meta.MAX_LEVEL)
	for st in ["letters", "shapes", "stroop", "master"]:
		data["life"][st] = maxi(0, int(cfg.get_value("meta", "life_" + st, 0)))


# Запись секции [meta] в ConfigFile (вызывающий делает cfg.save).
func save_to_cfg(cfg: ConfigFile) -> void:
	cfg.set_value("meta", "bytes", int(data["bytes"]))
	for s in Meta.STAGE_ORDER:
		cfg.set_value("meta", "stage_" + str(s), bool(data["stages"][s]))
	cfg.set_value("meta", "tolerance", int(data["tolerance"]))
	cfg.set_value("meta", "rollback", int(data["rollback"]))
	cfg.set_value("meta", "skip", int(data["skip"]))
	for st in ["letters", "shapes", "stroop", "master"]:
		cfg.set_value("meta", "life_" + st, int(data["life"][st]))
