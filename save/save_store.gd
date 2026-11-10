# user://save.json の読み書き(仕様書 §9.8)。自己ベスト・音の入/切・日替わりの回数と初回の結果(直近 7 日)。
# 読めない・壊れている・version が 1 でないときは既定値で始める(E-10)。書けなくても止めない(E-9)。
extends RefCounted

const B := preload("res://core/balance.gd")
const VERSION := 1
const DEFAULT_PATH := "user://save.json"

var path: String
var best_score := 0  # 「ふつう」の自己ベスト(§9.8 の形のまま)
var best_by_level: Dictionary = {}  # 難易度 -> 自己ベスト(FR-22)。normal は best_score と同じ値
var level := "normal"  # 選んでいる難易度(FR-20)
var sound_on := true
var effects_low := false  # 演出を弱める(揺れ・色ずれを止める)。§9.8 に無い追加の項目で、無ければ false
var daily: Dictionary = {}  # 日付 -> {attempts, first_score, first_correct, first_stage, first_grid}
# 2026-11-10 夜の追加(FR-23〜FR-32)。どれも無い・型が違うときは既定値で読む
var tutorial_done := false  # はじめての案内を閉じた(FR-23)
var bgm_on := true  # BGM の入/切(FR-30)。音が切なら鳴らさない
var streak_last := ""  # 今日の検問を最後に終えた日付(FR-26)
var streak_count := 0  # streak_last までの連続日数
var achievements: Dictionary = {}  # 実績の id -> 取った日付(FR-31)
var dex: Dictionary = {}  # ポート番号の文字列 -> 出会った回数(FR-32)


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


func load_data() -> void:
	best_score = 0
	best_by_level = {}
	for l: String in B.LEVELS:
		best_by_level[l] = 0
	level = "normal"
	sound_on = true
	effects_low = false
	daily = {}
	tutorial_done = false
	bgm_on = true
	streak_last = ""
	streak_count = 0
	achievements = {}
	dex = {}
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	# 型を確かめてから比べる(型の違う値どうしの == は実行時エラーになる)
	if not parsed is Dictionary or not parsed.get("version") is float or parsed["version"] != float(VERSION):
		return
	var best: Variant = parsed.get("best_score")
	var sound: Variant = parsed.get("sound_on")
	var days: Variant = parsed.get("daily")
	if not (best is float and sound is bool and days is Dictionary):
		return
	best_score = int(best)
	sound_on = sound
	var low: Variant = parsed.get("effects_low")
	effects_low = low is bool and low
	var lv: Variant = parsed.get("level")
	if lv is String and lv in B.LEVELS:
		level = lv
	var bests: Variant = parsed.get("best_by_level")
	if bests is Dictionary:
		for l: String in B.LEVELS:
			if bests.get(l) is float:
				best_by_level[l] = int(bests[l])
	best_by_level["normal"] = best_score
	var tut: Variant = parsed.get("tutorial_done")
	tutorial_done = tut is bool and tut
	var bgm: Variant = parsed.get("bgm_on")
	bgm_on = not (bgm is bool) or bgm
	var s_last: Variant = parsed.get("streak_last")
	var s_count: Variant = parsed.get("streak_count")
	if s_last is String and _date_ok(s_last) and s_count is float and s_count >= 1.0:
		streak_last = s_last
		streak_count = int(s_count)
	var ach: Variant = parsed.get("achievements")
	if ach is Dictionary:
		for id: Variant in ach:
			if id is String and ach[id] is String:
				achievements[id] = ach[id]
	var seen: Variant = parsed.get("dex")
	if seen is Dictionary:
		for port: Variant in seen:
			if port is String and port.is_valid_int() and seen[port] is float and seen[port] >= 1.0:
				dex[port] = int(seen[port])
	for date: Variant in days:
		var d: Variant = days[date]
		if date is String and d is Dictionary and d.get("attempts") is float and d.get("first_score") is float:
			daily[date] = {
				"attempts": int(d["attempts"]), "first_score": int(d["first_score"]),
				"first_correct": int(d.get("first_correct", 0)), "first_stage": int(d.get("first_stage", 0)),
				"first_grid": str(d.get("first_grid", "")),
				"first_level": d["first_level"] if d.get("first_level") is String and d["first_level"] in B.LEVELS else "normal",
			}


func save_data() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "best_score": best_score, "best_by_level": best_by_level, "level": level,
		"sound_on": sound_on, "effects_low": effects_low, "daily": daily,
		"tutorial_done": tutorial_done, "bgm_on": bgm_on, "streak_last": streak_last, "streak_count": streak_count,
		"achievements": achievements, "dex": dex}, "  "))
	file.close()
	return true


func daily_attempts(date: String) -> int:
	return daily[date]["attempts"] if daily.has(date) else 0


func set_sound(on: bool) -> void:
	sound_on = on
	save_data()


func set_effects_low(low: bool) -> void:
	effects_low = low
	save_data()


func set_level(p_level: String) -> void:
	level = p_level if p_level in B.LEVELS else "normal"
	save_data()


func set_tutorial_done() -> void:
	tutorial_done = true
	save_data()


func set_bgm(on: bool) -> void:
	bgm_on = on
	save_data()


# 今日の時点の連続日数(FR-26)。最後に遊んだのが今日か昨日なら続いている、それより前なら 0
func current_streak(today: String) -> int:
	if streak_last == "" or not _date_ok(today):
		return 0
	return streak_count if streak_last == today or next_day(streak_last) == today else 0


# 実績を取る(FR-31)。新しく取ったら true(保存は呼ぶ側が save_data でまとめて)
func unlock(id: String, date: String) -> bool:
	if achievements.has(id):
		return false
	achievements[id] = date
	return true


# 出会ったポートを数える(FR-32)。初めて出会ったポートを返す(保存は呼ぶ側)
func add_ports(ports: Array) -> Array[int]:
	var fresh: Array[int] = []
	for port: int in ports:
		var key := str(port)
		if not dex.has(key):
			fresh.append(port)
			dex[key] = 0
		dex[key] += 1
	return fresh


static func next_day(date: String) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(date) + 86400)


static func _date_ok(date: String) -> bool:
	return RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(date) != null


func best_for(p_level: String) -> int:
	return int(best_by_level.get(p_level, 0))


# ランを終えたときに 1 回呼ぶ。その難易度の自己ベストを更新したら true
func record_run(mode: String, date: String, score: int, correct: int, stage: int, grid: Array, p_level: String = "normal") -> bool:
	var new_best := score > best_for(p_level)
	if new_best:
		best_by_level[p_level] = score
		if p_level == "normal":
			best_score = score
	if mode == "daily":
		if daily.has(date):
			daily[date]["attempts"] += 1
		else:
			daily[date] = {"attempts": 1, "first_score": score, "first_correct": correct, "first_stage": stage,
				"first_grid": "/".join(grid), "first_level": p_level}
		# 連続日数(FR-26): 同じ日は数えない、翌日なら +1、間が空いたら 1 から。時計が戻った日付は無視
		if date != streak_last and date > streak_last:
			streak_count = streak_count + 1 if streak_last != "" and next_day(streak_last) == date else 1
			streak_last = date
		var dates := daily.keys()
		dates.sort()
		dates.reverse()
		for old: String in dates.slice(B.DAILY_KEEP):
			daily.erase(old)
	save_data()
	return new_best
