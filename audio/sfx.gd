# 効果音を鳴らす(仕様書 FR-16・E-15)。起動時に assets/sfx/ の wav を読み、名前で鳴らす。
# ファイルが無い・読めない音は黙って飛ばす(落ちない・エラーを出さない)。知らない名前も無視する。
extends Node

const NAMES := ["correct", "wrong", "warn", "rule_update", "result", "skill"]
const POOL_SIZE := 4

var enabled := true:
	set(value):
		enabled = value
		if not value:
			_stop_music()  # 担当 4: 音が切なら BGM もすぐ止める(FR-30)
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


# ===== 担当 4: BGM(FR-30)。set_music は 入/切(音が切なら app が false を渡す)、music_stage はステージ番号(0 はタイトル・結果) =====
# 効果音のプールとは別のプレーヤーで assets/bgm/loop.wav(tools/gen_bgm.py。取り込みでループ)を流す。
# ステージが進むほど pitch_scale を上げて速くする(音程も少し上がり、それが緊張感になる。8 で約 +2.8 半音)。
# ブラウザでは最初のクリック・キーまで Web Audio が止まっているので、鳴り始めはその後になる(FR-1)。
const MUSIC_PATH := "res://assets/bgm/loop.wav"
const MUSIC_DB := -2.0  # ステージ中の音量(曲そのものが -12 dBFS)
const MUSIC_QUIET_DB := -7.0  # タイトル・結果
const MUSIC_SILENT_DB := -40.0  # フェードの端
const MUSIC_FADE := 0.8  # 秒
const MUSIC_PITCH_QUIET := 0.94  # タイトル・結果は少しゆっくり
const MUSIC_PITCH_STEP := 0.025  # ステージ 1 が 1.0、1 つ進むごとに足す

var music_on := false  # 鳴らしている(フェードアウト中は false)
var _music: AudioStreamPlayer
var _music_stage := 0
var _music_tween: Tween


func set_music(on: bool) -> void:
	on = on and enabled
	if on == music_on:
		return
	music_on = on
	var player := _music_player()
	if player == null:
		music_on = false
		return
	if on:
		if not player.playing:  # フェードアウトの途中なら、そこから戻す
			player.volume_db = MUSIC_SILENT_DB
			player.pitch_scale = music_pitch(_music_stage)
			player.play()
		_music_fade(music_volume(_music_stage), false)
	else:
		_music_fade(MUSIC_SILENT_DB, true)


func music_stage(stage: int) -> void:
	_music_stage = clampi(stage, 0, 8)
	if not enabled:
		_stop_music()
		return
	if music_on:
		_music_fade(music_volume(_music_stage), false)


static func music_pitch(stage: int) -> float:
	return MUSIC_PITCH_QUIET if stage <= 0 else 1.0 + (stage - 1) * MUSIC_PITCH_STEP


static func music_volume(stage: int) -> float:
	return MUSIC_QUIET_DB if stage <= 0 else MUSIC_DB


func _music_player() -> AudioStreamPlayer:
	if _music == null and ResourceLoader.exists(MUSIC_PATH):
		var stream := load(MUSIC_PATH) as AudioStream
		if stream != null:
			_music = AudioStreamPlayer.new()
			_music.stream = stream
			add_child(_music)
	return _music


# 音量と速さを一緒に滑らせる。stop が true なら終わったら止める
func _music_fade(db: float, stop: bool) -> void:
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel()
	_music_tween.tween_property(_music, "volume_db", db, MUSIC_FADE)
	if not stop:
		_music_tween.tween_property(_music, "pitch_scale", music_pitch(_music_stage), MUSIC_FADE)
	else:
		_music_tween.chain().tween_callback(_music.stop)


# Godot 4.7 の Web(サンプル再生)は、ループで頭に戻るたびに Web Audio の再生速度が 1.0 に戻る
# (作り直した音源に pitch_scale を渡さない)。毎フレーム同じ値を入れ直して、ステージの速さを保つ
func _process(_delta: float) -> void:
	if _music != null and _music.playing and OS.has_feature("web"):
		_music.pitch_scale = _music.pitch_scale


func _stop_music() -> void:
	music_on = false
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null
	if _music != null:
		_music.stop()
# ===== 担当 4 ここまで =====


func play(sound_name: String) -> void:
	if not enabled or not _streams.has(sound_name) or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound_name]
	player.play()
