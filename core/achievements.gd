# 実績(FR-31)。ランの後に run_state と save を見て、条件を満たしている実績の id を返す(取ったかどうかは save.unlock が見る)。
# 練習のランは、練習と図鑑の実績だけに数える(得点・完走・連続の条件には数えない)。名前と条件の説明は strings.gd の ACH。
extends RefCounted

const B := preload("res://core/balance.gd")
const RunState := preload("res://core/run_state.gd")
const PortDex := preload("res://core/port_dex.gd")
const Strings := preload("res://core/strings.gd")

# しきい値(仮の値。担当 2 の調整値はここに置く)
const STREAK_A := 30  # 連続正解
const STREAK_B := 60
const DAILY_A := 3  # 今日の検問の連続日数
const DAILY_B := 7

# 一覧の並び
const LIST: Array[String] = [
	"first_run", "first_daily", "practice", "stage8", "all_cards", "fever", "streak_a", "streak_b",
	"rank_s", "no_skill", "hard_all", "shield_save", "all_levels", "daily_a", "daily_b", "dex_full",
]


# 倍率が最大になる連続正解の数(balance.gd の MULT_STEP・MULT_MAX から)
static func fever_streak() -> int:
	return (B.MULT_MAX - 1) * B.MULT_STEP


# 条件の説明に入れるしきい値(無ければ -1)
static func threshold(id: String) -> int:
	return {"fever": fever_streak(), "streak_a": STREAK_A, "streak_b": STREAK_B, "daily_a": DAILY_A, "daily_b": DAILY_B}.get(id, -1)


# 今、条件を満たしている実績の id(LIST の並び)。save は記録済み(record_run・add_ports の後)のものを渡す
static func check(rs: RefCounted, save: RefCounted) -> Array[String]:
	var met: Array[String] = []
	if PortDex.found(save.dex) == PortDex.ENTRIES.size():
		met.append("dex_full")
	if rs.is_practice():
		met.append("practice")
		return _sorted(met)
	var all_cards: bool = "".join(rs.grid).find("-") == -1
	met.append("first_run")
	if rs.mode == "daily":
		met.append("first_daily")
		var days: int = save.current_streak(rs.date)
		if days >= DAILY_A:
			met.append("daily_a")
		if days >= DAILY_B:
			met.append("daily_b")
	if rs.stage() >= B.STAGES:
		met.append("stage8")
	if all_cards:
		met.append("all_cards")
		if rs.skills_used == 0:
			met.append("no_skill")
		if rs.level == "hard":
			met.append("hard_all")
	if rs.max_streak >= fever_streak():
		met.append("fever")
	if rs.max_streak >= STREAK_A:
		met.append("streak_a")
	if rs.max_streak >= STREAK_B:
		met.append("streak_b")
	if RunState.rank_for(rs.correct) == "S":
		met.append("rank_s")
	# 防壁はミスのときだけ外れるので、使って外れていればミスを防いだ
	if int(rs.charges.get("shield", 0)) < int(B.SKILL_CHARGES["shield"]) and not rs.shield_on:
		met.append("shield_save")
	if B.LEVELS.all(func(l: String) -> bool: return save.best_for(l) > 0):
		met.append("all_levels")
	return _sorted(met)


static func name_of(id: String) -> String:
	return str(Strings.ACH.get(id, [id, ""])[0])


static func desc_of(id: String) -> String:
	var d := str(Strings.ACH.get(id, ["", ""])[1])
	return d % threshold(id) if d.contains("%d") else d


static func _sorted(met: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id in LIST:
		if id in met:
			out.append(id)
	return out
