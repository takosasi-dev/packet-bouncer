# 結果画面(仕様書 FR-11・FR-14・§9.9): 得点、正解数、最大の連続正解、到達ステージ、8 × 10 の結果の格子、
# 自己ベストの更新、選択できる共有テキストと「結果をコピー」(共有シートがあれば「結果を送る」も)、「もう一度」「タイトルへ」。
# コピーは試すだけで、成功したとは言わない(INV-11)。「もう一度」は最初の 1 回だけ受ける(E-17)。
extends Control

const P := preload("res://ui/palette.gd")
const B := preload("res://core/balance.gd")
const Strings := preload("res://core/strings.gd")
const ShareText := preload("res://core/share_text.gd")
const RunState := preload("res://core/run_state.gd")

const CELL := 40.0
const CELL_GAP := 5.0

var app: Control
var rs: RefCounted
var attempts_before := 0
var new_best := false
var _score_label: Label
var _score_shown := 0.0
var _copy_note: Label
var _leaving := false
var _cells: Array[Control] = []


func _ready() -> void:
	var lives_out: bool = rs.lives <= 0
	var head := P.label(Strings.RESULT_TITLE, 60, P.TEXT, P.bold())
	head.position = Vector2(0, 40)
	head.size = Vector2(720, 80)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(head)
	var sub_text: String = Strings.RESULT_LIVES_OUT if lives_out else Strings.RESULT_ALL_DONE % rs.total_cards()
	var mode_text: String
	if rs.mode == "daily":
		mode_text = "%s %s" % [rs.date, Strings.SHARE_FIRST if attempts_before == 0 else Strings.SHARE_NTH % (attempts_before + 1)]
	else:
		mode_text = Strings.SHARE_RANDOM
	mode_text += "  " + Strings.level_name(rs.level)
	var sub :=P.label("%s  /  %s" % [sub_text, mode_text], 24, P.WARN if lives_out else P.ALLOW)
	sub.position = Vector2(0, 118)
	sub.size = Vector2(720, 36)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	var cap := P.label(Strings.R_SCORE, 22, P.DIM)
	cap.position = Vector2(0, 168)
	cap.size = Vector2(720, 28)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(cap)
	_score_label = P.label("0", 96, P.TEXT, P.mono_bold())
	_score_label.position = Vector2(0, 190)
	_score_label.size = Vector2(720, 120)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.pivot_offset = Vector2(360, 60)
	add_child(_score_label)
	var best_text: String = (Strings.NEW_BEST + "  ") if new_best else ""
	var best := P.label(best_text + Strings.BEST % app.save.best_for(rs.level), 24, P.NEW_ROW if new_best else P.DIM, P.mono())
	best.position = Vector2(0, 306)
	best.size = Vector2(720, 34)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(best)
	if new_best:
		var t := best.create_tween().set_loops()
		t.tween_property(best, "modulate", Color(1.6, 1.5, 1.0), 0.4)
		t.tween_property(best, "modulate", Color.WHITE, 0.4)

	var stats := [
		[Strings.R_CORRECT, "%d/%d" % [rs.correct, rs.total_cards()]],
		[Strings.R_STREAK, str(rs.max_streak)],
		[Strings.R_STAGE, "%d/%d" % [rs.stage(), B.STAGES]],
	]
	for i in stats.size():
		var tile := Panel.new()
		tile.position = Vector2(28 + i * 228, 352)
		tile.size = Vector2(208, 92)
		tile.add_theme_stylebox_override("panel", P.box(Color(P.PANEL, 0.85), P.LINE, 14, 1))
		add_child(tile)
		var t_cap := P.label(stats[i][0], 22, P.DIM)
		t_cap.position = Vector2(0, 8)
		t_cap.size = Vector2(208, 26)
		t_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(t_cap)
		var t_val := P.label(stats[i][1], 36, P.TEXT, P.mono_bold())
		t_val.position = Vector2(0, 34)
		t_val.size = Vector2(208, 50)
		t_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(t_val)

	_build_grid(Vector2((720 - (CELL * B.CARDS_PER_STAGE + CELL_GAP * (B.CARDS_PER_STAGE - 1))) / 2.0, 464))

	var share := TextEdit.new()
	share.text = ShareText.build(rs.mode, rs.date, attempts_before, rs.score, rs.correct, rs.total_cards(), rs.stage(), rs.grid, B.SHARE_URL, rs.level, rs.skills_used)
	share.editable = false  # 選んでコピーはできる(E-11)
	share.position = Vector2(28, 838)
	share.size = Vector2(664, 150)
	share.add_theme_font_override("font", P.mono())
	share.add_theme_font_size_override("font_size", 22)
	share.add_theme_color_override("font_readonly_color", P.TEXT)
	share.add_theme_stylebox_override("read_only", P.box(Color(P.BG, 0.9), P.LINE, 10, 1))
	share.add_theme_stylebox_override("focus", P.box(Color(P.BG, 0.9), P.ACCENT, 10, 2))
	add_child(share)

	var copy := P.button(Strings.COPY, P.ACCENT, 28, 72)
	copy.position = Vector2(28, 998)
	copy.size = Vector2(664, 72)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(share.text)  # 確かめられないので「コピーしました」とは出さない(INV-11)
		_copy_note.text = Strings.COPY_TRIED
		Sfx.play("correct"))
	add_child(copy)
	if _can_send():  # スマホの共有シート(LINE・X など)。無いブラウザでは出さない
		copy.size = Vector2(322, 72)
		var send := P.button(Strings.SEND, P.ALLOW, 28, 72)
		send.position = Vector2(370, 998)
		send.size = Vector2(322, 72)
		send.pressed.connect(func() -> void:
			JavaScriptBridge.eval("navigator.share({text: %s}).catch(function () {})" % JSON.stringify(share.text), true)
			Sfx.play("correct"))
		add_child(send)
	_copy_note = P.label("", 22, P.DIM)
	_copy_note.position = Vector2(28, 1072)
	_copy_note.size = Vector2(664, 62)
	_copy_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copy_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_copy_note)

	var retry := P.button(Strings.RETRY, P.ALLOW, 34, 96)
	retry.position = Vector2(28, 1140)
	retry.size = Vector2(322, 96)
	retry.pressed.connect(_leave.bind(true))
	add_child(retry)
	var to_title := P.button(Strings.TO_TITLE, P.DIM, 30, 96)
	to_title.position = Vector2(370, 1140)
	to_title.size = Vector2(322, 96)
	to_title.pressed.connect(_leave.bind(false))
	add_child(to_title)
	retry.grab_focus.call_deferred()
	_build_rank()
	Sfx.play("result")
	if new_best:
		app.flash(P.NEW_ROW, 0.7)


