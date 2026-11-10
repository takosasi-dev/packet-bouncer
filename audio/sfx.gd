# 効果音を鳴らす(仕様書 FR-16・E-15)。起動時に assets/sfx/ の wav を読み、名前で鳴らす。
# ファイルが無い・読めない音は黙って飛ばす(落ちない・エラーを出さない)。知らない名前も無視する。
extends Node

const NAMES := ["correct", "wrong", "warn", "rule_update", "result"]
const POOL_SIZE := 4

var enabled := true
var folder := "res://assets/sfx"  # テストで無いフォルダに向ける(E-15)

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for sound_name: String in NAMES:
		var path := "%s/%s.wav" % [folder, sound_name]
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream != null:
			_streams[sound_name] = stream
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play(sound_name: String) -> void:
	if not enabled or not _streams.has(sound_name) or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound_name]
	player.play()
