# はじめての案内(仕様書 FR-23)。プレイ画面に重ねて、指す所だけを明るく残し、光の枠で囲む。
# steps は [{text, rects: Array[Rect2](play の座標)}]。タップ / Space / Enter で次へ、最後で閉じる。Esc と「とばす」は 1 回で全部閉じる。
# 出ている間はキーとパッドを全部ここで止める(play の _unhandled_input に届かせない)。時間と答えは play が止める。
extends Control

const P := preload("res://ui/palette.gd")
const Strings := preload("res://core/strings.gd")

signal closed

const SHADE := Color(0.027, 0.043, 0.078, 0.82)  # P.BG を暗く重ねる
const PAD := 8.0  # 枠を指す物より少し外に出す
const TEXT_Y := 904.0  # カード(下端 890)と答えのボタン(上端 1036)の間

var steps: Array = []
var play: Control  # 一時停止中は入力を play に回す
var effects_low := false
var step := 0
var _text: Label
var _counter: Label
var _time := 0.0


func _ready() -> void:
	size = Vector2(720, 1280)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := Panel.new()
	box.position = Vector2(28, TEXT_Y)
	box.size = Vector2(664, 122)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", P.box(Color(P.PANEL, 0.96), P.NEW_ROW, 14, 2, 10))
	add_child(box)
	_text = P.label("", 28, P.TEXT, P.bold())
	_text.position = Vector2(20, 4)
	_text.size = Vector2(624, 86)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY  # Web 版は日本語の区切りの辞書が無いので字の間で折る
	box.add_child(_text)
	_counter = P.label("", 20, P.NEW_ROW)
	_counter.position = Vector2(20, 90)
	_counter.size = Vector2(624, 28)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_counter)
	var skip := P.button(Strings.TUT_SKIP, P.DIM, 22, 36)
	skip.position = Vector2(720 - 28 - 150, 1236)
	skip.size = Vector2(150, 36)
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(close)
	add_child(skip)
	_show()


func _show() -> void:
	_text.text = steps[step]["text"]
	_counter.text = Strings.TUT_NEXT % [step + 1, steps.size()]
	_text.modulate.a = 0.0
	_text.create_tween().tween_property(_text, "modulate:a", 1.0, 0.15)
	queue_redraw()


func next() -> void:
	if not visible:
		return
	step += 1
	if step >= steps.size():
		close()
	else:
		Sfx.play("correct")
		_show()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	if not effects_low:
		queue_redraw()  # 枠の光を脈打たせる


# 暗い幕を、指す所だけ抜いて塗る(横の帯に切って、帯ごとに穴のない所を塗る)
func _draw() -> void:
	var holes: Array = (steps[step]["rects"] as Array).map(func(r: Rect2) -> Rect2: return r.grow(PAD))
	var ys: Array = [0.0, size.y]
	for r: Rect2 in holes:
		ys.append(r.position.y)
		ys.append(r.end.y)
	ys.sort()
	for i in ys.size() - 1:
		var y0: float = ys[i]
		var y1: float = ys[i + 1]
		if y1 <= y0:
			continue
		var spans := holes.filter(func(r: Rect2) -> bool: return r.position.y < y1 and r.end.y > y0)
		spans.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
		var x := 0.0
		for r: Rect2 in spans:
			if r.position.x > x:
				draw_rect(Rect2(x, y0, r.position.x - x, y1 - y0), SHADE)
			x = maxf(x, r.end.x)
		if x < size.x:
			draw_rect(Rect2(x, y0, size.x - x, y1 - y0), SHADE)
	var a := 1.0 if effects_low else 0.7 + 0.3 * sin(_time * 4.0)
	for r: Rect2 in holes:
		for k in 3:  # 外へ薄くなる光
			draw_rect(r.grow(3.0 + k * 4.0), Color(P.NEW_ROW, 0.16 * a / (k + 1)), false, 4.0)
		draw_rect(r, Color(P.NEW_ROW, a), false, 3.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		next()
		accept_event()


# キーとパッドは GUI より先にここで受け、全部止める(左右で答えない・技を使わない)
func _input(event: InputEvent) -> void:
	if not visible or (play != null and play.is_paused()):
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (not event.pressed or event.echo):
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept"):
		next()
