# 1 ランの進行(得点・ライフ・連続正解・制限時間・ルール更新のパネル・不正解の一時停止)。画面を知らない。
# 時間は tick(delta) で渡された delta だけで進み、1 回に MAX_DELTA 秒より多くは進まない(INV-3)。
# 入力は tick より先に answer で渡す(同じフレームの時間切れより入力を優先する。E-14)。
extends RefCounted

const B := preload("res://core/balance.gd")
const Evaluator := preload("res://core/evaluator.gd")
const Generator := preload("res://core/generator.gd")

signal stage_started(stage: int)  # ルール更新のパネルを出す
signal card_shown(packet: RefCounted)
signal answered(result: Dictionary)  # {correct, timeout, given, expected, rule_index, gained, multiplier}
signal time_warned
signal ended
signal skill_used(skill: String)

enum Phase { IDLE, PANEL, CARD, FEEDBACK, ENDED }

var phase := Phase.IDLE
var mode := ""  # "daily" / "random"
var level := "normal"  # 難易度(FR-20)
var max_lives := B.LIVES
var date := ""  # 日替わりの日付(開始時の物のまま。E-7)
var charges: Dictionary = {}  # 技 -> 残りの回数(FR-21)
var skills_used := 0
var frozen := false  # 今のカードの制限時間を止めている
var scanned := false  # 今のカードで解析を使った
var shield_on := false  # 次のミスでライフが減らない
var run_seed := 0
var run: Dictionary = {}
var stage_index := 0  # 0 始まり
var card_index := 0
var score := 0
var lives := B.LIVES
var streak := 0
var max_streak := 0
var correct := 0
var grid: Array[String] = []  # 8 行 × 10 文字。o / x / -
var time_limit := 0.0  # 今のカードの制限秒。0 なら制限なし
var time_left := 0.0
var elapsed := 0.0  # ゲーム内の経過時間(進んだ delta の合計)
var _panel_time := 0.0
var _feedback_left := 0.0
var _warned := false


# 成功で "" を、生成に失敗したら(E-13)エラーの文を返す
func start(p_seed: int, p_mode: String, p_date: String = "", p_level: String = "normal") -> String:
	var made := Generator.generate_run(p_seed)
	if made.has("error"):
		phase = Phase.IDLE
		return made["error"]
	run = made
	run_seed = p_seed
	mode = p_mode
	date = p_date
	level = p_level if p_level in B.LEVELS else "normal"
	max_lives = B.LEVEL_LIVES[level]
	charges = B.SKILL_CHARGES.duplicate()
	skills_used = 0
	shield_on = false
	stage_index = 0
	score = 0
	lives = max_lives
	streak = 0
	max_streak = 0
	correct = 0
	elapsed = 0.0
	grid.clear()
	for _s in B.STAGES:
		grid.append("-".repeat(B.CARDS_PER_STAGE))
	_begin_stage()
	return ""


func stage() -> int:
	return stage_index + 1


func stage_data() -> Dictionary:
	return run["stages"][stage_index]


func rules() -> Array:
	return stage_data()["rules"]


func current_card() -> RefCounted:
	return stage_data()["cards"][card_index]


func total_cards() -> int:
	return B.STAGES * B.CARDS_PER_STAGE


func multiplier() -> int:
	return multiplier_for(streak)


func panel_ready() -> bool:
	return phase == Phase.PANEL and _panel_time >= B.PANEL_GUARD_SEC


# ルール更新のパネルを閉じる。PANEL_GUARD_SEC 秒より前は受けない(E-2)
func dismiss_panel() -> bool:
	if not panel_ready():
		return false
	_show_card()
	return true


# 答える。カードを出している間だけ受け、それ以外は捨てる(E-1・E-2)。受けたら結果を返す
func answer(action: String) -> Dictionary:
	if phase != Phase.CARD:
		return {}
	return _resolve(action, false)


