# user://save.json の読み書き(仕様書 §9.8)。自己ベスト・音の入/切・日替わりの回数と初回の結果(直近 7 日)。
# 読めない・壊れている・version が 1 でないときは既定値で始める(E-10)。書けなくても止めない(E-9)。
extends RefCounted

const B := preload("res://core/balance.gd")
const VERSION := 1
const DEFAULT_PATH := "user://save.json"

var path: String
var best_score := 0
var sound_on := true
var effects_low := false  # 演出を弱める(揺れ・色ずれを止める)。§9.8 に無い追加の項目で、無ければ false
var daily: Dictionary = {}  # 日付 -> {attempts, first_score, first_correct, first_stage, first_grid}


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


func load_data() -> void:
	best_score = 0
	sound_on = true
	effects_low = false
	daily = {}
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
	for date: Variant in days:
		var d: Variant = days[date]
		if date is String and d is Dictionary and d.get("attempts") is float and d.get("first_score") is float:
			daily[date] = {
				"attempts": int(d["attempts"]), "first_score": int(d["first_score"]),
				"first_correct": int(d.get("first_correct", 0)), "first_stage": int(d.get("first_stage", 0)),
				"first_grid": str(d.get("first_grid", "")),
			}


func save_data() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "best_score": best_score, "sound_on": sound_on, "effects_low": effects_low, "daily": daily}, "  "))
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


# ランを終えたときに 1 回呼ぶ。自己ベストを更新したら true
func record_run(mode: String, date: String, score: int, correct: int, stage: int, grid: Array) -> bool:
	var new_best := score > best_score
	if new_best:
		best_score = score
	if mode == "daily":
		if daily.has(date):
			daily[date]["attempts"] += 1
		else:
			daily[date] = {"attempts": 1, "first_score": score, "first_correct": correct, "first_stage": stage,
				"first_grid": "/".join(grid)}
		var dates := daily.keys()
		dates.sort()
		dates.reverse()
		for old: String in dates.slice(B.DAILY_KEEP):
			daily.erase(old)
	save_data()
	return new_best
