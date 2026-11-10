# 担当 1「学ぶ」の確かめ: はじめての案内(FR-23)・ミスの振り返り(FR-24)・練習モードの画面(FR-25)。
# 本物の save.json に書かないよう、確認用のファイルに差し替えてから流す。見た目は tests/shoot_web.mjs の画像で見る。
extends "res://tests/suite.gd"

const B := preload("res://core/balance.gd")
const RunState := preload("res://core/run_state.gd")
const Evaluator := preload("res://core/evaluator.gd")
const SaveStore := preload("res://save/save_store.gd")
const Strings := preload("res://core/strings.gd")
const SAVE_PATH := "user://test_learn_save.json"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _new_app(tutorial_done: bool) -> Control:
	DirAccess.remove_absolute(SAVE_PATH)
	var app: Control = load("res://ui/app.tscn").instantiate()
	_root().add_child(app)
	_root().get_node("Sfx").enabled = false
	app.save = SaveStore.new(SAVE_PATH)
	app.save.load_data()
	app.save.tutorial_done = tutorial_done
	return app


func _done(app: Control) -> void:
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)


func _screen(app: Control) -> Control:
	return app.stage.get_child(-1)


func _to_card(play: Control) -> void:
	while not play.rs.panel_ready():
		play.rs.tick(B.MAX_DELTA)
	play._dismiss_panel()


