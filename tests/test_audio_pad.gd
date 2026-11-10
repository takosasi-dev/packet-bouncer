# 担当 4 の確かめ: BGM(FR-30)とゲームパッド(FR-33)。
# 本物の音は聞かない(ヘッドレスは音を出さないドライバー)。プレーヤーの状態だけ見て、鳴らしたらすぐ止める。
# パッドは InputEventJoypadButton / InputEventJoypadMotion を作って画面の入力に流す。
extends "res://tests/suite.gd"

const B := preload("res://core/balance.gd")
const RunState := preload("res://core/run_state.gd")
const Evaluator := preload("res://core/evaluator.gd")
const Strings := preload("res://core/strings.gd")
const SaveStore := preload("res://save/save_store.gd")
const SfxScript := preload("res://audio/sfx.gd")
const SAVE_PATH := "user://test_audio_pad_save.json"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _sfx() -> Node:
	return _root().get_node("Sfx")


func _new_app() -> Control:
	DirAccess.remove_absolute(SAVE_PATH)
	var app: Control = load("res://ui/app.tscn").instantiate()
	_root().add_child(app)
	_sfx().enabled = false
	app.save = SaveStore.new(SAVE_PATH)
	app.save.load_data()
	app.save.tutorial_done = true  # はじめての案内(FR-23)で止まらないように(メモリだけ)
	return app


func _end(app: Control) -> void:
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)


