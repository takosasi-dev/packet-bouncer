# プレイ画面(仕様書 FR-4〜FR-9・FR-16・FR-17): 状態の帯・ルール表・カード・残り時間・落とす/通す・ルール更新のパネル。
# 進行は run_state に任せ、ここは入力を渡して結果を見せるだけ。正誤は run_state の結果をそのまま使う(INV-1)。
# 入力は _process(時間を進める)より先に届くので、同じフレームの時間切れより入力が勝つ(E-14)。
extends Control

const P := preload("res://ui/palette.gd")
const B := preload("res://core/balance.gd")
const Strings := preload("res://core/strings.gd")
const RunState := preload("res://core/run_state.gd")
const RuleTable := preload("res://ui/rule_table.gd")
const Card := preload("res://ui/card.gd")

const MARGIN := 28.0
const TABLE_Y := 150.0
const CARD_Y := 640.0
const BAR_Y := 906.0
const REASON_Y := 930.0
const BUTTONS_Y := 1036.0
const END_DELAY := 0.9

var app: Control
var rs: RefCounted
var _table: Control
var _card: Control
var _stage_label: Label
var _score_label: Label
var _mult_label: Label
var _combo_label: Label
var _lives: LifeIcons
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _reason: Label
var _drop_btn: Button
var _allow_btn: Button
var _panel: Control
var _panel_go: Label
var _panel_title: Label
var _panel_stage: Label
var _panel_hint: Label
var _answered_frame := -1
var _shown_score := 0.0
var _ending := false


class LifeIcons extends Control:
	const P := preload("res://ui/palette.gd")
	var lives := 3
	var total := 3
	var hit := 0.0  # 減った直後の光

	func _draw() -> void:
		for i in total:
			var c := Vector2(size.x - 26.0 - i * 46.0, size.y / 2.0)
			var pts := PackedVector2Array()
			for k in 6:
				pts.append(c + Vector2.from_angle(PI / 6.0 + k * PI / 3.0) * 17.0)
			var alive := (total - 1 - i) < lives
			if alive:
				draw_colored_polygon(pts, Color(P.ALLOW, 0.85))
				pts.append(pts[0])
				draw_polyline(pts, P.TEXT, 2.0, true)
			else:
				pts.append(pts[0])
				draw_polyline(pts, Color(P.DROP, 0.5 + hit * 0.5), 2.0, true)
				draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), Color(P.DROP, 0.7), 3.0, true)
				draw_line(c + Vector2(-8, 8), c + Vector2(8, -8), Color(P.DROP, 0.7), 3.0, true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_hud()
	_table = RuleTable.new()
	_table.position = Vector2(MARGIN, TABLE_Y)
	add_child(_table)

	_card = Card.new()
	_card.home = Vector2(MARGIN, CARD_Y)
	_card.position = _card.home
	add_child(_card)
	_card.swiped.connect(_answer)
	_card.drag_changed.connect(_on_drag)

	_bar_track = ColorRect.new()
	_bar_track.color = Color(P.LINE, 0.8)
	_bar_track.position = Vector2(MARGIN, BAR_Y)
	_bar_track.size = Vector2(RuleTable.WIDTH, 12)
	add_child(_bar_track)
	_bar_fill = ColorRect.new()
	_bar_fill.color = P.ALLOW
	_bar_fill.size = _bar_track.size
	_bar_track.add_child(_bar_fill)

	_reason = P.label("", 30, P.WARN, P.bold())
	_reason.position = Vector2(MARGIN, REASON_Y)
	_reason.size = Vector2(RuleTable.WIDTH, 90)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_reason)

	_drop_btn = P.button(Strings.BTN_DROP, P.DROP, 40, 116)
	_drop_btn.position = Vector2(MARGIN, BUTTONS_Y)
	_drop_btn.size = Vector2(318, 116)
	_drop_btn.pressed.connect(_answer.bind("drop"))
	add_child(_drop_btn)
	_allow_btn = P.button(Strings.BTN_ALLOW, P.ALLOW, 40, 116)
	_allow_btn.position = Vector2(720 - MARGIN - 318, BUTTONS_Y)
	_allow_btn.size = Vector2(318, 116)
	_allow_btn.pressed.connect(_answer.bind("allow"))
	add_child(_allow_btn)
	for b: Button in [_drop_btn, _allow_btn]:
		b.focus_mode = Control.FOCUS_NONE  # Space/Enter をボタンに取られない
		b.pivot_offset = b.size / 2.0
		b.add_child(_shape_icon(b == _allow_btn))

	var hint := P.label(Strings.SWIPE_HINT, 20, P.DIM)
	hint.position = Vector2(0, 1172)
	hint.size = Vector2(720, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

	_build_panel()
	rs.stage_started.connect(_on_stage_started)
	rs.card_shown.connect(_on_card_shown)
	rs.answered.connect(_on_answered)
	rs.time_warned.connect(_on_warned)
	rs.ended.connect(_on_ended)
	_on_stage_started(rs.stage())  # start で出た最初のパネル


# 答えの形の印(INV-6): 通す=丸と右向きの山、落とす=×
func _shape_icon(allow: bool) -> Control:
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(36, 36)
	icon.position = Vector2(18 if not allow else 318 - 54, 40)
	var color := P.ALLOW if allow else P.DROP
	icon.draw.connect(func() -> void:
		var c := icon.size / 2.0
		if allow:
			icon.draw_arc(c, 15.0, 0.0, TAU, 32, color, 3.0, true)
			icon.draw_polyline(PackedVector2Array([c + Vector2(-5, -8), c + Vector2(4, 0), c + Vector2(-5, 8)]), color, 3.0, true)
		else:
			icon.draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), color, 4.0, true)
			icon.draw_line(c + Vector2(-11, 11), c + Vector2(11, -11), color, 4.0, true))
	return icon


