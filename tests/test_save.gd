# save/ の受け入れ基準 AC-15(仕様書 §9.8・E-10)。
# 本物の save.json に触らないよう、確認用のファイルを使って最後に消す。
extends "res://tests/suite.gd"

const SaveStore := preload("res://save/save_store.gd")
const PATH := "user://test_save.json"
const GRID := ["oooooooooo", "xxx-------"]


func _fresh() -> RefCounted:
	var store: RefCounted = SaveStore.new(PATH)
	store.load_data()
	return store


func test_daily_attempts_and_first_result() -> bool:
	DirAccess.remove_absolute(PATH)
	var store := _fresh()
	expect_eq(store.best_score, 0, "既定の自己ベスト")
	expect(store.record_run("daily", "2026-11-10", 6420, 71, 8, GRID), "初回は自己ベスト")
	store = _fresh()
	expect_eq(store.daily_attempts("2026-11-10"), 1, "1 ラン後の attempts")
	expect_eq(store.daily["2026-11-10"]["first_score"], 6420, "first_score")
	expect_eq(store.daily["2026-11-10"]["first_grid"], "oooooooooo/xxx-------", "first_grid")
	expect(not store.record_run("daily", "2026-11-10", 100, 1, 1, GRID), "低い得点で自己ベスト扱い")
	store = _fresh()
	expect_eq(store.daily_attempts("2026-11-10"), 2, "2 ラン後の attempts")
	expect_eq(store.daily["2026-11-10"]["first_score"], 6420, "2 ラン後も first_score は変わらない")
	expect_eq(store.best_score, 6420, "自己ベスト")
	store.record_run("random", "", 9000, 80, 8, GRID)
	expect_eq(_fresh().daily.size(), 1, "ランダムは日替わりに数えない")
	expect_eq(_fresh().best_score, 9000, "ランダムでも自己ベストは更新")
	DirAccess.remove_absolute(PATH)
	return true


func test_keeps_newest_seven_days() -> bool:
	DirAccess.remove_absolute(PATH)
	var store := _fresh()
	for day in range(1, 9):
		store.record_run("daily", "2026-11-%02d" % day, day, 0, 1, GRID)
	store = _fresh()
	expect_eq(store.daily.size(), 7, "8 日分を入れた後の件数")
	expect(not store.daily.has("2026-11-01") and store.daily.has("2026-11-08"), "古い日付から消える")
	DirAccess.remove_absolute(PATH)
	return true


func test_broken_file_starts_from_default() -> bool:
	for text: String in ["{ broken", "[1, 2]", '{"version": 2, "best_score": 5, "sound_on": false, "daily": {}}']:
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var store := _fresh()
		expect(store.best_score == 0 and store.sound_on and store.daily.is_empty(), "既定値で始まらない: " + text)
	var store := _fresh()
	store.set_sound(false)
	expect(not _fresh().sound_on, "音の切を読み直すと切のまま(AC-22 の前半)")
	DirAccess.remove_absolute(PATH)
	return true