func _button(index: JoyButton, pressed: bool = true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = pressed
	return e


func _stick(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_X
	e.axis_value = value
	return e


func _push(event: InputEvent) -> void:
	_root().push_input(event)


func _press(index: JoyButton) -> void:
	_push(_button(index, true))
	_push(_button(index, false))


# PANEL なら閉じられるまで進めて A で閉じ、FEEDBACK なら次のカードまで進める
func _to_card(play: Control) -> void:
	var rs: RefCounted = play.rs
	var guard := 0
	while rs.phase != RunState.Phase.CARD and guard < 1000:
		guard += 1
		if rs.phase == RunState.Phase.PANEL and rs.panel_ready():
			_press(JOY_BUTTON_A)
		else:
			rs.tick(B.MAX_DELTA)
	play._answered_frame = -1  # 同じフレームの 2 回目は捨てる作り(E-1)なので、テストでは毎回戻す


func test_bgm_file_loops() -> bool:
	var stream := load("res://assets/bgm/loop.wav") as AudioStreamWAV
	expect(stream != null, "BGM の wav を読める")
	if stream == null:
		return true
	expect_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "取り込みでループする")
	expect_eq(stream.loop_begin, 0, "頭からループ")
	expect_eq(stream.mix_rate, 22050, "22050 Hz")
	expect(not stream.stereo, "モノラル")
	expect(absf(stream.get_length() - 16.0) < 0.01, "16 秒(120 BPM の 8 小節): %f" % stream.get_length())
	# 元の wav: 16bit・モノラル・22050 Hz、頭と尻の波形がつながっている
	var f := FileAccess.open("res://assets/bgm/loop.wav", FileAccess.READ)
	expect(f != null, "元の wav を開ける")
	if f == null:
		return true
	expect_eq(f.get_buffer(4).get_string_from_ascii(), "RIFF", "RIFF")
	f.seek(22)
	expect_eq(f.get_16(), 1, "チャンネル数")
	expect_eq(f.get_32(), 22050, "サンプリング周波数")
	f.seek(34)
	expect_eq(f.get_16(), 16, "ビット数")
	f.seek(40)
	var frames := f.get_32() / 2
	expect_eq(frames, 352800, "サンプル数")
	var head := f.get_16()
	f.seek(44 + (frames - 1) * 2)
	var tail := f.get_16()
	var jump := absi(((head + 32768) % 65536) - ((tail + 32768) % 65536))  # 符号付きの差
	expect(jump < 600, "頭と尻がつながる(差 %d)" % jump)
	expect(f.get_length() < 800 * 1024, "wav は 800 KB 未満: %d" % f.get_length())
	return true


func test_music_silent_when_sound_off() -> bool:
	var sfx := _sfx()
	sfx.enabled = false
	sfx.set_music(true)
	expect(not sfx.music_on, "音が切なら BGM を入れない")
	expect(sfx._music == null or not sfx._music.playing, "プレーヤーが止まっている")
	sfx.music_stage(4)
	expect(sfx._music == null or not sfx._music.playing, "ステージが変わっても鳴らない")
	# 鳴っている最中に音を切ると、フェードを待たずに止まる
	sfx.enabled = true
	sfx.set_music(true)
	expect(sfx.music_on and sfx._music != null and sfx._music.playing, "音が入なら鳴らす")
	sfx.enabled = false
	expect(not sfx.music_on and not sfx._music.playing, "音を切るとすぐ止まる")
	sfx.music_stage(0)
	return true


func test_music_fades_and_speeds_up() -> bool:
	var sfx := _sfx()
	sfx.enabled = true
	sfx.music_stage(1)
	sfx.set_music(true)
	var player: AudioStreamPlayer = sfx._music
	expect(player.playing, "入で鳴り始める")
	expect(player != sfx._players[0], "効果音のプールとは別のプレーヤー")
	expect_eq(player.volume_db, SfxScript.MUSIC_SILENT_DB, "小さい所から")
	sfx._music_tween.custom_step(SfxScript.MUSIC_FADE + 0.1)
	expect(is_equal_approx(player.volume_db, SfxScript.MUSIC_DB), "フェードインしてステージの音量: %f" % player.volume_db)
	expect(is_equal_approx(player.pitch_scale, 1.0), "ステージ 1 は元の速さ")
	sfx.music_stage(8)
	sfx._music_tween.custom_step(SfxScript.MUSIC_FADE + 0.1)
	expect(player.pitch_scale > 1.1, "ステージ 8 は速い: %f" % player.pitch_scale)
	sfx.music_stage(0)
	sfx._music_tween.custom_step(SfxScript.MUSIC_FADE + 0.1)
	expect(player.pitch_scale < 1.0 and player.volume_db < SfxScript.MUSIC_DB, "タイトル・結果は静かでゆっくり")
	var last := 0.0
	for s in range(1, B.STAGES + 1):
		expect(SfxScript.music_pitch(s) > last, "ステージ %d で速くなる" % s)
		last = SfxScript.music_pitch(s)
	sfx.set_music(false)
	expect(not sfx.music_on and player.playing, "切はフェードアウトしてから止める")
	sfx._music_tween.custom_step(SfxScript.MUSIC_FADE + 0.1)
	expect(not player.playing, "フェードが終わると止まる")
	sfx.enabled = false
	return true


func test_app_bgm_toggle_follows_sound() -> bool:
	var app := _new_app()
	var sfx := _sfx()
	sfx.enabled = true
	app.set_bgm(false)
	expect(not sfx.music_on, "BGM 切")
	app.set_sound(false)
	app.set_bgm(true)
	expect(app.save.bgm_on and not sfx.music_on, "音が切なら BGM 入でも鳴らさない")
	app.set_sound(true)
	expect(sfx.music_on, "音を入に戻すと BGM が鳴る")
	app.set_sound(false)
	expect(not sfx.music_on and not sfx._music.playing, "音を切ると止まる")
	_end(app)
	return true


func test_pad_answers_and_skills() -> bool:
	var app := _new_app()
	app.start_practice()
	var play: Control = app.stage.get_child(-1)
	var rs: RefCounted = play.rs
	var given: Array[String] = []
	rs.answered.connect(func(r: Dictionary) -> void: given.append(r["given"]))
	expect_eq(rs.phase, RunState.Phase.PANEL, "最初はルール更新のパネル")
	_to_card(play)
	expect_eq(rs.phase, RunState.Phase.CARD, "A でパネルを閉じる")
	_press(JOY_BUTTON_DPAD_RIGHT)
	expect_eq(given, ["allow"] as Array[String], "十字キーの右で通す")
	_to_card(play)
	_press(JOY_BUTTON_DPAD_LEFT)
	expect_eq(given.size(), 2, "十字キーの左で答える")
	expect(given.size() == 2 and given[1] == "drop", "左は落とす")
	# スティック: しきい値を超えた瞬間に 1 回だけ。倒したままなら次のカードでも答えない
	_to_card(play)
	_push(_stick(0.2))
	expect_eq(given.size(), 2, "小さく倒しただけでは答えない")
	_push(_stick(0.9))
	expect(given.size() == 3 and given[2] == "allow", "右に倒すと通す")
	_to_card(play)
	_push(_stick(0.95))
	_push(_stick(0.7))
	_push(_stick(0.5))
	expect_eq(given.size(), 3, "倒したままでは次を受けない")
	_push(_stick(0.1))
	_push(_stick(-0.8))
	expect(given.size() == 4 and given[3] == "drop", "戻してから左に倒すと落とす")
	# 技: X / Y / B が 1 / 2 / 3
	_to_card(play)
	rs.time_limit = 10.0  # 練習は時間なし。凍結は時間のあるカードだけなので、ここだけ時間を付ける
	rs.time_left = 10.0
	var before: Dictionary = rs.charges.duplicate()
	_press(JOY_BUTTON_X)
	_press(JOY_BUTTON_Y)
	_press(JOY_BUTTON_B)
	for skill: String in B.SKILLS:
		expect_eq(rs.charges[skill], before[skill] - 1, "%s を使った" % skill)
	expect(rs.frozen and rs.scanned and rs.shield_on, "凍結・解析・防壁")
	_end(app)
	return true


func test_pad_pause() -> bool:
	var app := _new_app()
	app.start_practice()
	var play: Control = app.stage.get_child(-1)
	var rs: RefCounted = play.rs
	_to_card(play)
	_press(JOY_BUTTON_START)
	expect(play.is_paused(), "Start で一時停止")
	var answered := [0]
	rs.answered.connect(func(_r: Dictionary) -> void: answered[0] += 1)
	_press(JOY_BUTTON_DPAD_RIGHT)
	_push(_stick(1.0))
	_push(_stick(0.0))
	expect_eq(answered[0], 0, "止めている間は答えない")
	_press(JOY_BUTTON_A)  # 再開のボタンにフォーカスがある(A は ui_accept)
	expect(not play.is_paused(), "A で再開")
	_press(JOY_BUTTON_START)
	_press(JOY_BUTTON_START)
	expect(not play.is_paused(), "Start でも再開")
	_end(app)
	return true


# タイトルは Godot の ui_* で選ぶ: 十字キーで動き、A(ui_accept に足した)で決める
func test_pad_title_menu() -> bool:
	var app := _new_app()
	var title: Control = app.stage.get_child(-1)
	for c: Node in title.find_children("*", "Container", true, false):  # 並べるのは次のフレームなので、ここで並べる
		c.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var buttons := title.find_children("*", "Button", true, false)
	(buttons[0] as Button).grab_focus()  # 本番では call_deferred で今日の検問に置く
	var first := _root().gui_get_focus_owner()
	_press(JOY_BUTTON_DPAD_DOWN)
	var moved := _root().gui_get_focus_owner()
	expect(moved != null and moved != first, "十字キーの下でフォーカスが動く")
	_press(JOY_BUTTON_A)
	expect(app.stage.get_child(-1).get_script() == preload("res://ui/play.gd"), "A で選んだモードが始まる")
	_end(app)
	return true


# 結果も同じ: 「もう一度」にフォーカスがあり、十字キーの右で「タイトルへ」、左で戻り、A で押す
func test_pad_result_menu() -> bool:
	var app := _new_app()
	app.start_random()
	var play: Control = app.stage.get_child(-1)
	var rs: RefCounted = play.rs
	var guard := 0
	while rs.phase != RunState.Phase.ENDED and guard < 5000:  # 全部まちがえてライフを使い切る
		guard += 1
		if rs.phase == RunState.Phase.CARD:
			var right: String = Evaluator.evaluate(rs.rules(), rs.current_card())["action"]
			play._answered_frame = -1
			play._answer("drop" if right == "allow" else "allow")
		elif rs.phase == RunState.Phase.PANEL and rs.panel_ready():
			play._dismiss_panel()
		else:
			rs.tick(B.MAX_DELTA)
	app.finish_run(rs)
	var result: Control = app.stage.get_child(-1)
	expect(result.get_script() == preload("res://ui/result.gd"), "結果画面")
	var retry: Button = null
	var to_title: Button = null
	for b: Button in result.find_children("*", "Button", true, false):
		if b.text == Strings.RETRY:
			retry = b
		elif b.text == Strings.TO_TITLE:
			to_title = b
	expect(retry != null and to_title != null, "もう一度・タイトルへのボタン")
	if retry == null or to_title == null:
		_end(app)
		return true
	retry.grab_focus()  # 本番では call_deferred で置く
	_press(JOY_BUTTON_DPAD_RIGHT)
	expect(_root().gui_get_focus_owner() == to_title, "十字キーの右でタイトルへ")
	_press(JOY_BUTTON_DPAD_LEFT)
	expect(_root().gui_get_focus_owner() == retry, "左でもう一度に戻る")
	_press(JOY_BUTTON_A)
	expect(app.stage.get_child(-1).get_script() == preload("res://ui/play.gd"), "A でもう一度")
	_end(app)
	return true
