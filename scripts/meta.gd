class_name Meta
extends RefCounted
# Данные мета-прогрессии: цены магазина, курсы байтов, дефолтное состояние.
# Экран SYSTEM UPDATE и main.gd используют этот каталог как единственный
# источник правды по ценам и условиям.

# Этапы, продающиеся как модули (letters — всегда доступен).
const STAGE_ORDER := ["shapes", "stroop", "master"]
const STAGE_PRICES := {"shapes": 150, "stroop": 400, "master": 900}

# Байты за верный ответ по этапу. The Sequence (master) — байтов не даёт.
const BYTE_RATES := {"letters": 1, "shapes": 2, "stroop": 3, "master": 0}

# Цены следующих уровней механик (индекс = текущий уровень).
const TOLERANCE_PRICES := [100, 300, 700]      # ур.0->1, 1->2, 2->3
const ROLLBACK_PRICES := [350, 600, 1200]      # ур.0->1, 1->2, 2->3 (ур.0 — базовый)
const SKIP_PRICES := [500, 900, 1500]          # ур.0->1, 1->2, 2->3

# Для покупки пропуска этапа N нужно: этап N куплен + столько очков
# (верных ответов) в предыдущем этапе за всё время.
const SKIP_REQ_POINTS := 300

# Стартовый комбо для уровня пропуска.
const STAGE_START_COMBO := [0, 100, 200, 300]
const STAGE_LABELS := ["HEX-CYPHER", "POLYMETRY", "STROOPTEST", "THE SEQUENCE"]

# Описания уровней отката для магазина.
const ROLLBACK_DESC := [
	"ОТКАТ В НАЧАЛО ИГРЫ",
	"ОТКАТ В НАЧАЛО ЭТАПА",
	"ОТКАТ -20 ОЧКОВ",
	"БЕЗ ОТКАТА",
]


static func default_meta() -> Dictionary:
	return {
		"bytes": 0,
		"stages": {"shapes": false, "stroop": false, "master": false},
		"tolerance": 0,
		"rollback": 0,
		"skip": 0,
		"life": {"letters": 0, "shapes": 0, "stroop": 0, "master": 0},
	}
