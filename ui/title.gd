# タイトル画面(仕様書 FR-2・FR-18): 題名、「今日の検問」「ランダム」「音 入/切」「あそびかた」、自己ベスト、版。
# 題名は色ずれの影を重ねて揺らす。最初のボタンにフォーカスを置き、キーだけでも始められる。
extends Control

const P := preload("res://ui/palette.gd")
const Strings := preload("res://core/strings.gd")
const Rng := preload("res://core/rng.gd")
const B := preload("res://core/balance.gd")

var app: Control
var message := ""  # E-13 などの知らせ
var _logo: Control
var _ghosts: Array[Label] = []
var _sound: Button
var _effects: Button
var _best: Label
var _levels: Dictionary = {}  # 難易度 -> ボタン(FR-20)
var _howto: Control
var _time := 0.0
var _started := false
var _jitter: RefCounted = Rng.new(Rng.fnv1a("title"))


func _ready() -> void:
	_build_logo()

	var tag := P.label(Strings.TAGLINE, 26, P.DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position = Vector2(0, 470)
	tag.size = Vector2(720, 40)
	add_child(tag)

	var menu := VBoxContainer.new()
	menu.position = Vector2(110, 580)
	menu.size = Vector2(500, 0)
	menu.add_theme_constant_override("separation", 16)
	add_child(menu)

	var date := Rng.today()
	var daily := _big_button(Strings.DAILY, _daily_sub(date), P.ALLOW)
	daily.pressed.connect(_go.bind("daily"))
	menu.add_child(daily)
	var random := _big_button(Strings.RANDOM, Strings.RANDOM_SUB, P.ACCENT)
	random.pressed.connect(_go.bind("random"))
	menu.add_child(random)

	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 14)
	menu.add_child(levels)
	for l: String in B.LEVELS:
		var lb := _level_button(l)
		levels.add_child(lb)
		_levels[l] = lb

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	menu.add_child(row)
	_sound = P.button("", P.DIM, 26, 80)
	_sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound.pressed.connect(_toggle_sound)
	row.add_child(_sound)
	_effects = P.button("", P.DIM, 26, 80)
	_effects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects.pressed.connect(_toggle_effects)
	row.add_child(_effects)
	var howto := P.button(Strings.HOWTO, P.DIM, 26, 80)
	howto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	howto.pressed.connect(_toggle_howto)
	row.add_child(howto)
	_update_sound()

	var best := P.label("", 30, P.TEXT, P.mono())
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best.position = Vector2(0, 1150)
	best.size = Vector2(720, 44)
	add_child(best)
	_best = best
	_update_level()

	if message != "":
		var note := P.label(message, 24, P.WARN)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.position = Vector2(0, 1190)
		note.size = Vector2(720, 40)
		add_child(note)

	var version := P.label(Strings.VERSION_FORMAT % ProjectSettings.get_setting("application/config/version"), 22, P.DIM, P.mono())
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.position = Vector2(0, 1232)
	version.size = Vector2(690, 30)
	add_child(version)

	_build_howto()
	daily.grab_focus.call_deferred()
	_intro([tag, menu, best])


func _daily_sub(date: String) -> String:
	var played: int = app.save.daily_attempts(date)
	var sub := Strings.DAILY_SUB % date
	return sub if played == 0 else sub + "  " + Strings.DAILY_PLAYED % (played + 1)


func _big_button(text: String, sub: String, color: Color) -> Button:
	var b := P.button(text, color, 44, 128)
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var s := P.label(sub, 22, Color(P.TEXT, 0.75))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	s.offset_top = -36
	s.offset_bottom = -8
	b.add_child(s)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("h_separation", 0)
	b.add_theme_stylebox_override("normal", P.box(Color(color, 0.10), Color(color, 0.8), 20, 2, 10))
	for state: String in ["normal", "hover", "focus", "pressed", "disabled"]:
		(b.get_theme_stylebox(state) as StyleBoxFlat).content_margin_bottom = 40  # 見出しを上に寄せ、下に説明を置く
	return b


const LEVEL_COLORS := {"easy": P.ALLOW, "normal": P.ACCENT, "hard": P.DROP}


