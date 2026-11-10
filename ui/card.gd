# パケットのカード(仕様書 §9.1・D-6・FR-17)。プロトコル・送信元・宛先ポートを、ルール表と同じ横位置に出す。
# 左右に SWIPE_PX 以上ドラッグして離すと答えになり、足りなければ戻る。最初の指だけを追い、窓の外で離したらその場で離したとみなす(E-4・E-5)。
extends Control

const P := preload("res://ui/palette.gd")
const B := preload("res://core/balance.gd")
const Strings := preload("res://core/strings.gd")
const Packet := preload("res://core/packet.gd")
const Table := preload("res://ui/rule_table.gd")

signal swiped(action: String)
signal drag_changed(ratio: float)  # -1(落とす側)〜 1(通す側)

const HEIGHT := 250.0
const DIM_ALPHA := 0.4  # FR-17 の不透明度 40%

var interactive := false
var home := Vector2.ZERO
var _bg: Panel
var _header: Label
var _free: Label
var _values: Array[Label] = []
var _captions: Array[Label] = []
var _scan: ColorRect
var _stamp: Label
var _dragging := false
var _drag_start := 0.0
var _tween: Tween


func _ready() -> void:
	size = Vector2(Table.WIDTH, HEIGHT)
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = Panel.new()
	_bg.size = size
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_theme_stylebox_override("panel", P.box(P.BG_LIFT, P.ACCENT, 22, 2, 24))
	add_child(_bg)
	var stripe := ColorRect.new()  # 上の帯
	stripe.color = Color(P.ACCENT, 0.18)
	stripe.position = Vector2(2, 2)
	stripe.size = Vector2(size.x - 4, 54)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)
	_header = P.label("", 24, P.TEXT, P.mono_bold())
	_header.position = Vector2(26, 10)
	_header.size = Vector2(320, 40)
	add_child(_header)
	_free = P.label(Strings.NO_LIMIT, 22, P.ALLOW)
	_free.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_free.position = Vector2(340, 12)
	_free.size = Vector2(size.x - 366, 36)
	add_child(_free)
	var cols := [Table.COL_PROTO, Table.COL_SRC, Table.COL_PORT]
	var names := [Strings.COL_PROTO, Strings.COL_SRC, Strings.COL_PORT]
	for k in 3:
		var col: Vector2 = cols[k]
		var cap := P.label(names[k], 22, P.DIM)
		cap.position = Vector2(col.x, 84)
		cap.size = Vector2(col.y - col.x, 30)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(cap)
		_captions.append(cap)
		var v := P.label("", 40 if k != 1 else 25, P.TEXT, P.mono_bold())
		v.position = Vector2(col.x - 6, 120)
		v.size = Vector2(col.y - col.x + 12, 80)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(v)
		_values.append(v)
	# 列の区切り
	for x: float in [Table.COL_SRC.x, Table.COL_PORT.x]:
		var sep := ColorRect.new()
		sep.color = Color(P.LINE, 0.9)
		sep.position = Vector2(x, 90)
		sep.size = Vector2(2, 120)
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sep)
	_scan = ColorRect.new()
	_scan.color = Color(P.ALLOW, 0.55)
	_scan.size = Vector2(size.x - 8, 3)
	_scan.position = Vector2(4, 0)
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scan)
	_stamp = P.label("", 64, P.TEXT, P.bold())
	_stamp.size = size
	_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stamp.pivot_offset = size / 2.0
	_stamp.visible = false
	add_child(_stamp)


# dims: プロトコル・送信元・ポートの欄のうち、どの行も条件にしていない物(FR-17)
func set_packet(packet: RefCounted, number: int, total: int, timed: bool, dims: Array) -> void:
	_header.text = Strings.CARD_TITLE % [number, total]
	_free.visible = not timed
	_values[0].text = packet.proto.to_upper()
	_values[1].text = Packet.ip_text(packet.src)
	_values[2].text = str(packet.dport)
	for k in 3:
		var a := DIM_ALPHA if dims[k] else 1.0
		_values[k].modulate.a = a
		_captions[k].modulate.a = a
	_stamp.visible = false
	_bg.add_theme_stylebox_override("panel", P.box(P.BG_LIFT, P.ACCENT, 22, 2, 24))


