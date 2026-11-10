# 担当 2「続ける」の確かめ: 実績の判定(FR-31)、図鑑の項目が生成で出うる番号と一致すること(FR-32)、
# ランの後の記録(_after_run)、結果画面の連続日数と知らせ、一覧と図鑑の重ね画面が開いて閉じること。
extends "res://tests/suite.gd"

const B := preload("res://core/balance.gd")
const RunState := preload("res://core/run_state.gd")
const SaveStore := preload("res://save/save_store.gd")
const Generator := preload("res://core/generator.gd")
const StageDefs := preload("res://core/stage_defs.gd")
const Rng := preload("res://core/rng.gd")
const Achievements := preload("res://core/achievements.gd")
const PortDex := preload("res://core/port_dex.gd")
const Strings := preload("res://core/strings.gd")
const SAVE_PATH := "user://test_progress_save.json"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _save() -> RefCounted:
	DirAccess.remove_absolute(SAVE_PATH)
	var save: RefCounted = SaveStore.new(SAVE_PATH)
	save.load_data()
	return save


# 終わったランの形だけを作る(進行は回さない)。all = 80 枚に答え終えた
func _rs(mode: String, all: bool, correct: int, max_streak: int, level: String = "normal") -> RefCounted:
	var rs: RefCounted = RunState.new()
	rs.mode = mode
	rs.level = level
	rs.date = "2026-11-10" if mode == "daily" else ""
	rs.charges = B.SKILL_CHARGES.duplicate()
	rs.correct = correct
	rs.max_streak = max_streak
	rs.stage_index = B.STAGES - 1 if all else 2
	for s in B.STAGES:
		rs.grid.append("o".repeat(B.CARDS_PER_STAGE) if all or s < 3 else "-".repeat(B.CARDS_PER_STAGE))
	return rs


func test_achievement_conditions() -> bool:
	var save := _save()
	var met := Achievements.check(_rs("random", false, 25, 12), save)
	expect_eq(met, ["first_run"] as Array[String], "途中で終わったランダム")

	var rs := _rs("daily", true, 80, 80, "hard")
	save.best_by_level = {"easy": 10, "normal": 10, "hard": 10}
	save.streak_last = "2026-11-10"
	save.streak_count = B.DAILY_KEEP  # 7
	met = Achievements.check(rs, save)
	for id: String in ["first_run", "first_daily", "stage8", "all_cards", "fever", "streak_a", "streak_b",
			"rank_s", "no_skill", "hard_all", "all_levels", "daily_a", "daily_b"]:
		expect(id in met, "全部そろったランで %s が無い: %s" % [id, met])
	expect(not "shield_save" in met and not "practice" in met and not "dex_full" in met, "条件を満たさない実績: %s" % [met])

	rs = _rs("random", true, 79, Achievements.STREAK_A - 1)
	rs.skills_used = 1
	rs.charges["shield"] = 0  # 防壁を使い、ミスで外れた
	met = Achievements.check(rs, save)
	expect("shield_save" in met and "fever" in met, "防壁と最大倍率: %s" % [met])
	for id: String in ["rank_s", "no_skill", "hard_all", "streak_a", "first_daily", "daily_a"]:
		expect(not id in met, "79 枚・技あり・ランダムで %s" % id)
	rs.shield_on = true  # 張ったまま終わったら、防いでいない
	expect(not "shield_save" in Achievements.check(rs, save), "張ったままの防壁で防いだことになった")

	save.streak_count = Achievements.DAILY_A - 1
	expect(not "daily_a" in Achievements.check(_rs("daily", false, 3, 3), save), "%d 日で連続日数の実績" % (Achievements.DAILY_A - 1))
	save.best_by_level["easy"] = 0
	expect(not "all_levels" in Achievements.check(rs, save), "やさしいで点が無いのに三つの難易度")
	return true


# 練習は練習と図鑑の実績だけ。80 枚正解・長い連続でも、得点・完走・連続の実績は取らない
func test_practice_is_excluded() -> bool:
	var save := _save()
	var met := Achievements.check(_rs("practice", true, 80, 80), save)
	expect_eq(met, ["practice"] as Array[String], "練習で取れる実績")
	for e: Array in PortDex.ENTRIES:
		save.dex[str(e[1])] = 1
	met = Achievements.check(_rs("practice", true, 80, 80), save)
	expect_eq(met, ["practice", "dex_full"] as Array[String], "練習で図鑑を埋めた")
	return true


