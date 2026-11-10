# ミスの振り返り(仕様書 FR-24)。結果画面に重ねて、ミスしたカード・そのときのルール表・決め手の行・
# 「N 行目で決まり → 通す/落とす」・自分の答え(時間切れか)を出す。前後のミスへ移れる。
# キーは GUI より先にここで受ける(結果画面の「もう一度」にフォーカスがあっても Space で押させない)。
extends Control

const P := preload("res://ui/palette.gd")
const B := preload("res://core/balance.gd")
const Strings := preload("res://core/strings.gd")
const RuleTable := preload("res://ui/rule_table.gd")
const Card := preload("res://ui/card.gd")

const MARGIN := 28.0

var rs: RefCounted
var index := 0
var _table: Control
var _card: Control
var _count: Label
var _where: Label
var _reason: Label
var _yours: Label
var _prev: Button
var _next: Button
var _back_focus: Control  # 閉じたらフォーカスを戻す


func _ready() -> void:
	size = Vector2(720, 1280)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_back_focus = get_viewport().gui_get_focus_owner()
	var shade := ColorRect.new()
	shade.color = P.BG
	shade.size = size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var head := P.label(Strings.REVIEW_TITLE, 44, P.WARN, P.bold())
	head.position = Vector2(MARGIN, 34)
	head.size = Vector2(300, 64)
	add_child(head)
	_count = P.label("", 30, P.TEXT, P.bold())
	_count.position = Vector2(360, 34)
	_count.size = Vector2(720 - MARGIN - 360, 64)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_count)
	_where = P.label("", 24, P.DIM, P.mono_bold())
	_where.position = Vector2(MARGIN, 98)
	_where.size = Vector2(400, 36)
	add_child(_where)

	_table = RuleTable.new()
	_table.position = Vector2(MARGIN, 146)
	add_child(_table)
	_card = Card.new()
	_card.home = Vector2(MARGIN, 640)  # 6 行 + 既定の行の表(146 + 460)の下
	_card.position = _card.home
	add_child(_card)

	_reason = P.label("", 34, P.TEXT, P.bold())
	_reason.position = Vector2(MARGIN, 904)
	_reason.size = Vector2(664, 52)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_reason)
	_yours = P.label("", 26, P.WARN, P.bold())
	_yours.position = Vector2(MARGIN, 960)
	_yours.size = Vector2(664, 40)
	_yours.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_yours)

	_prev = _nav_button(Strings.REVIEW_PREV, P.ACCENT, 0)
	_prev.pressed.connect(step.bind(-1))
	var close_btn := _nav_button(Strings.CLOSE, P.DIM, 1)
	close_btn.pressed.connect(close)
	_next = _nav_button(Strings.REVIEW_NEXT, P.ACCENT, 2)
	_next.pressed.connect(step.bind(1))
	var keys := P.label(Strings.REVIEW_KEYS, 22, P.DIM)
	keys.position = Vector2(0, 1150)
	keys.size = Vector2(720, 30)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(keys)

	_show()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _nav_button(text: String, color: Color, slot: int) -> Button:
	var b := P.button(text, color, 28, 84)
	b.position = Vector2(MARGIN + slot * 228.0, 1040)
	b.size = Vector2(208, 84)
	b.focus_mode = Control.FOCUS_NONE  # Space はフォーカスのボタンではなく「閉じる」に使う
	add_child(b)
	return b


func step(d: int) -> void:
	var to := clampi(index + d, 0, rs.misses.size() - 1)
	if to != index:
		index = to
		_show()
		Sfx.play("correct")


func _show() -> void:
	var m: Dictionary = rs.misses[index]
	var s := int(m.get("stage", 1))
	var k := int(m.get("card", 0))
	var ri := int(m.get("rule_index", -1))
	var expected := str(m.get("expected", "drop"))
	var given := str(m.get("given", ""))
	var data: Dictionary = rs.run["stages"][s - 1]
	_count.text = Strings.REVIEW_COUNT % [index + 1, rs.misses.size()]
	_where.text = Strings.PANEL_STAGE % s
	_table.clear_highlight()
	_table.show_rules(data["rules"], [], false)
	_table.highlight(ri)
	var timed: bool = not rs.is_practice() and k >= B.FREE_CARDS
	_card.set_packet(data["cards"][k], k + 1, B.CARDS_PER_STAGE, timed, [false, false, false])
	var expected_text := Strings.ALLOW if expected == "allow" else Strings.DROP
	_reason.text = Strings.REASON_ROW % [ri + 1, expected_text] if ri >= 0 else Strings.REASON_DEFAULT
	_reason.add_theme_color_override("font_color", P.action_color(expected))
	if bool(m.get("timeout", false)):
		_yours.text = Strings.REVIEW_TIMEOUT
	else:
		_yours.text = Strings.REVIEW_YOURS % (Strings.ALLOW if given == "allow" else Strings.DROP)
	_prev.disabled = index == 0
	_next.disabled = index >= rs.misses.size() - 1


func close() -> void:
	if not visible:
		return
	visible = false
	if is_instance_valid(_back_focus) and _back_focus.is_inside_tree():
		_back_focus.grab_focus()
	queue_free()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (not event.pressed or event.echo):
		return
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.keycode == KEY_A):
		step(-1)
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.keycode == KEY_D):
		step(1)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