func _build_hud() -> void:
	var hud := Panel.new()
	hud.position = Vector2(MARGIN, 24)
	hud.size = Vector2(RuleTable.WIDTH, 108)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_stylebox_override("panel", P.box(Color(P.PANEL, 0.75), P.LINE, 16, 1))
	add_child(hud)
	_stage_label = P.label("", 26, P.TEXT, P.bold())
	_stage_label.position = Vector2(20, 14)
	_stage_label.size = Vector2(220, 40)
	hud.add_child(_stage_label)
	_combo_label = P.label("", 22, P.NEW_ROW, P.bold())
	_combo_label.position = Vector2(20, 58)
	_combo_label.size = Vector2(220, 36)
	_combo_label.pivot_offset = Vector2(0, 18)
	hud.add_child(_combo_label)
	var score_cap := P.label(Strings.SCORE, 18, P.DIM)
	score_cap.position = Vector2(220, 8)
	score_cap.size = Vector2(224, 24)
	score_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(score_cap)
	_score_label = P.label("0", 50, P.TEXT, P.mono_bold())
	_score_label.position = Vector2(220, 28)
	_score_label.size = Vector2(224, 64)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.pivot_offset = Vector2(112, 32)
	hud.add_child(_score_label)
	_mult_label = P.label("", 30, P.ACCENT, P.mono_bold())
	_mult_label.position = Vector2(420, 40)
	_mult_label.size = Vector2(70, 40)
	_mult_label.pivot_offset = Vector2(35, 20)
	hud.add_child(_mult_label)
	var lives_cap := P.label(Strings.LIVES, 18, P.DIM)
	lives_cap.position = Vector2(500, 8)
	lives_cap.size = Vector2(144, 24)
	lives_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(lives_cap)
	_lives = LifeIcons.new()
	_lives.position = Vector2(500, 38)
	_lives.size = Vector2(150, 56)
	_lives.total = B.LIVES
	hud.add_child(_lives)


func _build_panel() -> void:
	_panel = Control.new()
	_panel.position = Vector2(0, CARD_Y - 30)
	_panel.size = Vector2(720, 1280 - CARD_Y + 30)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_dismiss_panel())
	add_child(_panel)
	var shade := ColorRect.new()
	shade.color = Color(P.BG, 0.9)
	shade.size = _panel.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(shade)
	var line := ColorRect.new()
	line.color = P.NEW_ROW
	line.size = Vector2(720, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(line)
	_panel_title = P.label(Strings.PANEL_TITLE, 72, P.NEW_ROW, P.bold())
	_panel_title.position = Vector2(0, 70)
	_panel_title.size = Vector2(720, 100)
	_panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_title.pivot_offset = Vector2(360, 50)
	_panel.add_child(_panel_title)
	_panel_stage = P.label("", 34, P.TEXT, P.mono_bold())
	_panel_stage.position = Vector2(0, 180)
	_panel_stage.size = Vector2(720, 50)
	_panel_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_panel_stage)
	_panel_hint = P.label("", 36, P.TEXT, P.bold())
	_panel_hint.position = Vector2(40, 260)
	_panel_hint.size = Vector2(640, 110)
	_panel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_panel_hint)
	_panel_go = P.label(Strings.PANEL_GO, 28, P.ALLOW)
	_panel_go.position = Vector2(0, 430)
	_panel_go.size = Vector2(720, 44)
	_panel_go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_panel_go)


