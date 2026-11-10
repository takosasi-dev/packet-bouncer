# AC-16: 同梱フォントが strings.gd の全文字と ASCII の印字可能文字を持つ(INV-5)。
# 等幅の数字用のフォントは ASCII だけを持てばよい。
extends "res://tests/suite.gd"

const STRINGS_PATH := "res://core/strings.gd"
const FONT_JP := "res://assets/fonts/NotoSansJP-Subset.ttf"
const FONT_MONO := "res://assets/fonts/JetBrainsMono-Subset.ttf"
const ASCII_FIRST := 0x20
const ASCII_LAST := 0x7E


func test_fonts_cover_strings_and_ascii() -> bool:
	var ascii := ""
	for code in range(ASCII_FIRST, ASCII_LAST + 1):
		ascii += char(code)
	var strings_text := ""
	for value: Variant in (load(STRINGS_PATH) as Script).get_script_constant_map().values():
		strings_text += _collect_text(value)
	expect(strings_text != "", "strings.gd から文言を 1 つも読めない")
	_expect_covers(FONT_JP, strings_text + ascii)
	_expect_covers(FONT_MONO, ascii)
	return true


func _expect_covers(path: String, text: String) -> void:
	var font := load(path) as FontFile
	if font == null:
		errors.append("%s を読めない" % path)
		return
	var missing := ""
	for i in text.length():
		if not font.has_char(text.unicode_at(i)) and not missing.contains(text[i]):
			missing += text[i]
	expect(missing == "", "%s に無い文字: %s" % [path.get_file(), missing])


func _collect_text(value: Variant) -> String:
	if value is String:
		return value
	var text := ""
	if value is Array:
		for item: Variant in value:
			text += _collect_text(item)
	elif value is Dictionary:
		for key: Variant in value:
			text += _collect_text(key) + _collect_text(value[key])
	return text
