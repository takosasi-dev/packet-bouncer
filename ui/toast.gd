# 実績を取った知らせ(FR-31)。画面の上に「実績 ○○」を 1 つずつ数秒出して消し、全部出したら自分を消す。押す操作は奪わない。
extends Control

const P := preload("res://ui/palette.gd")
const SHOW_SEC := 1.8
const FADE_SEC := 0.25
const MAX_EACH := 2  # これより多く取ったら、残りは「ほか N 個」の 1 枚にまとめる(見出しに長く重ならないように)

var texts: Array = []


func _init(p_texts: Array = []) -> void:
	texts = p_texts.slice(0, MAX_EACH)
	if p_texts.size() > MAX_EACH:
		texts.append(preload("res://core/strings.gd").ACH_MORE % (p_texts.size() - MAX_EACH))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(60, 20)
	size = Vector2(600, 80)
	var panel := Panel.new()
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", P.box(Color(P.PANEL, 0.96), P.NEW_ROW, 16, 2, 14))
	add_child(panel)
	var label := P.label("", 30, P.NEW_ROW, P.bold())
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(label)
	modulate.a = 0.0
	var t := create_tween()
	for text: Variant in texts:
		t.tween_callback(func() -> void: label.text = str(text))
		t.tween_property(self, "modulate:a", 1.0, FADE_SEC)
		t.tween_interval(SHOW_SEC)
		t.tween_property(self, "modulate:a", 0.0, FADE_SEC)
	t.tween_callback(queue_free)