func enter() -> void:
	_kill()
	position = home + Vector2(0, -60)
	modulate.a = 0.0
	scale = Vector2(0.92, 0.92)
	rotation = 0.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "position", home, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_scan.position.y = 0.0
	_scan.modulate.a = 1.0
	var s := _scan.create_tween()
	s.tween_property(_scan, "position:y", HEIGHT - 4.0, 0.35).set_trans(Tween.TRANS_SINE)
	s.tween_property(_scan, "modulate:a", 0.0, 0.1)


# 正解のとき: 答えた側へ飛ばす(通す=右、落とす=左)
func fly(action: String) -> void:
	_kill()
	var dir := 1.0 if action == "allow" else -1.0
	_show_stamp(Strings.ALLOW if action == "allow" else Strings.DROP, P.action_color(action), dir)
	_bg.add_theme_stylebox_override("panel", P.box(P.BG_LIFT, P.action_color(action), 22, 4, 36))
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "position:x", home.x + dir * 820.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "rotation", dir * 0.35, 0.32)
	_tween.tween_property(self, "modulate:a", 0.0, 0.32).set_delay(0.1)


# 不正解のとき: 震えて、正しい答えの印を出す
func reject(expected: String) -> void:
	_kill()
	var c := P.action_color(expected)
	_bg.add_theme_stylebox_override("panel", P.box(Color(P.DROP, 0.12), P.WARN, 22, 4, 30))
	_show_stamp(Strings.MISS, P.WARN, 0.0)
	_tween = create_tween()
	for i in 6:
		var off := 18.0 * (1.0 - i / 6.0) * (1.0 if i % 2 == 0 else -1.0)
		_tween.tween_property(self, "position", home + Vector2(off, 0), 0.04)
	_tween.tween_property(self, "position", home, 0.04)
	_tween.tween_property(self, "rotation", 0.0, 0.01)
	_tween.tween_interval(0.5)
	_tween.tween_property(self, "position:y", home.y + 60.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.25, 0.4)
	_stamp.add_theme_color_override("font_color", c.lerp(P.WARN, 0.5))


func _show_stamp(text: String, color: Color, dir: float) -> void:
	_stamp.text = text
	_stamp.add_theme_color_override("font_color", color)
	_stamp.visible = true
	_stamp.rotation = -0.2 * dir if dir != 0.0 else -0.12
	_stamp.scale = Vector2(1.8, 1.8)
	_stamp.modulate.a = 0.0
	var t := _stamp.create_tween().set_parallel()
	t.tween_property(_stamp, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_stamp, "modulate:a", 1.0, 0.08)


func _kill() -> void:
	if _tween != null:
		_tween.kill()
	_dragging = false


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _dragging:
			_kill()
			_dragging = true
			_drag_start = get_global_mouse_position().x - (position.x - home.x)
			accept_event()
		elif not event.pressed and _dragging:
			release_drag()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var dx := get_global_mouse_position().x - _drag_start
		position = home + Vector2(dx, absf(dx) * 0.05)
		rotation = dx / 1400.0
		drag_changed.emit(clampf(dx / B.SWIPE_PX, -1.0, 1.0))
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT and _dragging:
		release_drag()  # E-5


# 離した: SWIPE_PX 以上なら答え、足りなければ戻す
func release_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	var dx := position.x - home.x
	drag_changed.emit(0.0)
	if absf(dx) >= B.SWIPE_PX:
		swiped.emit("allow" if dx > 0.0 else "drop")
	else:
		_tween = create_tween().set_parallel()
		_tween.tween_property(self, "position", home, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "rotation", 0.0, 0.2)