func _process(delta: float) -> void:
	rs.tick(delta)
	if rs.phase == RunState.Phase.PANEL:
		_panel_go.modulate.a = (0.55 + 0.45 * sin(rs.elapsed * 6.0)) if rs.panel_ready() else 0.0
	# 残り時間のバー(制限なしのカードでは出さない。FR-8)
	_bar_track.visible = rs.phase == RunState.Phase.CARD and rs.time_limit > 0.0
	if _bar_track.visible:
		var ratio: float = rs.time_left / rs.time_limit
		_bar_fill.size.x = RuleTable.WIDTH * ratio
		var col := P.ALLOW.lerp(P.WARN, clampf((0.6 - ratio) / 0.35, 0.0, 1.0))
		if ratio < B.WARN_RATIO:
			col = P.DROP.lerp(P.WARN, 0.5 + 0.5 * sin(rs.elapsed * 30.0))
		_bar_fill.color = col
	# 得点は数え上げる
	_shown_score = move_toward(_shown_score, rs.score, maxf(40.0, absf(rs.score - _shown_score) * 8.0) * delta)
	_score_label.text = str(int(round(_shown_score)))
	_lives.hit = maxf(_lives.hit - delta * 2.0, 0.0)
	_lives.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:  # E-3
		return
	match event.keycode:
		KEY_LEFT, KEY_A:
			_answer("drop")
		KEY_RIGHT, KEY_D:
			_answer("allow")
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_dismiss_panel()
		_:
			return
	get_viewport().set_input_as_handled()


func _answer(action: String) -> void:
	if _ending or rs.phase != RunState.Phase.CARD or _answered_frame == Engine.get_process_frames():
		return  # E-1・E-2
	_answered_frame = Engine.get_process_frames()
	rs.answer(action)


func _dismiss_panel() -> void:
	if rs.dismiss_panel():
		var t := _panel.create_tween().set_parallel()
		t.tween_property(_panel, "modulate:a", 0.0, 0.18)
		t.tween_property(_panel, "position:y", _panel.position.y + 40.0, 0.18)
		t.chain().tween_callback(func() -> void: _panel.visible = false)


