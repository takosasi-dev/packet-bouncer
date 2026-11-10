# ルール表の部品(仕様書 §9.1・D-6)。列は #・動作・プロトコル・送信元・宛先ポートで、カードの欄と同じ横位置に並ぶ。
# 最後に既定の行「どれにも合わない → 落とす」を必ず出す。新しい行と、決め手の行(不正解のとき)を光らせる。
extends Control

const P := preload("res://ui/palette.gd")
const Strings := preload("res://core/strings.gd")

const WIDTH := 664.0
const HEADER_H := 40.0
const ROW_H := 54.0
const ROW_GAP := 6.0
# 列の [左端, 右端]。card.gd も同じ値で欄を並べる
const COL_NO := Vector2(0, 44)
const COL_ACTION := Vector2(44, 150)
const COL_PROTO := Vector2(150, 290)
const COL_SRC := Vector2(290, 522)
const COL_PORT := Vector2(522, 664)

var _rows: Array[Panel] = []  # 既定の行を含む
var _pulse: Tween


func _ready() -> void:
	size = Vector2(WIDTH, HEADER_H)
	var heads := [[COL_NO, Strings.COL_NO], [COL_ACTION, Strings.COL_ACTION], [COL_PROTO, Strings.COL_PROTO],
		[COL_SRC, Strings.COL_SRC], [COL_PORT, Strings.COL_PORT]]
	for h: Array in heads:
		add_child(_cell(h[1], h[0], 0.0, HEADER_H, 20, P.DIM))


static func cell_rect(col: Vector2, y: float, h: float) -> Rect2:
	return Rect2(col.x, y, col.y - col.x, h)


func _cell(text: String, col: Vector2, y: float, h: float, font_size: int, color: Color, font: Font = null) -> Label:
	var l := P.label(text, font_size, color, font)
	var r := cell_rect(col, y, h)
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	return l


func row_count() -> int:
	return _rows.size()


func height_for(rule_count: int) -> float:
	return HEADER_H + (rule_count + 1) * (ROW_H + ROW_GAP)


func show_rules(rules: Array, new_indices: Array, animate: bool) -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in rules.size():
		var rule: RefCounted = rules[i]
		var row := _row(i, str(i + 1), rule.action, [rule.proto_text(), rule.src_text(), rule.ports_text()], i in new_indices)
		_rows.append(row)
	_rows.append(_row(rules.size(), "*", "drop", [], false))
	size = Vector2(WIDTH, height_for(rules.size()))
	if animate:
		for i in _rows.size():
			var row := _rows[i]
			row.modulate.a = 0.0
			var x := row.position.x
			row.position.x = x - 40.0
			var t := row.create_tween().set_parallel()
			t.tween_property(row, "modulate:a", 1.0, 0.25).set_delay(i * 0.06)
			t.tween_property(row, "position:x", x, 0.3).set_delay(i * 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _row(index: int, number: String, action: String, cells: Array, is_new: bool) -> Panel:
	var row := Panel.new()
	row.position = Vector2(0, HEADER_H + index * (ROW_H + ROW_GAP))
	row.size = Vector2(WIDTH, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := P.NEW_ROW if is_new else P.LINE
	var style := P.box(Color(P.PANEL, 0.88), border, 10, 2 if is_new else 1, 10.0 if is_new else 0.0)
	row.add_theme_stylebox_override("panel", style)
	row.set_meta("base_style", style)
	add_child(row)
	row.add_child(_cell(number, COL_NO, 0.0, ROW_H, 22, P.DIM, P.mono()))
	var pill := Panel.new()
	var pr := cell_rect(COL_ACTION, 9.0, ROW_H - 18.0).grow_individual(-8, 0, -8, 0)
	pill.position = pr.position
	pill.size = pr.size
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := P.action_color(action)
	pill.add_theme_stylebox_override("panel", P.box(Color(c, 0.18), c, 8, 2))
	row.add_child(pill)
	row.add_child(_cell(Strings.ALLOW if action == "allow" else Strings.DROP, COL_ACTION, 0.0, ROW_H, 22, c, P.bold()))
	if cells.is_empty():  # 既定の行
		var all := Vector2(COL_PROTO.x, COL_PORT.y)
		row.add_child(_cell(Strings.DEFAULT_ROW, all, 0.0, ROW_H, 24, P.DIM))
	else:
		var cols := [COL_PROTO, COL_SRC, COL_PORT]
		for k in 3:
			row.add_child(_cell(cells[k], cols[k], 0.0, ROW_H, 24 if k != 1 else 23, P.TEXT, P.mono()))
	if is_new:
		var tag := P.label(Strings.PANEL_NEW, 16, P.BG, P.bold())
		var tag_bg := Panel.new()
		tag_bg.add_theme_stylebox_override("panel", P.box(P.NEW_ROW, P.NEW_ROW, 6, 1))
		tag_bg.position = Vector2(WIDTH - 92, -15)
		tag_bg.size = Vector2(84, 20)
		tag_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.position = Vector2.ZERO
		tag.size = tag_bg.size
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag_bg.add_child(tag)
		row.add_child(tag_bg)
		var t := row.create_tween().set_loops(4)
		t.tween_property(row, "self_modulate", Color(1.5, 1.4, 1.0), 0.35)
		t.tween_property(row, "self_modulate", Color.WHITE, 0.35)
	return row


# 決め手の行を光らせる(-1 は既定の行)。ほかの行は暗くする
func highlight(rule_index: int) -> void:
	clear_highlight()
	var target: Panel = _rows[rule_index] if rule_index >= 0 else _rows.back()
	for r in _rows:
		r.modulate = Color(1, 1, 1, 0.35) if r != target else Color.WHITE
	var sb := P.box(Color(P.WARN, 0.16), P.WARN, 10, 4, 18)
	target.add_theme_stylebox_override("panel", sb)
	target.pivot_offset = target.size / 2.0
	_pulse = target.create_tween().set_loops()
	_pulse.tween_property(target, "scale", Vector2(1.03, 1.12), 0.18).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(target, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)


func clear_highlight() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	for i in _rows.size():
		var r := _rows[i]
		r.modulate = Color.WHITE
		r.scale = Vector2.ONE
		r.add_theme_stylebox_override("panel", r.get_meta("base_style"))
