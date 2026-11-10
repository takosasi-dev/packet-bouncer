# 実績の一覧(FR-31)。タイトルの上に重ねる(app.show_achievements が app.stage に足し、閉じたら消える)。
# 取った物は名前と日付、まだの物は条件の説明を薄く。全面の幕で下のボタンを押させず、フォーカスは閉じるボタンから動かさない。
# 閉じるはボタン・Esc・Space(フォーカスのあるボタン)。上下キーで送る。図鑑(dex_screen.gd)はこれを継いで中身だけ変える。
extends Control

const P := preload("res://ui/palette.gd")
const Strings := preload("res://core/strings.gd")
const Achievements := preload("res://core/achievements.gd")
const KEY_SCROLL := 120

var save: RefCounted
var _scroll: ScrollContainer
var _close: Button
var _back_focus: Control


func _ready() -> void:
	size = Vector2(720, 1280)
	_back_focus = get_viewport().gui_get_focus_owner()
	var shade := ColorRect.new()  # 全面で押す操作を受け止める(MOUSE_FILTER_STOP)
	shade.color = Color(P.BG, 0.92)
	shade.size = size
	add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(40, 70)
	panel.size = Vector2(640, 1140)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", P.box(P.PANEL, _color(), 20, 2, 18))
	add_child(panel)
	var head := P.label(_title(), 40, _color(), P.bold())
	head.position = Vector2(72, 96)
	head.size = Vector2(360, 56)
	add_child(head)
	var count := P.label(_count(), 28, P.TEXT, P.mono())
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.position = Vector2(432, 104)
	count.size = Vector2(216, 44)
	add_child(count)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(64, 168)
	_scroll.size = Vector2(592, 906)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 指で送る操作を ScrollContainer に届ける
	list.add_theme_constant_override("separation", 12)
	_scroll.add_child(list)
	_fill(list)

	_close = P.button(Strings.CLOSE, _color(), 30, 84)
	_close.position = Vector2(64, 1100)
	_close.size = Vector2(592, 84)
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_close.set_focus_neighbor(side, NodePath("."))  # 下のタイトルのボタンへフォーカスを逃がさない
	_close.focus_next = NodePath(".")
	_close.focus_previous = NodePath(".")
	_close.pressed.connect(close)
	add_child(_close)
	_close.grab_focus()
	Sfx.play("correct")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_up", true):
		_scroll.scroll_vertical -= KEY_SCROLL
	elif event.is_action_pressed("ui_down", true):
		_scroll.scroll_vertical += KEY_SCROLL
	else:
		return
	get_viewport().set_input_as_handled()


func close() -> void:
	if is_queued_for_deletion():
		return
	queue_free()
	if is_instance_valid(_back_focus) and _back_focus.is_inside_tree():
		_back_focus.grab_focus()
	Sfx.play("correct")


func _color() -> Color:
	return P.NEW_ROW


func _title() -> String:
	return Strings.ACHIEVEMENTS


func _count() -> String:
	return Strings.ACH_COUNT % [Achievements.LIST.filter(func(id: String) -> bool: return save.achievements.has(id)).size(), Achievements.LIST.size()]


func _fill(list: VBoxContainer) -> void:
	for id: String in Achievements.LIST:
		var got: bool = save.achievements.has(id)
		var right: String = Strings.ACH_GOT % str(save.achievements[id]) if got else ""
		list.add_child(_row(Achievements.name_of(id), right, Achievements.desc_of(id), got))


# 1 行: 見出しと右の小さな文字、その下に説明。まだの物は全体を薄く
func _row(title: String, right: String, desc: String, on: bool) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := P.box(Color(P.BG, 0.6), Color(_color(), 0.7) if on else P.LINE, 12, 1)
	style.set_content_margin_all(14)
	row.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var head := P.label(title, 28, _color() if on else P.TEXT, P.bold())
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	if right != "":
		top.add_child(P.label(right, 20, P.DIM, P.mono()))
	if desc != "":
		var d := P.label(desc, 22, P.TEXT if on else P.DIM)
		# Web 版は日本語の区切りの辞書を持たない(空白でしか折れない)ので、どこでも折る
		d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		d.custom_minimum_size = Vector2(540, 0)
		box.add_child(d)
	if not on:
		row.modulate.a = 0.55
	return row