# 図鑑の項目 == 生成で出うる番号。候補を作る関数をステージごとに多く回した集合と、本物のランの集合の両方で見る
func test_dex_matches_generator() -> bool:
	var gen_ports := {}
	var rng: RefCounted = Rng.new(12345)
	for run_seed in 4:
		var params := StageDefs.roll_params(Rng.new(run_seed + 1))
		for stage in range(1, B.STAGES + 1):
			var rules := StageDefs.rules_for(stage, params)
			for _i in 3000:
				gen_ports[Generator.candidate(stage, rules, params, rng).dport] = true
	for run_seed in 40:
		var run := Generator.generate_run(run_seed * 7919 + 3)
		if run.has("error"):
			continue
		for st: Dictionary in run["stages"]:
			for card: RefCounted in st["cards"]:
				expect(gen_ports.has(card.dport), "ランに候補に無い番号 %d" % card.dport)
	var dex_ports := {}
	for e: Array in PortDex.ENTRIES:
		for p in range(int(e[1]), int(e[2]) + 1):
			dex_ports[p] = true
	var only_gen := gen_ports.keys().filter(func(p: int) -> bool: return not dex_ports.has(p))
	var only_dex := dex_ports.keys().filter(func(p: int) -> bool: return not gen_ports.has(p))
	expect(only_gen.is_empty(), "図鑑に無いのに出る番号: %s" % [only_gen])
	expect(only_dex.is_empty(), "図鑑にあるのに出ない番号: %s" % [only_dex])
	for e: Array in PortDex.ENTRIES:
		expect(Strings.DEX_INFO.has(str(e[0])), "図鑑の説明が無い: %s" % e[0])
	expect_eq(Strings.DEX_INFO.size(), PortDex.ENTRIES.size(), "説明の数")
	expect_eq(PortDex.id_for(8080), "8080", "8080 は範囲と別の項目")
	expect_eq(PortDex.id_for(8081), "8000-8099", "範囲の中")
	expect_eq(PortDex.count("8000-8099", {"8000": 2, "8080": 5, "8099": 1}), 3, "範囲の回数は 8080 を除いて合計")
	for id: String in Achievements.LIST:
		expect(Strings.ACH.has(id) and not Achievements.desc_of(id).contains("%"), "実績の文言: %s" % id)
	return true


func _new_app() -> Control:
	DirAccess.remove_absolute(SAVE_PATH)
	var app: Control = load("res://ui/app.tscn").instantiate()
	_root().add_child(app)
	_root().get_node("Sfx").enabled = false
	app.save = SaveStore.new(SAVE_PATH)
	app.save.load_data()
	return app


# _after_run が図鑑と実績を保存し、新しく取った物だけを返す。結果画面に連続日数と知らせが出る
func test_after_run_saves_and_returns_new() -> bool:
	var app := _new_app()
	var rs := _rs("random", false, 25, 12)
	rs.ports_seen.assign([80, 80, 22, 8050])
	var fresh: Array = app._after_run(rs)
	expect_eq(fresh, ["first_run"], "初めてのラン")
	var again: RefCounted = SaveStore.new(SAVE_PATH)
	again.load_data()
	expect(again.achievements.has("first_run"), "実績が保存されていない")
	expect_eq(again.dex, {"80": 2, "22": 1, "8050": 1}, "図鑑の保存")
	expect_eq(app._after_run(rs), [], "2 回目は新しい実績が無い")
	expect_eq(app.save.dex["80"], 4, "図鑑の回数が増える")

	app.save.streak_last = Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(Rng.today()) - 86400)
	app.save.streak_count = 2  # 昨日まで 2 日、今日で 3 日
	var daily := _rs("daily", true, 80, 80)
	daily.date = Rng.today()
	daily.ports_seen.assign([443])
	app.finish_run(daily)
	var result: Control = app.stage.get_child(-1)
	expect(result.get_script() == preload("res://ui/result.gd"), "結果画面")
	expect("rank_s" in result.earned and not "first_run" in result.earned, "結果画面の新しい実績: %s" % [result.earned])
	var texts := result.get_children().filter(func(n: Node) -> bool: return n is Label).map(func(l: Label) -> String: return l.text)
	expect(Strings.STREAK % 3 in texts, "結果画面に連続日数が無い: %s" % [texts])
	var toast := result.get_children().filter(func(n: Node) -> bool: return n.get_script() == preload("res://ui/toast.gd"))
	# 知らせは MAX_EACH 個まで 1 つずつ、残りは「ほか N 個」の 1 枚にまとめる
	var each: int = preload("res://ui/toast.gd").MAX_EACH
	var want: int = result.earned.size() if result.earned.size() <= each else each + 1
	expect(toast.size() == 1 and toast[0].texts.size() == want, "知らせが無い")
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)
	return true


func test_lists_open_and_close() -> bool:
	var app := _new_app()
	app.save.achievements["first_run"] = "2026-11-10"
	app.save.dex["80"] = 3
	for which: String in ["achievements", "dex"]:
		var title: Control = app.stage.get_child(-1)
		if which == "achievements":
			app.show_achievements()
		else:
			app.show_dex()
		var screen: Control = app.stage.get_child(-1)
		expect(screen != title and screen._close.has_focus(), "%s: 開いて閉じるボタンにフォーカス" % which)
		var rows: Array = screen._scroll.get_child(0).get_children()
		expect_eq(rows.size(), Achievements.LIST.size() if which == "achievements" else PortDex.ENTRIES.size(), "%s の行の数" % which)
		var all_text := " ".join(_labels(screen))
		if which == "achievements":
			expect(all_text.contains(Strings.ACH_GOT % "2026-11-10") and all_text.contains(Achievements.desc_of("rank_s")), "実績の一覧の中身")
		else:
			expect(all_text.contains("HTTP") and all_text.contains(Strings.DEX_COUNT % 3) and all_text.contains(Strings.DEX_UNKNOWN) and not all_text.contains("SSH"), "図鑑の中身")
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		screen._input(esc)
		expect(screen.is_queued_for_deletion(), "%s: Esc で閉じない" % which)
		app.stage.remove_child(screen)
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)
	return true


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for c in node.get_children():
		if c is Label:
			out.append(c.text)
		out.append_array(_labels(c))
	return out
