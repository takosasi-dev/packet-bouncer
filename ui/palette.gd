# 画面の色・フォント・部品の見た目をまとめる。通す=青緑と右、落とす=赤と左(色だけに頼らない。INV-6)。
# フォントは同梱の 2 本だけを使う(INV-4)。等幅は数字・IP・ポート用で、日本語は Noto Sans JP に落とす。
extends RefCounted

const BG := Color("070b14")
const BG_LIFT := Color("0d1424")
const PANEL := Color("0f182a")
const LINE := Color("23324f")
const TEXT := Color("e6f1ff")
const DIM := Color("7b8aa6")
const ALLOW := Color("2ee6b8")
const DROP := Color("ff4d6d")
const WARN := Color("ffb547")
const ACCENT := Color("6c8cff")
const NEW_ROW := Color("ffd166")

const FONT_JP := preload("res://assets/fonts/NotoSansJP-Subset.ttf")
const FONT_MONO_FILE := preload("res://assets/fonts/JetBrainsMono-Subset.ttf")

static var _mono: FontVariation
static var _bold: FontVariation
static var _mono_bold: FontVariation


static func mono() -> Font:
	if _mono == null:
		_mono = FontVariation.new()
		_mono.base_font = FONT_MONO_FILE
		_mono.fallbacks = [FONT_JP]
	return _mono


static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = FONT_JP
		_bold.variation_embolden = 0.9
	return _bold


static func mono_bold() -> Font:
	if _mono_bold == null:
		_mono_bold = FontVariation.new()
		_mono_bold.base_font = mono()
		_mono_bold.variation_embolden = 0.7
	return _mono_bold


static func action_color(action: String) -> Color:
	return ALLOW if action == "allow" else DROP


static func label(text: String, size: int, color: Color = TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(fill: Color, border: Color, radius: int = 14, border_width: int = 2, glow: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if glow > 0.0:
		s.shadow_color = Color(border, 0.45)
		s.shadow_size = int(glow)
	return s


# ネオンの縁取りのボタン。押す・乗る・フォーカスで光が強くなる
static func button(text: String, color: Color, size: int = 34, min_height: int = 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.add_theme_font_override("font", bold())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_stylebox_override("normal", box(Color(color, 0.08), Color(color, 0.7), 18, 2, 6))
	b.add_theme_stylebox_override("hover", box(Color(color, 0.18), color, 18, 3, 16))
	b.add_theme_stylebox_override("focus", box(Color(color, 0.18), TEXT, 18, 3, 16))
	b.add_theme_stylebox_override("pressed", box(color, color, 18, 3, 22))
	b.add_theme_stylebox_override("disabled", box(Color(color, 0.03), Color(color, 0.2), 18, 2))
	return b