func _level_button(level: String) -> Button:
	var color: Color = LEVEL_COLORS[level]
	var b := P.button(Strings.LEVEL_NAMES[level], color, 26, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := P.label(Strings.LEVEL_SUBS[level], 17, Color(P.TEXT, 0.7))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	s.offset_top = -30
	s.offset_bottom = -6
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(s)
	b.set_meta("base_normal", b.get_theme_stylebox("normal"))
	for state: String in ["normal", "hover", "focus", "pressed"]:
		(b.get_theme_stylebox(state) as StyleBoxFlat).content_margin_bottom = 26
	b.pressed.connect(_pick_level.bind(level))
	return b


func _pick_level(level: String) -> void:
	app.save.set_level(level)
	_update_level()
	Sfx.play("correct")


# 選んでいる難易度だけ塗り、ほかは暗くする。自己ベストはその難易度の物を出す
func _update_level() -> void:
	for l: String in _levels:
		var b: Button = _levels[l]
		var on: bool = l == app.save.level
		var color: Color = LEVEL_COLORS[l]
		var sb: StyleBoxFlat = P.box(Color(color, 0.30), color, 18, 3, 14) if on else b.get_meta("base_normal")
		sb.content_margin_bottom = 26
		b.add_theme_stylebox_override("normal", sb)
		b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
	var best: int = app.save.best_for(app.save.level)
	_best.text = "%s  %s" % [Strings.level_name(app.save.level), Strings.BEST % best]


func _build_logo() -> void:
	_logo = Control.new()
	_logo.position = Vector2(0, 230)
	_logo.size = Vector2(720, 200)
	add_child(_logo)
	for c: Color in [Color(P.ALLOW, 0.7), Color(P.DROP, 0.7), P.TEXT]:
		var l := P.label(Strings.TITLE, 104, c, P.bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(720, 140)
		_logo.add_child(l)
		_ghosts.append(l)
	var product := P.label(Strings.PRODUCT, 38, P.ALLOW, P.mono_bold())
	product.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	product.position = Vector2(0, 150)
	product.size = Vector2(720, 50)
	_logo.add_child(product)
	var bar := ColorRect.new()  # 題名の下を走る光
	bar.color = Color(P.ALLOW, 0.8)
	bar.position = Vector2(160, 212)
	bar.size = Vector2(400, 3)
	_logo.add_child(bar)
	var t := create_tween().set_loops()
	t.tween_property(bar, "modulate:a", 0.15, 1.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(bar, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)


func _intro(nodes: Array) -> void:
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(1.15, 1.15)
	_logo.pivot_offset = Vector2(360, 100)
	var t := create_tween().set_parallel()
	t.tween_property(_logo, "modulate:a", 1.0, 0.5)
	t.tween_property(_logo, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in nodes.size():
		var n: CanvasItem = nodes[i]
		n.modulate.a = 0.0
		var nt := n.create_tween()
		nt.tween_interval(0.25 + i * 0.12)
		nt.tween_property(n, "modulate:a", 1.0, 0.4)


func _process(delta: float) -> void:
	_time += delta
	# 題名の色ずれ: ふだんは小さく揺れ、ときどき大きくずれる
	var burst := 1.0 if fmod(_time, 3.2) < 0.12 else 0.0
	var amp := 2.0 + burst * 12.0
	_ghosts[0].position = Vector2(-amp + _unit() * burst * 6.0, 0)
	_ghosts[1].position = Vector2(amp + _unit() * burst * 6.0, _unit() * burst * 3.0)
	if app != null and app.save.effects_low:
		burst = 0.0
		amp = 2.0
	if burst > 0.0 and app != null:
		app.glitch(0.25)


func _unit() -> float:
	return float(_jitter.next_int(2001)) / 1000.0 - 1.0


func _go(mode: String) -> void:
	if _started:
		return
	_started = true
	Sfx.play("rule_update")
	app.flash(P.ALLOW, 0.6)
	if mode == "daily":
		app.start_daily()
	else:
		app.start_random()


func _toggle_sound() -> void:
	app.set_sound(not app.save.sound_on)
	_update_sound()
	Sfx.play("correct")


func _update_sound() -> void:
	_sound.text = Strings.SOUND_ON if app.save.sound_on else Strings.SOUND_OFF
	_effects.text = Strings.EFFECTS_LOW if app.save.effects_low else Strings.EFFECTS_FULL


func _toggle_effects() -> void:
	app.set_effects_low(not app.save.effects_low)
	_update_sound()
	Sfx.play("correct")


func _build_howto() -> void:
	_howto = Control.new()
	_howto.size = Vector2(720, 1280)
	_howto.visible = false
	add_child(_howto)
	var shade := ColorRect.new()
	shade.color = Color(P.BG, 0.85)
	shade.size = _howto.size
	_howto.add_child(shade)
	var panel := PanelContainer.new()
	var panel_style := P.box(P.PANEL, P.ACCENT, 20, 2, 18)
	panel_style.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2(60, 380)
	panel.size = Vector2(600, 0)
	_howto.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	var head := P.label(Strings.HOWTO, 40, P.ACCENT, P.bold())
	box.add_child(head)
	for i in Strings.HOWTO_LINES.size():
		var l := P.label("%d. %s" % [i + 1, Strings.HOWTO_LINES[i]], 26, P.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(540, 0)
		box.add_child(l)
	var close := P.button(Strings.CLOSE, P.ACCENT, 28, 76)
	close.pressed.connect(_toggle_howto)
	box.add_child(close)


func _toggle_howto() -> void:
	_howto.visible = not _howto.visible
	if _howto.visible:
		(_howto.get_child(1).get_child(0).get_child(-1) as Button).grab_focus()
	Sfx.play("correct")
