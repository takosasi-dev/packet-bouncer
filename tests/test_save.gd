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


# FR-20・FR-22: 難易度と難易度ごとの自己ベスト。古い形(項目が無い)ならふつうの自己ベストとして読む
func test_levels_and_best_by_level() -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{"version": 1, "best_score": 4200, "sound_on": true, "daily": {"2026-11-09": {"attempts": 1, "first_score": 10}}}')
	file.close()
	var store := _fresh()
	expect_eq(store.level, "normal", "古い形の難易度")
	expect_eq(store.best_for("normal"), 4200, "古い形の自己ベストはふつうの物")
	expect_eq(store.best_for("hard"), 0, "古い形のむずかしい")
	expect_eq(store.daily["2026-11-09"]["first_level"], "normal", "古い形の first_level")
	store.set_level("hard")
	expect(store.record_run("daily", "2026-11-10", 900, 9, 1, GRID, "hard"), "むずかしいの初回は自己ベスト")
	store = _fresh()
	expect_eq(store.level, "hard", "難易度を読み直す")
	expect_eq(store.best_for("hard"), 900, "むずかしいの自己ベスト")
	expect_eq(store.best_score, 4200, "ほかの難易度でふつうの自己ベストは変わらない")
	expect_eq(store.daily["2026-11-10"]["first_level"], "hard", "初回の難易度")
	store.set_level("nonsense")
	expect_eq(_fresh().level, "normal", "知らない難易度はふつう")
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{"version": 1, "best_score": 5, "sound_on": true, "level": 3, "best_by_level": {"easy": "x", "hard": 7}, "daily": {}}')
	file.close()
	store = _fresh()
	expect(store.level == "normal" and store.best_for("easy") == 0 and store.best_for("hard") == 7, "型の違う項目は既定値")
	DirAccess.remove_absolute(PATH)
	return true


# FR-23・FR-26・FR-30〜FR-32 の保存(2026-11-10 夜)。連続日数は翌日なら +1、同じ日は数えない、飛んだら 1 から
func test_streak_and_new_fields() -> bool:
	DirAccess.remove_absolute(PATH)
	var store := _fresh()
	expect(not store.tutorial_done and store.bgm_on and store.achievements.is_empty() and store.dex.is_empty(), "新しい項目の既定値")
	expect_eq(SaveStore.next_day("2026-11-30"), "2026-12-01", "月をまたぐ翌日")
	expect_eq(SaveStore.next_day("2026-12-31"), "2027-01-01", "年をまたぐ翌日")
	store.record_run("daily", "2026-11-09", 1, 1, 1, GRID)
	store.record_run("daily", "2026-11-09", 1, 1, 1, GRID)
	expect_eq(store.streak_count, 1, "同じ日の 2 回目は数えない")
	store.record_run("daily", "2026-11-10", 1, 1, 1, GRID)
	expect_eq(_fresh().streak_count, 2, "翌日で 2 日連続(読み直し後)")
	expect_eq(store.current_streak("2026-11-10"), 2, "今日の時点")
	expect_eq(store.current_streak("2026-11-11"), 2, "翌日はまだ続いている")
	expect_eq(store.current_streak("2026-11-12"), 0, "2 日空いたら 0")
	store.record_run("random", "", 1, 1, 1, GRID)
	expect_eq(store.streak_last, "2026-11-10", "ランダムは連続日数に数えない")
	store.record_run("daily", "2026-11-08", 1, 1, 1, GRID)
	expect_eq(store.streak_count, 2, "時計が戻った日付は数えない")
	store.record_run("daily", "2026-11-13", 1, 1, 1, GRID)
	expect_eq(store.streak_count, 1, "間が空いたら 1 から")
	expect(store.unlock("first_clear", "2026-11-13") and not store.unlock("first_clear", "2026-11-14"), "実績は 1 回だけ取れる")
	expect_eq(store.add_ports([80, 443, 80]), [80, 443] as Array[int], "初めて出会ったポート")
	expect_eq(store.add_ports([80, 22]), [22] as Array[int], "2 回目は新しい物だけ")
	store.set_tutorial_done()
	store.set_bgm(false)
	store = _fresh()
	expect(store.tutorial_done and not store.bgm_on, "案内と BGM を読み直す")
	expect_eq(store.achievements.get("first_clear"), "2026-11-13", "実績を読み直す")
	expect_eq(store.dex.get("80"), 3, "図鑑の回数を読み直す")
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{"version": 1, "best_score": 0, "sound_on": true, "daily": {}, "tutorial_done": "yes", "bgm_on": 0, "streak_last": "x", "streak_count": 3, "achievements": {"a": 1, "b": "2026-11-10"}, "dex": {"80": "many", "abc": 2, "22": 4}}')
	file.close()
	store = _fresh()
	expect(not store.tutorial_done and store.bgm_on and store.streak_last == "" and store.streak_count == 0, "型の違う新しい項目は既定値")
	expect(store.achievements.size() == 1 and store.dex.size() == 1 and store.dex.get("22") == 4, "壊れた実績・図鑑は捨てる")
	DirAccess.remove_absolute(PATH)
	return true


func test_broken_file_starts_from_default() -> bool:
	for text: String in ["{ broken", "[1, 2]", '{"version": 2, "best_score": 5, "sound_on": false, "daily": {}}',
			'{"version": "1", "best_score": 5, "sound_on": false, "daily": {}}', '{"version": 1, "best_score": "5", "sound_on": false, "daily": {}}']:
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