func _on_stage_started(stage: int) -> void:
	var data: Dictionary = rs.stage_data()
	_table.show_rules(data["rules"], data["new_indices"], true)
	_stage_label.text = Strings.STAGE % [stage, B.STAGES]
	_panel_stage.text = Strings.PANEL_STAGE % stage
	_panel_hint.text = Strings.STAGE_HINTS[stage - 1]
	_panel.visible = true
	_panel.modulate.a = 0.0
	_panel.position.y = CARD_Y - 30
	_card.visible = false
	_reason.text = ""
	var t := _panel.create_tween()
	t.tween_property(_panel, "modulate:a", 1.0, 0.2)
	_panel_title.scale = Vector2(1.6, 1.6)
	_panel_title.create_tween().tween_property(_panel_title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("rule_update")
	app.flash(P.NEW_ROW, 0.5)
	app.glitch(0.35)


func _on_card_shown(packet: RefCounted) -> void:
	_table.clear_highlight()
	_reason.text = ""
	for b: Button in [_drop_btn, _allow_btn]:
		b.modulate = Color.WHITE
		b.scale = Vector2.ONE
	var rules: Array = rs.rules()
	var dims := [
		rules.all(func(r: RefCounted) -> bool: return r.proto == "any"),
		rules.all(func(r: RefCounted) -> bool: return r.src_prefix == 0),
		rules.all(func(r: RefCounted) -> bool: return r.ports["kind"] == "any"),
	]
	_card.visible = true
	_card.set_packet(packet, rs.card_index + 1, B.CARDS_PER_STAGE, rs.time_limit > 0.0, dims)
	_card.enter()
	_card.interactive = true


func _on_drag(ratio: float) -> void:
	_drop_btn.modulate = Color(1.6, 1.6, 1.6) if ratio <= -1.0 else Color(1, 1, 1, 1.0 - maxf(ratio, 0.0) * 0.5)
	_allow_btn.modulate = Color(1.6, 1.6, 1.6) if ratio >= 1.0 else Color(1, 1, 1, 1.0 + minf(ratio, 0.0) * 0.5)


func _on_answered(result: Dictionary) -> void:
	_card.interactive = false
	_on_drag(0.0)
	var given_btn := _allow_btn if result["given"] == "allow" else _drop_btn
	if result["correct"]:
		_card.fly(result["given"])
		_burst(result["given"])
		_pop(given_btn)
		_float_text(Strings.GAIN % result["gained"], P.action_color(result["given"]), Vector2(360, 120))
		Sfx.play("correct")
		app.flash(P.action_color(result["given"]), 0.25)
		var t := _score_label.create_tween()
		_score_label.scale = Vector2(1.18, 1.18)
		t.tween_property(_score_label, "scale", Vector2.ONE, 0.18)
		if rs.multiplier() > result["multiplier"]:  # 倍率が上がった
			_float_text(Strings.MULT % rs.multiplier(), P.ACCENT, Vector2(455, 120))
	else:
		_card.reject(result["expected"])
		_table.highlight(result["rule_index"])
		var why: String
		if result["rule_index"] >= 0:
			var expected_text := Strings.ALLOW if result["expected"] == "allow" else Strings.DROP
			why = Strings.REASON_ROW % [result["rule_index"] + 1, expected_text]
		else:
			why = Strings.REASON_DEFAULT
		_reason.text = "%s: %s" % [Strings.TIMEOUT if result["timeout"] else Strings.MISS, why]
		_reason.modulate.a = 0.0
		_reason.create_tween().tween_property(_reason, "modulate:a", 1.0, 0.12)
		# 正しかった側のボタンを点滅させる(位置と文字で伝える。INV-6)
		var right_btn := _allow_btn if result["expected"] == "allow" else _drop_btn
		var t := right_btn.create_tween().set_loops(3)
		t.tween_property(right_btn, "scale", Vector2(1.06, 1.06), 0.12)
		t.tween_property(right_btn, "scale", Vector2.ONE, 0.12)
		(_drop_btn if right_btn == _allow_btn else _allow_btn).modulate = Color(1, 1, 1, 0.35)
		_lives.lives = rs.lives
		_lives.hit = 1.0
		Sfx.play("wrong")
		app.shake(0.7)
		app.glitch(1.0)
		app.flash(P.DROP, 0.8)
	_lives.lives = rs.lives
	_mult_label.text = Strings.MULT % rs.multiplier() if rs.multiplier() > 1 else ""
	_combo_label.text = Strings.COMBO % rs.streak if rs.streak >= 2 else ""
	if rs.streak >= 2:
		_combo_label.scale = Vector2(1.3, 1.3)
		_combo_label.create_tween().tween_property(_combo_label, "scale", Vector2.ONE, 0.2)


func _on_warned() -> void:
	Sfx.play("warn")


func _on_ended() -> void:
	_ending = true
	_card.interactive = false
	var t := create_tween()
	t.tween_interval(END_DELAY)
	t.tween_callback(func() -> void: app.finish_run(rs))


func _pop(btn: Button) -> void:
	btn.scale = Vector2(1.1, 1.1)
	btn.create_tween().tween_property(btn, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _float_text(text: String, color: Color, at: Vector2) -> void:
	var l := P.label(text, 40, color, P.mono_bold())
	l.size = Vector2(240, 50)
	l.position = at - Vector2(120, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "position:y", at.y - 70.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	t.chain().tween_callback(l.queue_free)


# 答えた側に粒を散らす
func _burst(action: String) -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(360 + (220.0 if action == "allow" else -220.0), CARD_Y + Card.HEIGHT / 2.0)
	p.amount = 48
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.spread = 180.0
	p.direction = Vector2(1 if action == "allow" else -1, 0)
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 620.0
	p.gravity = Vector2(0, 500)
	p.damping_min = 120.0
	p.damping_max = 240.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(P.TEXT))
	ramp.set_color(1, Color(P.action_color(action), 0.0))
	ramp.add_point(0.25, P.action_color(action))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
