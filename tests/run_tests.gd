# 自前のテストランナー(仕様書 D-13)。tests/test_*.gd の test_ で始まる関数を順に呼び、1 件でも失敗すれば終了コード 1。
# 各テストは最後に true を返す。スクリプトエラーで途中で止まったテストも失敗に数える。
# 実行: godot --headless --path . --script res://tests/run_tests.gd(先に godot --headless --path . --import を 1 回)
extends SceneTree

const DIR := "res://tests"


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだ動いておらず、画面のテストで _ready が走らない


func _run() -> void:
	var total := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(DIR)).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	var only := Array(OS.get_cmdline_user_args())  # 例: -- test_ui で、そのファイルだけ回す
	if not only.is_empty():
		files = files.filter(func(f: String) -> bool: return only.any(func(o: String) -> bool: return f.begins_with(o)))
	for file: String in files:
		var script := load(DIR.path_join(file)) as Script
		if script == null or not script.can_instantiate():  # 構文エラー。ここで止まると quit に届かず終わらない
			total += 1
			failed += 1
			print("NG  %s を読めない(構文エラー)" % file)
			continue
		var suite: RefCounted = script.new()
		for method: Dictionary in suite.get_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			total += 1
			suite.errors.clear()
			if suite.call(test_name) != true:
				suite.errors.append("途中で止まった(スクリプトエラー)")
			if suite.errors.is_empty():
				print("OK  %s %s" % [file.get_basename(), test_name])
			else:
				failed += 1
				print("NG  %s %s" % [file.get_basename(), test_name])
				for error: String in suite.errors:
					print("      ", error)
	print("%d 件中 %d 件成功、%d 件失敗" % [total, total - failed, failed])
	quit(1 if failed > 0 or total == 0 else 0)
