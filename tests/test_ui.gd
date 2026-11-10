# 画面をヘッドレスで組んで流す確かめ(AC-12・AC-21・AC-22 の後半・FR-17)。見た目は tests/shoot_web.mjs の画像で見る。
# 本物の save.json に書かないよう、確認用のファイルに差し替えてから流す。
extends "res://tests/suite.gd"

const B := preload("res://core/balance.gd")
const RunState := preload("res://core/run_state.gd")
const Evaluator := preload("res://core/evaluator.gd")
const SaveStore := preload("res://save/save_store.gd")
const SAVE_PATH := "user://test_ui_save.json"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _new_app() -> Control:
	DirAccess.remove_absolute(SAVE_PATH)
	var app: Control = load("res://ui/app.tscn").instantiate()
	_root().add_child(app)
	_root().get_node("Sfx").enabled = false  # 鳴らした音が残ると、終了処理で止まることがある
	app.save = SaveStore.new(SAVE_PATH)
	app.save.load_data()
	return app


func _screen(app: Control) -> Control:
	return app.stage.get_child(-1)


func _play_through(play: Control, mistakes: int) -> void:
	var rs: RefCounted = play.rs
	var wrong_left := mistakes
	var guard := 0
	while rs.phase != RunState.Phase.ENDED:
		guard += 1
		if guard > 5000:
			errors.append("ランが終わらない: phase %d stage %d card %d" % [rs.phase, rs.stage(), rs.card_index])
			return
		if rs.phase == RunState.Phase.PANEL:
			while not rs.panel_ready():
				rs.tick(B.MAX_DELTA)
			play._dismiss_panel()
		elif rs.phase == RunState.Phase.FEEDBACK:
			rs.tick(B.MAX_DELTA)
		else:
			var right: String = Evaluator.evaluate(rs.rules(), rs.current_card())["action"]
			var give := right
			if wrong_left > 0:
				give = "drop" if right == "allow" else "allow"
				wrong_left -= 1
			play._answered_frame = -1  # 同じフレームの 2 回目は捨てる作り(E-1)なので、テストでは毎回戻す
			play._answer(give)


func test_daily_run_to_result_and_retry() -> bool:
	var app := _new_app()
	expect(_screen(app).get_script() == preload("res://ui/title.gd"), "起動するとタイトル")
	app.start_daily()
	var play := _screen(app)
	expect(play.get_script() == preload("res://ui/play.gd"), "今日の検問でプレイ画面")
	var first_card: String = str(play.rs.stage_data()["cards"][0])
	_play_through(play, 2)
	expect_eq(play.rs.correct, B.STAGES * B.CARDS_PER_STAGE - 2, "2 回だけ間違えた正解数")
	app.finish_run(play.rs)
	var result := _screen(app)
	expect(result.get_script() == preload("res://ui/result.gd"), "結果画面")
	var share := result.get_children().filter(func(n: Node) -> bool: return n is TextEdit)
	expect(share.size() == 1 and share[0].text.contains("(初回)"), "共有テキストの欄に (初回)")
	expect_eq(app.save.daily_attempts(play.rs.date), 1, "日替わりの回数を保存した")
	result._leave(true)
	result._leave(true)  # E-17: 2 回目は捨てる
	var again := _screen(app)
	expect(again.get_script() == preload("res://ui/play.gd"), "もう一度でプレイ画面")
	expect_eq(str(again.rs.stage_data()["cards"][0]), first_card, "日替わりのもう一度は同じ列")
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)
	return true


func test_lives_out_and_random_retry() -> bool:
	var app := _new_app()
	app.start_random()
	var play := _screen(app)
	var first: String = str(play.rs.stage_data()["cards"])
	_play_through(play, B.LIVES)
	expect_eq(play.rs.lives, 0, "ライフ 0")
	app.finish_run(play.rs)
	var result := _screen(app)
	result._leave(true)
	expect(str(_screen(app).rs.stage_data()["cards"]) != first, "ランダムのもう一度は違う列")
	expect_eq(app.save.daily.size(), 0, "ランダムは日替わりに数えない")
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)
	return true


# FR-17: どの行も条件にしていない欄は 40%
func test_unused_fields_dimmed() -> bool:
	var app := _new_app()
	app.start_daily()
	var play := _screen(app)
	var rs: RefCounted = play.rs
	while not rs.panel_ready():
		rs.tick(B.MAX_DELTA)
	play._dismiss_panel()
	var card: Control = play._card
	for k: int in [0, 1]:
		expect(is_equal_approx(card._values[k].modulate.a, card.DIM_ALPHA), "ステージ 1 の欄 %d が薄くない" % k)
	expect(is_equal_approx(card._values[2].modulate.a, 1.0), "ステージ 1 のポート欄が薄い")
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)
	return true


# AC-22 の後半・E-15: 効果音のファイルが無くても落ちない
func test_missing_sfx_does_not_crash() -> bool:
	var sfx: Node = load("res://audio/sfx.gd").new()
	sfx.folder = "res://no_such_folder"
	_root().add_child(sfx)
	sfx.play("correct")
	sfx.play("no_such_sound")
	expect(sfx._streams.is_empty(), "無いフォルダから音を読んだ")
	sfx.queue_free()
	return true


# 「演出 弱」: 保存され、揺れと色ずれが起きない(依頼者の追加 2026-11-10)
func test_effects_low_stops_shake_and_glitch() -> bool:
	var app := _new_app()
	app.set_effects_low(true)
	app.shake(1.0)
	app.glitch(1.0)
	expect(app._shake == 0.0 and app._glitch == 0.0, "演出 弱でも揺れ・色ずれが起きた")
	var again: RefCounted = SaveStore.new(SAVE_PATH)
	again.load_data()
	expect(again.effects_low, "演出 弱が保存されない")
	app.set_effects_low(false)
	app.shake(1.0)
	expect(app._shake > 0.0, "演出 強に戻しても揺れない")
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)
	return true
