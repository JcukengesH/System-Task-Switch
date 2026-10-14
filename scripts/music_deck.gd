class_name MusicDeck
extends RefCounted
# Музыкальный плейлист терминала: intro->loop на трек. Не знает про игру —
# main.gd вызывает play(key) / play_for_mode(mode) / set_volume(v).

const MUSIC_TRACKS := {
	"menu":   {"intro": "res://audio/menu_intro_v2.ogg", "loop": "res://audio/menu_loop_v2.ogg"},
	"stage1": {"intro": "res://audio/stage1_intro.ogg",  "loop": "res://audio/stage1_loop.ogg"},
	"stage2": {"intro": "res://audio/stage2_intro.ogg",  "loop": "res://audio/stage2_loop.ogg"},
	"stage3": {"intro": "res://audio/stage3_intro.ogg",  "loop": "res://audio/stage3_loop.ogg"},
	"stage4": {"intro": "res://audio/stage4_intro.ogg",  "loop": "res://audio/stage4_loop.ogg"},
	"outro":  {"intro": "res://audio/outro.ogg",         "loop": ""},
}

# Ключ трека-интро для текущего этапа забега.
const STAGE_KEYS := {"letters": "stage1", "shapes": "stage2", "stroop": "stage3", "master": "stage4"}

var _intro_player: AudioStreamPlayer
var _loop_player: AudioStreamPlayer
var _current_key: String = ""


# Создаёт двух players (Master-шина) и вешает их на parent.
func attach(parent: Node) -> void:
	_intro_player = AudioStreamPlayer.new()
	_intro_player.bus = "Master"
	_intro_player.volume_db = -6.0
	_intro_player.finished.connect(_on_intro_finished)
	parent.add_child(_intro_player)

	_loop_player = AudioStreamPlayer.new()
	_loop_player.bus = "Master"
	_loop_player.volume_db = -6.0
	parent.add_child(_loop_player)


func play(key: String) -> void:
	if key == _current_key:
		return
	if _intro_player == null:
		return

	_current_key = key

	if _intro_player.playing:
		_intro_player.stop()
	if _loop_player.playing:
		_loop_player.stop()

	var entry: Dictionary = MUSIC_TRACKS.get(key, {})
	if entry.is_empty():
		push_warning("MusicDeck.play: неизвестный ключ '%s'" % key)
		return

	var intro_stream: AudioStream = _load(entry.get("intro", ""), false)
	if intro_stream != null:
		_intro_player.stream = intro_stream
		_intro_player.play()
	else:
		var loop_stream: AudioStream = _load(entry.get("loop", ""), true)
		if loop_stream != null:
			_loop_player.stream = loop_stream
			_loop_player.play()


# Переключение трека при смене этапа (letters..master -> stage1..4).
func play_for_mode(mode: String) -> void:
	var key: String = STAGE_KEYS.get(mode, "")
	if key != "":
		play(key)


# Ползунка громкости музыки 0..1 -> dB (общая кривая для intro/loop).
# Отдача 11: музыка чуть тише базовой громкости микса, чтобы SFX читались.
const VOLUME_TRIM_DB := -3.0


func set_volume(v: float) -> void:
	var c: float = clampf(v, 0.0, 1.0)
	var db: float = -80.0 if c <= 0.001 else linear_to_db(c) + VOLUME_TRIM_DB
	if _intro_player:
		_intro_player.volume_db = db
	if _loop_player:
		_loop_player.volume_db = db


func stop_all() -> void:
	if _intro_player != null and _intro_player.playing:
		_intro_player.stop()
	if _loop_player != null and _loop_player.playing:
		_loop_player.stop()


func _on_intro_finished() -> void:
	var entry: Dictionary = MUSIC_TRACKS.get(_current_key, {})
	var loop_path: String = entry.get("loop", "")
	if loop_path == "":
		return
	var loop_stream: AudioStream = _load(loop_path, true)
	if loop_stream == null:
		return
	_loop_player.stream = loop_stream
	_loop_player.play()


func _load(path: String, loop: bool) -> AudioStream:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
		if loop:
			stream.loop_offset = 0.0
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		stream.loop_begin = 0
	return stream
