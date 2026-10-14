extends Node

const SFX_DIR := "res://audio/sfx/"
const KBD_FILES := ["kbd1.ogg", "kbd2.ogg", "kbd3.ogg", "kbd4.ogg", "kbd5.ogg"]
const ERR_FILES := ["err1.ogg", "err2.ogg", "err3.ogg"]
const CORRUPTED_FILE := "corrupted.ogg"
const BOOTING_FILE := "booting.ogg"
const SHUTDOWN_FILE := "ShutDown.ogg"

const POOL_SIZE := 6
# Отдача 11: SFX были на -6 дБ и тонули в музыке. База теперь 0 дБ,
# пишущий «бип» терминала поднят до -10, гул БП оставлен фоном.
const VOLUME_DB := 0.0

var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0

var _kbd_streams: Array[AudioStream] = []
var _err_streams: Array[AudioStream] = []
var _corrupted: AudioStream
var _booting: AudioStream
var _shutdown: AudioStream

var _last_kbd: int = -1
var _last_err: int = -1

# «Аутентичный стиль»: низкий гул блока питания + ступенчатый дисплейный бип.
# Оба просятся процедурно (AudioStreamWAV в памяти) — не тащим бинарные
# ассеты в репозиторий и не зависим от импортёра.
const HUM_DB := -33.0
const BEEP_DB := -10.0
var _hum_player: AudioStreamPlayer
var _beep_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = VOLUME_DB
		add_child(p)
		_pool.append(p)

	_kbd_streams = _load_group(KBD_FILES)
	_err_streams = _load_group(ERR_FILES)
	_corrupted = _load_one(CORRUPTED_FILE)
	_booting = _load_one(BOOTING_FILE)
	_shutdown = _load_one(SHUTDOWN_FILE)

	_hum_player = AudioStreamPlayer.new()
	_hum_player.bus = "Master"
	_hum_player.volume_db = HUM_DB
	_hum_player.stream = _synth_hum()
	_hum_player.autoplay = true
	add_child(_hum_player)

	_beep_player = AudioStreamPlayer.new()
	_beep_player.bus = "Master"
	_beep_player.volume_db = BEEP_DB
	_beep_player.stream = _synth_beep()
	add_child(_beep_player)


# 50/100 Гц сетевой фон + свист ВЧ-трансформатора + шипение коронного разряда.
# Шум детерминирован по индексу сэмпла — цикл замыкается без щелчка.
func _synth_hum() -> AudioStreamWAV:
	var sr := 22050
	var n := sr * 2  # ровно 2 секунды = целое число периодов 50/100 Гц
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sr
		var v: float = sin(TAU * 50.0 * t) * 0.22 \
			+ sin(TAU * 100.0 * t) * 0.10 \
			+ sin(TAU * 7800.0 * t) * 0.02
		var h: float = float((i * 1103515245 + 12345) & 0x7FFFFFFF) / 2147483647.0
		v += (h - 0.5) * 0.05
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 28000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


# Короткий меандр 740 Гц с огибающей — «печатающийся» символ.
func _synth_beep() -> AudioStreamWAV:
	var sr := 22050
	var n := int(sr * 0.045)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sr
		var sq: float = 1.0 if fmod(t * 740.0, 1.0) < 0.5 else -1.0
		var env: float = 1.0 - float(i) / float(n)
		data.encode_s16(i * 2, int(clampf(sq * 0.4 * env, -1.0, 1.0) * 28000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	return wav


func _load_group(files: Array) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for f in files:
		var s := _load_one(f)
		if s:
			out.append(s)
	return out


func _load_one(fname: String) -> AudioStream:
	var path := SFX_DIR + fname
	if not ResourceLoader.exists(path):
		push_warning("SFX missing: " + path)
		return null
	return load(path)


func _next_player() -> AudioStreamPlayer:
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	return p


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := _next_player()
	p.stream = stream
	p.play()


func _play_random(streams: Array, group: String) -> void:
	if streams.is_empty():
		return
	var idx: int = randi() % streams.size()
	if streams.size() > 1:
		var last: int = _last_kbd if group == "kbd" else _last_err
		if idx == last:
			# Сдвигаем на любой другой, кроме last.
			idx = (last + 1 + randi() % (streams.size() - 1)) % streams.size()
	if group == "kbd":
		_last_kbd = idx
	else:
		_last_err = idx
	_play(streams[idx])

func set_volume(linear: float) -> void:
	var v: float = clampf(linear, 0.0, 1.0)
	var db: float
	if v <= 0.001:
		db = -80.0
	else:
		db = VOLUME_DB + linear_to_db(v)
	for p in _pool:
		p.volume_db = db
	# Гул и бип живут в своей громкости, но молчат вместе со всеми.
	if _hum_player:
		_hum_player.volume_db = -80.0 if v <= 0.001 else HUM_DB + linear_to_db(v)
	if _beep_player:
		_beep_player.volume_db = -80.0 if v <= 0.001 else BEEP_DB + linear_to_db(v)

# --- Public API ---
func key() -> void:
	_play_random(_kbd_streams, "kbd")


# Бип появления символа на квадранте (аутентичный стиль).
func beep() -> void:
	if _beep_player:
		_beep_player.play()


func error() -> void:
	_play_random(_err_streams, "err")


func corrupted() -> void:
	_play(_corrupted)


func booting() -> void:
	_play(_booting)


func shutdown_length() -> float:
	if _shutdown == null:
		return 0.0
	return _shutdown.get_length()


func shutdown() -> void:
	_play(_shutdown)


# Мгновенно гасит весь вывод: пул, гул и бип. Нужен, чтобы закрытие
# окна не ждало досылки аудио-буферов (отдача: «игра долго закрывается»).
func stop_all() -> void:
	for p in _pool:
		if p.playing:
			p.stop()
	if _hum_player != null and _hum_player.playing:
		_hum_player.stop()
	if _beep_player != null and _beep_player.playing:
		_beep_player.stop()
