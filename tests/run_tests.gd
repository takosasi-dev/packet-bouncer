# 自前のテストランナー(仕様書 D-13)。test_ で始まる関数を順に呼び、1 件でも失敗すれば終了コード 1 で終わる。
# 各テストは最後に true を返す。スクリプトエラーで途中で止まったテストも失敗に数える。
# 実行: godot --headless --path . --script res://tests/run_tests.gd(先に godot --headless --path . --import を 1 回)
extends SceneTree

const STRINGS_PATH := "res://core/strings.gd"
const FONT_JP := "res://assets/fonts/NotoSansJP-Subset.ttf"
const FONT_MONO := "res://assets/fonts/JetBrainsMono-Subset.ttf"
const ASCII_FIRST := 0x20  # AC-16 の「ASCII の印字可能文字」の範囲
const ASCII_LAST := 0x7E

var _errors: Array[String] = []


func _initialize() -> void:
	var total := 0
	var failed := 0
	for method: Dictionary in get_method_list():
		var test_name: String = method["name"]
		if not test_name.begins_with("test_"):
			continue
		total += 1
		_errors.clear()
		if call(test_name) != true:
			_errors.append("途中で止まった(スクリプトエラー)")
		if _errors.is_empty():
			print("OK  ", test_name)
		else:
			failed += 1
			print("NG  ", test_name)
			for error in _errors:
				print("      ", error)
	print("%d 件中 %d 件成功、%d 件失敗" % [total, total - failed, failed])
	quit(1 if failed > 0 or total == 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


# AC-16: 同梱フォントが strings.gd の全文字と ASCII の印字可能文字を持つ(INV-5)
func test_fonts_cover_strings_and_ascii() -> bool:
	var ascii := ""
	for code in range(ASCII_FIRST, ASCII_LAST + 1):
		ascii += char(code)
	var strings_text := ""
	for value: Variant in (load(STRINGS_PATH) as Script).get_script_constant_map().values():
		strings_text += _collect_text(value)
	_expect(strings_text != "", "strings.gd から文言を 1 つも読めない")
	_expect_covers(FONT_JP, strings_text + ascii)
	_expect_covers(FONT_MONO, ascii)
	return true


func _expect_covers(path: String, text: String) -> void:
	var font := load(path) as FontFile
	if font == null:
		_errors.append("%s を読めない" % path)
		return
	var missing := ""
	for i in text.length():
		if not font.has_char(text.unicode_at(i)) and not missing.contains(text[i]):
			missing += text[i]
	_expect(missing == "", "%s に無い文字: %s" % [path.get_file(), missing])


# 定数の値から文字列を集める(配列・辞書の中も見る)
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
