extends Node

const SFX_DIR := "res://audio/sfx/"
const KBD_FILES := ["kbd1.ogg", "kbd2.ogg", "kbd3.ogg", "kbd4.ogg", "kbd5.ogg"]
const ERR_FILES := ["err1.ogg", "err2.ogg", "err3.ogg"]
const CORRUPTED_FILE := "corrupted.ogg"
const BOOTING_FILE := "booting.ogg"
const SHUTDOWN_FILE := "ShutDown.ogg"

const POOL_SIZE := 6
const VOLUME_DB := -6.0

var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0

var _kbd_streams: Array[AudioStream] = []
var _err_streams: Array[AudioStream] = []
var _corrupted: AudioStream
var _booting: AudioStream
var _shutdown: AudioStream

var _last_kbd: int = -1
var _last_err: int = -1


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

# --- Public API ---
func key() -> void:
	_play_random(_kbd_streams, "kbd")


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