# 8 行 × 10 マス。正解は o と青緑、不正解・時間切れは x と赤、出なかったカードは - と枠だけ(INV-6)
func _build_grid(origin: Vector2) -> void:
	for s in rs.grid.size():
		var row: String = rs.grid[s]
		for k in row.length():
			var ch := row[k]
			var color := P.ALLOW if ch == "o" else (P.DROP if ch == "x" else P.LINE)
			var cell := Panel.new()
			cell.position = origin + Vector2(k * (CELL + CELL_GAP), s * (CELL + CELL_GAP))
			cell.size = Vector2(CELL, CELL)
			cell.pivot_offset = cell.size / 2.0
			var fill := Color(color, 0.85) if ch != "-" else Color(P.PANEL, 0.6)
			cell.add_theme_stylebox_override("panel", P.box(fill, color, 8, 1, 6.0 if ch != "-" else 0.0))
			var mark := P.label(ch, 24, P.BG if ch != "-" else P.DIM, P.mono_bold())
			mark.size = cell.size
			mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(mark)
			add_child(cell)
			cell.scale = Vector2.ZERO
			var t := cell.create_tween()
			t.tween_interval(0.25 + (s * row.length() + k) * 0.012)
			t.tween_property(cell, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_cells.append(cell)


const RANK_COLORS := {"S": P.NEW_ROW, "A": P.ALLOW, "B": P.ACCENT, "C": P.WARN, "D": P.DROP}
const RANK_DELAY := 1.1  # 得点の数え上げが終わる頃に押す


# 得点の右にランクの判子を押す
func _build_rank() -> void:
	var rank: String = RunState.rank_for(rs.correct)
	var color: Color = RANK_COLORS.get(rank, P.DROP)
	var stamp := Panel.new()
	stamp.position = Vector2(566, 176)
	stamp.size = Vector2(124, 124)
	stamp.pivot_offset = stamp.size / 2.0
	stamp.rotation_degrees = -12.0
	stamp.add_theme_stylebox_override("panel", P.box(Color(color, 0.14), color, 18, 4, 18))
	add_child(stamp)
	var letter := P.label(rank, 76, color, P.mono_bold())
	letter.size = Vector2(124, 96)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.add_child(letter)
	var cap := P.label(Strings.RANK, 18, color)
	cap.position = Vector2(0, 88)
	cap.size = Vector2(124, 28)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.add_child(cap)
	stamp.modulate.a = 0.0
	stamp.scale = Vector2(2.6, 2.6)
	var t := stamp.create_tween()
	t.tween_interval(RANK_DELAY)
	t.tween_callback(func() -> void: Sfx.play("rule_update" if rank == "S" else "correct"))
	t.parallel().tween_property(stamp, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(stamp, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		app.shake(0.35)
		app.flash(color, 0.4))


func _process(delta: float) -> void:
	if _score_shown < rs.score:
		_score_shown = minf(rs.score, _score_shown + maxf(rs.score * 0.9, 300.0) * delta)
		_score_label.text = str(int(_score_shown))
		_score_label.scale = Vector2.ONE * (1.0 + 0.06 * sin(_score_shown * 0.05))
	else:
		_score_label.text = str(rs.score)
		_score_label.scale = Vector2.ONE


# Web で navigator.share があるときだけ「結果を送る」を出す(送れたかは分からないので、成功とは言わない。INV-11)
func _can_send() -> bool:
	if not OS.has_feature("web"):
		return false
	# 戻り値は文字列で比べる(型の違う値どうしの == は実行時エラーになり、リリース版では黙って止まる)
	return str(JavaScriptBridge.eval("typeof navigator.share", true)) == "function"


func _leave(again: bool) -> void:
	if _leaving:
		return  # E-17
	_leaving = true
	if again:
		app.retry(rs)
	else:
		app.show_title()