func _key_event(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	return e


# 本物の入力の道筋(_input → GUI → _unhandled_input)で 1 回押して離す
func _press(keycode: Key) -> void:
	_root().push_input(_key_event(keycode))
	var up := _key_event(keycode)
	up.pressed = false
	_root().push_input(up)


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func _labels(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


# wrong: 間違える [stage, card] の一覧
func _play_through(play: Control, wrong: Array) -> void:
	var rs: RefCounted = play.rs
	var guard := 0
	while rs.phase != RunState.Phase.ENDED:
		guard += 1
		if guard > 5000:
			errors.append("ランが終わらない")
			return
		if rs.phase == RunState.Phase.PANEL:
			_to_card(play)
		elif rs.phase == RunState.Phase.FEEDBACK:
			rs.tick(B.MAX_DELTA)
		else:
			var right: String = Evaluator.evaluate(rs.rules(), rs.current_card())["action"]
			var give := right
			if [rs.stage(), rs.card_index] in wrong:
				give = "drop" if right == "allow" else "allow"
			play._answered_frame = -1
			play._answer(give)


# FR-23: 初めてならステージ 1 の 1 枚目で出る。出ている間は時間が進まず、答え・技・キーを受けない。最後まで進むと閉じて保存
func test_tutorial_steps_block_and_save() -> bool:
	var app := _new_app(false)
	app.start_daily()
	var play := _screen(app)
	var rs: RefCounted = play.rs
	expect(not play.tutorial_open(), "パネルの間に案内が出た")
	_to_card(play)
	expect(play.tutorial_open(), "初めてなのに 1 枚目で案内が出ない")
	var tut: Control = play._tutorial
	expect_eq(tut.steps.size(), Strings.TUT_STEPS.size(), "案内の段の数")
	expect(tut.steps.all(func(st: Dictionary) -> bool: return not (st["rects"] as Array).is_empty()), "指す所の無い段がある")
	var elapsed: float = rs.elapsed
	for _i in 60:
		play._process(B.MAX_DELTA)
	expect_eq(rs.elapsed, elapsed, "案内の間に時間が進んだ")
	play._answered_frame = -1
	play._answer("allow")
	play._use_skill("scan")
	expect(rs.card_index == 0 and rs.phase == RunState.Phase.CARD and rs.misses.is_empty() and not rs.scanned, "案内の間に答えか技を受けた")
	_press(KEY_LEFT)
	_press(KEY_2)
	expect(rs.card_index == 0 and rs.phase == RunState.Phase.CARD and not rs.scanned, "案内の間に ← か 2 キーが play に届いた")
	expect_eq(tut.step, 0, "← で案内が進んだ")
	_press(KEY_SPACE)
	expect_eq(tut.step, 1, "Space で次の段へ")
	tut._gui_input(_click())
	expect_eq(tut.step, 2, "タップで次の段へ")
	expect(not app.save.tutorial_done, "最後の段より前に保存した")
	_press(KEY_ENTER)
	expect(not play.tutorial_open(), "最後の段で Enter を押しても閉じない")
	expect(app.save.tutorial_done, "閉じても tutorial_done が立たない")
	var again: RefCounted = SaveStore.new(SAVE_PATH)
	again.load_data()
	expect(again.tutorial_done, "tutorial_done がファイルに保存されていない")
	var right: String = Evaluator.evaluate(rs.rules(), rs.current_card())["action"]
	play._answered_frame = -1
	play._answer(right)
	expect_eq(rs.card_index, 1, "案内を閉じた後に答えられない")
	_done(app)
	return true


# FR-23: 「とばす」は 1 回で閉じて保存。練習でも出る。保存済みなら出ない
func test_tutorial_skip_and_not_again() -> bool:
	var app := _new_app(false)
	app.start_practice()
	var play := _screen(app)
	_to_card(play)
	expect(play.tutorial_open(), "練習でも初めてなら案内が出る")
	var skip: Button = play._tutorial.find_children("*", "Button", true, false)[0]
	skip.pressed.emit()
	expect(not play.tutorial_open() and app.save.tutorial_done, "「とばす」で閉じて保存")
	app.start_daily()
	play = _screen(app)
	_to_card(play)
	expect(not play.tutorial_open(), "保存した後も案内が出た")
	_done(app)
	app = _new_app(false)
	app.start_random()
	play = _screen(app)
	_to_card(play)
	_press(KEY_ESCAPE)
	expect(not play.tutorial_open() and not play.is_paused(), "Esc で案内を全部閉じる(一時停止にしない)")
	expect(app.save.tutorial_done, "Esc で閉じても保存")
	_done(app)
	return true


# FR-24: 格子の x のマスから、そのミスの振り返りが開く。前後へ移れて、キーで閉じる。Space で「もう一度」を押さない
func test_review_from_grid() -> bool:
	var app := _new_app(true)
	app.start_daily()
	var play := _screen(app)
	var rs: RefCounted = play.rs
	var wrong := [[1, 3], [2, 5], [4, 0]]
	_play_through(play, wrong)
	expect_eq(rs.misses.size(), 3, "ミスの数")
	app.finish_run(rs)
	var result := _screen(app)
	expect(Strings.REVIEW_HINT in _labels(result), "ミスがあるのに振り返りの案内が無い")
	var cell: Control = result._cells[(2 - 1) * B.CARDS_PER_STAGE + 5]
	cell.gui_input.emit(_click())
	var review: Control = result._review
	expect(review != null and review.visible, "x のマスを押しても振り返りが開かない")
	expect_eq(review.index, 1, "押したマスのミス")
	var m: Dictionary = rs.misses[1]
	var packet: RefCounted = rs.run["stages"][1]["cards"][5]
	expect_eq(review._card._values[2].text, str(packet.dport), "振り返りのカードのポート")
	var rows: Array = review._table._rows
	expect_eq(rows.size(), (rs.run["stages"][1]["rules"] as Array).size() + 1, "そのステージのルール表")
	var target: int = m["rule_index"] if m["rule_index"] >= 0 else rows.size() - 1
	expect(rows[target].modulate.a > 0.9 and rows.filter(func(r: Control) -> bool: return r.modulate.a < 0.5).size() == rows.size() - 1, "決め手の行だけが明るい")
	var expected_text := Strings.ALLOW if m["expected"] == "allow" else Strings.DROP
	var reason := Strings.REASON_ROW % [m["rule_index"] + 1, expected_text] if m["rule_index"] >= 0 else Strings.REASON_DEFAULT
	expect_eq(review._reason.text, reason, "決め手の文")
	expect_eq(review._yours.text, Strings.REVIEW_YOURS % (Strings.ALLOW if m["given"] == "allow" else Strings.DROP), "自分の答え")
	_press(KEY_RIGHT)
	expect_eq(review.index, 2, "→ で次のミス")
	_press(KEY_RIGHT)
	expect_eq(review.index, 2, "最後のミスより先へ進んだ")
	_press(KEY_LEFT)
	_press(KEY_LEFT)
	_press(KEY_LEFT)
	expect_eq(review.index, 0, "← で最初のミスまで戻る")
	_press(KEY_ESCAPE)
	expect(not review.visible, "Esc で閉じない")
	# 「もう一度」にフォーカスがあっても、振り返りの Space は閉じるだけ
	var retry: Button = result.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == Strings.RETRY)[0]
	retry.grab_focus()
	result.open_review(0)
	_press(KEY_SPACE)
	expect(not result._review.visible, "Space で閉じない")
	expect(_screen(app) == result and not result._leaving, "振り返りの Space で「もう一度」が押された")
	_done(app)
	return true


# FR-24: 時間切れのミスは「時間切れ」と出す。ミスが 0 なら案内を出さない
func test_review_timeout_and_no_misses() -> bool:
	var app := _new_app(true)
	app.start_daily()
	var play := _screen(app)
	var rs: RefCounted = play.rs
	_to_card(play)
	for _i in B.FREE_CARDS:
		play._answered_frame = -1
		play._answer(Evaluator.evaluate(rs.rules(), rs.current_card())["action"])
	while rs.phase == RunState.Phase.CARD:
		rs.tick(B.MAX_DELTA)
	expect(rs.misses.size() == 1 and rs.misses[0]["timeout"], "時間切れのミスが記録されない")
	_play_through(play, [])
	app.finish_run(rs)
	var result := _screen(app)
	result.open_review(0)
	expect_eq(result._review._yours.text, Strings.REVIEW_TIMEOUT, "時間切れの表示")
	_done(app)
	app = _new_app(true)
	app.start_daily()
	play = _screen(app)
	_play_through(play, [])
	app.finish_run(play.rs)
	expect(not Strings.REVIEW_HINT in _labels(_screen(app)), "ミス 0 なのに振り返りの案内が出た")
	_done(app)
	return true


# FR-25: 練習ではライフの印の代わりに「練習」。結果は自己ベストの代わりに「練習は記録に数えない」、ランクは出す
func test_practice_hud_and_result() -> bool:
	var app := _new_app(true)
	app.start_random()
	var normal := _screen(app)
	expect(normal._lives.visible and normal.find_child("PracticeTag", true, false) == null, "ふつうのランで練習の表示")
	app.start_practice()
	var play := _screen(app)
	var rs: RefCounted = play.rs
	expect(not play._lives.visible, "練習でライフの印が出ている")
	var tag: Label = play.find_child("PracticeTag", true, false)
	expect(tag != null and tag.visible and tag.text == Strings.PRACTICE, "練習の HUD に「練習」が無い")
	_play_through(play, [[1, 0], [1, 1], [1, 2], [1, 3]])
	expect_eq(rs.lives, rs.max_lives, "練習でライフが減った")
	app.finish_run(rs)
	var labels := _labels(_screen(app))
	expect(Strings.PRACTICE_NO_RECORD in labels, "練習の結果に「練習は記録に数えない」が無い")
	expect(not labels.any(func(t: String) -> bool: return t.contains(Strings.BEST % 0)), "練習の結果に自己ベストが出た")
	expect(Strings.RANK in labels, "練習の結果にランクが無い")
	_done(app)
	return true