func tick(delta: float) -> void:
	var d := clampf(delta, 0.0, B.MAX_DELTA)
	elapsed += d
	match phase:
		Phase.PANEL:
			_panel_time += d
		Phase.FEEDBACK:
			_feedback_left -= d
			if _feedback_left <= 0.0:
				_advance()
		Phase.CARD:
			if time_limit > 0.0 and not frozen:
				time_left = maxf(time_left - d, 0.0)
				if not _warned and time_left < time_limit * B.WARN_RATIO:
					_warned = true
					time_warned.emit()
				if time_left <= 0.0:
					_resolve("", true)


# 技を使えるか(FR-21)。凍結は制限時間のあるカードだけ、凍結と解析は 1 枚に 1 回、防壁は張っていない間
func can_use(skill: String) -> bool:
	if int(charges.get(skill, 0)) <= 0 or phase == Phase.ENDED or phase == Phase.IDLE:
		return false
	match skill:
		"freeze":
			return phase == Phase.CARD and time_limit > 0.0 and not frozen
		"scan":
			return phase == Phase.CARD and not scanned
		"shield":
			return not shield_on
	return false


func use_skill(skill: String) -> bool:
	if not can_use(skill):
		return false
	charges[skill] -= 1
	skills_used += 1
	match skill:
		"freeze":
			frozen = true
		"scan":
			scanned = true
		"shield":
			shield_on = true
	skill_used.emit(skill)
	return true


# 今のカードの決め手の行(-1 は既定の行)
func deciding_row() -> int:
	return Evaluator.evaluate(rules(), current_card())["rule_index"]


static func rank_for(correct_count: int) -> String:
	for r: Array in B.RANKS:
		if correct_count >= int(r[0]):
			return str(r[1])
	return "D"


static func multiplier_for(streak_before: int) -> int:
	return mini(B.MULT_MAX, 1 + streak_before / B.MULT_STEP)


static func score_for(streak_before: int, limit: float, left: float) -> int:
	var bonus := 0
	if limit > 0.0:
		bonus = floori(B.TIME_BONUS_MAX * left / limit)
	return B.BASE_SCORE * multiplier_for(streak_before) + bonus


func _begin_stage() -> void:
	card_index = 0
	_panel_time = 0.0
	phase = Phase.PANEL
	stage_started.emit(stage())


func _show_card() -> void:
	phase = Phase.CARD
	time_limit = 0.0 if card_index < B.FREE_CARDS else B.TIME_LIMIT_SEC[stage_index] * B.LEVEL_TIME_SCALE[level]
	time_left = time_limit
	_warned = false
	frozen = false
	scanned = false
	card_shown.emit(current_card())


func _resolve(given: String, timeout: bool) -> Dictionary:
	var verdict := Evaluator.evaluate(rules(), current_card())
	var ok: bool = not timeout and given == verdict["action"]
	var result := {
		"correct": ok, "timeout": timeout, "given": given, "expected": verdict["action"],
		"rule_index": verdict["rule_index"], "gained": 0, "multiplier": multiplier(), "shielded": false,
	}
	var row := grid[stage_index]
	if ok:
		result["gained"] = score_for(streak, time_limit, time_left)
		score += result["gained"]
		streak += 1
		max_streak = maxi(max_streak, streak)
		correct += 1
		grid[stage_index] = row.substr(0, card_index) + "o" + row.substr(card_index + 1)
		answered.emit(result)
		_advance()
	else:
		if shield_on:  # 防壁: ライフは減らないが、連続正解は 0・格子は x(FR-21)
			shield_on = false
			result["shielded"] = true
		else:
			lives -= 1
		streak = 0
		grid[stage_index] = row.substr(0, card_index) + "x" + row.substr(card_index + 1)
		phase = Phase.FEEDBACK
		_feedback_left = B.FEEDBACK_SEC
		answered.emit(result)
	return result


func _advance() -> void:
	var last_card := card_index + 1 >= B.CARDS_PER_STAGE
	if lives <= 0 or (last_card and stage_index + 1 >= B.STAGES):
		phase = Phase.ENDED
		ended.emit()
	elif last_card:
		stage_index += 1
		_begin_stage()
	else:
		card_index += 1
		_show_card()
