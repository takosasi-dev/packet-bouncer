# core/ の受け入れ基準 AC-5〜AC-14・AC-17(仕様書 §11)。
# 固定値は仕様書 §9.2・§9.5 に作成者が Python で計算した物。
extends "res://tests/suite.gd"

const B := preload("res://core/balance.gd")
const Rng := preload("res://core/rng.gd")
const Packet := preload("res://core/packet.gd")
const Evaluator := preload("res://core/evaluator.gd")
const StageDefs := preload("res://core/stage_defs.gd")
const Generator := preload("res://core/generator.gd")
const RunState := preload("res://core/run_state.gd")
const ShareText := preload("res://core/share_text.gd")
const SEEDS := 200
const FORBIDDEN := "\\b(randi\\w*|randf\\w*|randomize|RandomNumberGenerator|shuffle|pick_random)\\b"


func _pk(proto: String, a: int, b: int, c: int, d: int, port: int) -> RefCounted:
	return Packet.new(proto, Packet.ip(a, b, c, d), port)


func _rules(ids: Array, params: Dictionary) -> Array:
	return ids.map(func(id: String) -> RefCounted: return StageDefs.make_rule(id, params))


# AC-5
func test_rng_fixed_values() -> bool:
	expect_eq(Rng.fnv1a("a"), 3826002220, "FNV-1a(a)")
	expect_eq(Rng.fnv1a("abc"), 440920331, "FNV-1a(abc)")
	expect_eq(Rng.fnv1a("PB1:2026-11-10"), 1665684503, "FNV-1a(PB1:2026-11-10)")
	var rng := Rng.new(1)
	var got := []
	for _i in 5:
		got.append(rng.next())
	expect_eq(got, [270369, 67634689, 2647435461, 307599695, 2398689233], "xorshift32 種 1")
	expect_eq(Rng.new(0).next(), Rng.new(1).next(), "種 0 は 1 に置き換える")
	return true


# AC-6
func test_evaluate_blk_web_dns() -> bool:
	var rules := _rules(["BLK", "WEB", "DNS"], {"b": 7})
	expect_eq(Evaluator.evaluate(rules, _pk("tcp", 203, 0, 113, 7, 443)), {"action": "drop", "rule_index": 0}, "tcp 203.0.113.7 -> 443")
	expect_eq(Evaluator.evaluate(rules, _pk("tcp", 203, 0, 113, 8, 443)), {"action": "allow", "rule_index": 1}, "tcp 203.0.113.8 -> 443")
	expect_eq(Evaluator.evaluate(rules, _pk("udp", 198, 51, 100, 5, 53)), {"action": "allow", "rule_index": 2}, "udp 198.51.100.5 -> 53")
	expect_eq(Evaluator.evaluate(rules, _pk("tcp", 198, 51, 100, 5, 53)), {"action": "drop", "rule_index": -1}, "tcp 198.51.100.5 -> 53")
	return true


# AC-7・E-16
func test_evaluate_range_and_subnet() -> bool:
	var high := _rules(["HIGH"], {})
	for port: int in [8000, 8099]:
		expect_eq(Evaluator.evaluate(high, _pk("tcp", 198, 51, 100, 5, port))["action"], "allow", "HIGH tcp -> %d" % port)
	for port: int in [7999, 8100]:
		expect_eq(Evaluator.evaluate(high, _pk("tcp", 198, 51, 100, 5, port))["action"], "drop", "HIGH tcp -> %d" % port)
	var ssh := _rules(["SSH"], {"n": 5})
	expect_eq(Evaluator.evaluate(ssh, _pk("tcp", 192, 168, 5, 200, 22))["action"], "allow", "SSH 192.168.5.200")
	expect_eq(Evaluator.evaluate(ssh, _pk("tcp", 192, 168, 6, 200, 22))["action"], "drop", "SSH 192.168.6.200")
	return true


# AC-8
func test_stage_params_fixed_values() -> bool:
	expect_eq(StageDefs.roll_params(Rng.new(Rng.daily_seed("2026-11-10"))), {"P": 80, "b": 70, "n": 161, "v": 155}, "2026-11-10")
	expect_eq(StageDefs.roll_params(Rng.new(Rng.daily_seed("2027-01-01"))), {"P": 443, "b": 229, "n": 125, "v": 191}, "2027-01-01")
	return true


# AC-9
func test_generated_stages_meet_rules() -> bool:
	for run_seed in range(1, SEEDS + 1):
		var made := Generator.generate_run(run_seed)
		if made.has("error"):
			errors.append("種 %d: %s" % [run_seed, made["error"]])
			continue
		for s: Dictionary in made["stages"]:
			var label := "種 %d ステージ %d" % [run_seed, s["stage"]]
			var cards: Array = s["cards"]
			var rules: Array = s["rules"]
			expect_eq(cards.size(), B.CARDS_PER_STAGE, label + " の枚数")
			var allows := 0
			var traps := 0
			var news := 0
			for i in cards.size():
				var c: RefCounted = cards[i]
				var verdict := Evaluator.evaluate(rules, c)
				allows += 1 if verdict["action"] == "allow" else 0
				traps += 1 if Evaluator.is_order_trap(rules, c) else 0
				news += 1 if verdict["rule_index"] in s["new_indices"] else 0
				for j in range(i + 1, cards.size()):
					expect(not c.same_as(cards[j]), "%s: 同じカード %s" % [label, c])
				if s["stage"] <= 2:
					expect_eq(c.proto, "tcp", label + " のプロトコル")
			expect_eq(allows, B.CARDS_PER_STAGE / 2, label + " の通す枚数")
			if s["stage"] >= 4:
				expect(traps >= 2, "%s: 順序のひっかけが %d 枚" % [label, traps])
			if s["stage"] <= 7:
				expect(news >= 2, "%s: 新しい行で決まるカードが %d 枚" % [label, news])
		if errors.size() > 20:
			break  # 出しすぎない
	return true


# AC-10
func test_same_seed_same_cards() -> bool:
	var flat := func(run_seed: int) -> String:
		var out := ""
		for s: Dictionary in Generator.generate_run(run_seed)["stages"]:
			for c: RefCounted in s["cards"]:
				out += str(c) + ";"
		return out
	var a: String = flat.call(12345)
	expect_eq(a.count(";"), B.STAGES * B.CARDS_PER_STAGE, "80 枚")
	expect_eq(flat.call(12345), a, "同じ種で 2 回作った列")
	expect(flat.call(12346) != a, "種を変えても同じ列になった")
	return true


# AC-11
func test_score() -> bool:
	var totals := []
	var total := 0
	for streak in 6:
		total += RunState.score_for(streak, 0.0, 0.0)
		totals.append(total)
	expect_eq(totals, [100, 200, 300, 400, 500, 700], "制限時間なしの 6 連続正解の累計")
	expect_eq(RunState.score_for(0, 8.0, 4.0), 125, "制限 8.0 秒・残り 4.0 秒・連続 0")
	return true


func _new_run() -> RefCounted:
	var rs: RefCounted = RunState.new()
	expect_eq(rs.start(Rng.daily_seed("2026-11-10"), "daily", "2026-11-10"), "", "開始")
	return rs


func _right(rs: RefCounted) -> String:
	return Evaluator.evaluate(rs.rules(), rs.current_card())["action"]


func _wrong(rs: RefCounted) -> String:
	return "drop" if _right(rs) == "allow" else "allow"


# AC-12
func test_lives_end_run_and_time_limits() -> bool:
	var rs := _new_run()
	expect(not rs.dismiss_panel(), "パネルは PANEL_GUARD_SEC より前に閉じない")
	_tick_for(rs, B.PANEL_GUARD_SEC)
	expect(rs.dismiss_panel(), "PANEL_GUARD_SEC 後にパネルを閉じられる")
	for i in B.LIVES:
		expect_eq(rs.phase, RunState.Phase.CARD, "%d 回目の不正解の前" % (i + 1))
		expect(not rs.answer(_wrong(rs))["correct"], "わざと間違えた答えが正解になった")
		expect(rs.answer(_right(rs)).is_empty(), "不正解の表示中の入力を受けた(E-2)")
		_tick_for(rs, B.FEEDBACK_SEC + B.MAX_DELTA)
	expect_eq(rs.lives, 0, "ライフ")
	expect_eq(rs.phase, RunState.Phase.ENDED, "3 回目の不正解でランが終わる")

	rs = _new_run()
	for stage in range(1, B.STAGES + 1):
		_tick_for(rs, B.PANEL_GUARD_SEC)
		rs.dismiss_panel()
		for card in B.CARDS_PER_STAGE:
			var limit: float = 0.0 if card < B.FREE_CARDS else B.TIME_LIMIT_SEC[stage - 1]
			expect_eq(rs.time_limit, limit, "ステージ %d の %d 枚目の制限時間" % [stage, card + 1])
			rs.answer(_right(rs))
	expect_eq(rs.phase, RunState.Phase.ENDED, "80 枚目に答えるとランが終わる")
	expect_eq(rs.correct, B.STAGES * B.CARDS_PER_STAGE, "正解数")
	for row: String in rs.grid:
		expect_eq(row, "o".repeat(B.CARDS_PER_STAGE), "格子の行")

	rs = _new_run()
	_tick_for(rs, B.PANEL_GUARD_SEC)
	rs.dismiss_panel()
	for _i in B.FREE_CARDS:
		rs.answer(_right(rs))
	var streak_before: int = rs.streak
	var results := []
	rs.answered.connect(func(r: Dictionary) -> void: results.append(r))
	_tick_for(rs, B.TIME_LIMIT_SEC[0] + B.MAX_DELTA)
	expect(streak_before > 0, "前提: 連続正解がある")
	expect(results.size() == 1 and results[0]["timeout"], "制限時間を過ぎると時間切れになる")
	expect_eq(rs.lives, B.LIVES - 1, "時間切れでライフ -1")
	expect_eq(rs.streak, 0, "時間切れで連続正解 0")
	return true


# AC-13・INV-3
func test_time_stops_in_panel_and_feedback() -> bool:
	var rs := _new_run()
	rs.tick(5.0)
	expect(is_equal_approx(rs.elapsed, B.MAX_DELTA), "delta 5.0 で進んだ時間が %f" % rs.elapsed)
	_tick_for(rs, B.PANEL_GUARD_SEC)
	rs.dismiss_panel()
	for _i in B.FREE_CARDS:
		rs.answer(_right(rs))
	var limit: float = rs.time_limit
	rs.tick(5.0)
	expect(is_equal_approx(rs.time_left, limit - B.MAX_DELTA), "カードの残り時間が %f(1 回で 0.1 秒だけ減る)" % rs.time_left)
	rs.answer(_wrong(rs))
	var left: float = rs.time_left
	rs.tick(B.MAX_DELTA)
	expect_eq(rs.phase, RunState.Phase.FEEDBACK, "不正解の表示中")
	expect_eq(rs.time_left, left, "不正解の表示中にカードの時間が進んだ")
	return true


# E-14: 同じフレームの時間切れより入力を優先する(answer を tick より先に呼ぶ)
func test_input_before_timeout() -> bool:
	var rs := _new_run()
	_tick_for(rs, B.PANEL_GUARD_SEC)
	rs.dismiss_panel()
	for _i in B.FREE_CARDS:
		rs.answer(_right(rs))
	while rs.time_left > B.MAX_DELTA:
		rs.tick(B.MAX_DELTA)
	var result: Dictionary = rs.answer(_right(rs))
	expect(result.get("correct", false), "時間切れ直前の入力が正解にならない")
	return true


# AC-14
func test_share_text() -> bool:
	var grid := ["oooooooooo", "ooooxooooo", "oooooooooo", "ooxooooooo", "oooooxoooo", "oooooooxoo", "oxooooxooo", "ooxoxoooxo"]
	var text := ShareText.build("daily", "2026-11-10", 0, 6420, 71, 80, 8, grid, "https://example.github.io/packet-bouncer/")
	var wanted := "PacketBouncer 2026-11-10 (初回)\n6420点 / 正解 71/80 / ステージ8\n" + "\n".join(grid) + "\nhttps://example.github.io/packet-bouncer/"
	expect_eq(text, wanted, "§9.9 の例")
	var second := ShareText.build("daily", "2026-11-10", 1, 100, 1, 80, 1, grid, "")
	expect(second.split("\n")[0].ends_with("(2回目)"), "2 回目の 1 行目: " + second.split("\n")[0])
	expect_eq(second.split("\n").size(), 2 + B.STAGES, "SHARE_URL が空のときの行数")
	var random := ShareText.build("random", "", 0, 0, 0, 80, 1, grid, "")
	expect_eq(random.split("\n")[0], "PacketBouncer ランダム", "ランダムの 1 行目")
	var rs := _new_run()
	for row: String in rs.grid:
		expect(row.length() == B.CARDS_PER_STAGE and row.replace("o", "").replace("x", "").replace("-", "") == "", "格子の行: " + row)
	# FR-22: ふつう・技なしは上の形のまま。ほかは 1 行目に難易度、2 行目に技の回数
	var plain := ShareText.build("daily", "2026-11-10", 0, 6420, 71, 80, 8, grid, "https://example.github.io/packet-bouncer/", "normal", 0)
	expect_eq(plain, wanted, "ふつう・技なしは §9.9 の例と同じ")
	var hard := ShareText.build("daily", "2026-11-10", 0, 6420, 71, 80, 8, grid, "", "hard", 3).split("\n")
	expect_eq(hard[0], "PacketBouncer 2026-11-10 (初回) むずかしい", "むずかしいの 1 行目")
	expect_eq(hard[1], "6420点 / 正解 71/80 / ステージ8 / 技 3回", "技ありの 2 行目")
	expect_eq(hard.size(), 2 + B.STAGES, "難易度と技を足しても行数は同じ")
	var easy := ShareText.build("random", "", 0, 0, 0, 80, 1, grid, "", "easy", 0).split("\n")
	expect_eq(easy[0], "PacketBouncer ランダム やさしい", "やさしいの 1 行目")
	return true


# FR-20: 難易度はライフと制限時間だけを変え、カードの列は変えない。知らない値はふつう
func test_levels() -> bool:
	var cards := {}
	for level: String in B.LEVELS + ["nonsense"]:
		var rs: RefCounted = RunState.new()
		rs.start(Rng.daily_seed("2026-11-10"), "daily", "2026-11-10", level)
		var want: String = level if level in B.LEVELS else "normal"
		expect_eq(rs.level, want, "難易度 " + level)
		expect_eq(rs.lives, B.LEVEL_LIVES[want], "%s のライフ" % level)
		cards[level] = str(rs.stage_data()["cards"])
		_tick_for(rs, B.PANEL_GUARD_SEC)
		rs.dismiss_panel()
		for _i in B.FREE_CARDS:
			rs.answer(_right(rs))
		expect(is_equal_approx(rs.time_limit, B.TIME_LIMIT_SEC[0] * B.LEVEL_TIME_SCALE[want]), "%s の制限時間 %f" % [level, rs.time_limit])
	expect(cards["easy"] == cards["normal"] and cards["hard"] == cards["normal"], "難易度でカードの列が変わった")
	expect_eq(B.LEVEL_LIVES["normal"], B.LIVES, "ふつうのライフは追加前と同じ")
	expect_eq(B.LEVEL_TIME_SCALE["normal"], 1.0, "ふつうの倍率は 1.0")
	return true


# FR-25: 練習は制限時間なし・ライフが減らない。FR-24: ミスを記録する。FR-32: 出たポートを記録する
func test_practice_misses_and_ports() -> bool:
	var rs: RefCounted = RunState.new()
	rs.start(Rng.daily_seed("2026-11-10"), "practice")
	var guard := 0
	while rs.phase != RunState.Phase.ENDED and guard < 2000:
		guard += 1
		if rs.phase == RunState.Phase.PANEL:
			_tick_for(rs, B.PANEL_GUARD_SEC)
			rs.dismiss_panel()
		elif rs.phase == RunState.Phase.FEEDBACK:
			rs.tick(B.MAX_DELTA)
		else:
			expect_eq(rs.time_limit, 0.0, "練習の制限時間")
			rs.answer(_wrong(rs) if rs.card_index == 3 else _right(rs))
	expect_eq(rs.phase, RunState.Phase.ENDED, "練習も 80 枚で終わる")
	expect_eq(rs.lives, B.LIVES, "練習ではライフが減らない")
	expect_eq(rs.misses.size(), B.STAGES, "ステージごとに 1 回ずつのミスを記録")
	var m: Dictionary = rs.misses[0]
	expect(m["stage"] == 1 and m["card"] == 3 and m["given"] != m["expected"] and not m["timeout"], "ミスの記録: " + str(m))
	expect_eq(rs.ports_seen.size(), B.STAGES * B.CARDS_PER_STAGE, "出たポートの数")
	expect_eq(rs.ports_seen[0], rs.run["stages"][0]["cards"][0].dport, "最初のポート")
	var share := ShareText.build("practice", "", 0, 0, 0, 80, 8, rs.grid, "")
	expect_eq(share.split("\n")[0], "PacketBouncer 練習", "練習の共有文")
	var daily := ShareText.build("daily", "2026-11-10", 0, 0, 0, 80, 8, rs.grid, "", "normal", 0, 3)
	expect_eq(daily.split("\n")[0], "PacketBouncer 2026-11-10 (初回) 3日連続", "連続日数の共有文")
	expect_eq(ShareText.build("daily", "2026-11-10", 0, 0, 0, 80, 8, rs.grid, "", "normal", 0, 1).split("\n")[0], "PacketBouncer 2026-11-10 (初回)", "1 日目は連続を書かない")
	return true


func test_rank() -> bool:
	var want := {80: "S", 79: "A", 72: "A", 71: "B", 60: "B", 59: "C", 40: "C", 39: "D", 0: "D"}
	for n: int in want:
		expect_eq(RunState.rank_for(n), want[n], "正解 %d のランク" % n)
	return true


# FR-21: 凍結・解析・防壁
func test_skills() -> bool:
	var rs := _new_run()
	expect(not rs.can_use("freeze") and not rs.can_use("scan"), "パネル中は凍結と解析を使えない")
	expect(not rs.use_skill("nonsense"), "知らない技を受けた")
	_tick_for(rs, B.PANEL_GUARD_SEC)
	rs.dismiss_panel()
	expect(not rs.use_skill("freeze"), "制限時間なしのカードで凍結を受けた")
	expect(rs.use_skill("scan"), "解析")
	expect_eq(rs.deciding_row(), Evaluator.evaluate(rs.rules(), rs.current_card())["rule_index"], "解析の行")
	expect(not rs.use_skill("scan"), "1 枚に 2 回目の解析を受けた")
	for _i in B.FREE_CARDS:
		rs.answer(_right(rs))
	expect(rs.can_use("scan"), "次のカードで解析がまた使える")
	# 凍結: 制限時間を何秒過ぎても時間切れにならず、答えると次のカードでは止まっていない
	expect(rs.use_skill("freeze"), "凍結")
	var left: float = rs.time_left
	_tick_for(rs, rs.time_limit * 3.0)
	expect_eq(rs.phase, RunState.Phase.CARD, "凍結中に時間切れになった")
	expect_eq(rs.time_left, left, "凍結中に時間が減った")
	expect(rs.answer(_right(rs))["correct"], "凍結中の正解")
	expect(not rs.frozen, "次のカードまで凍結が残った")
	expect(rs.use_skill("freeze"), "2 回目の凍結")
	rs.answer(_right(rs))
	expect(not rs.can_use("freeze"), "回数を使い切っても凍結できた")
	expect_eq(rs.charges["freeze"], 0, "凍結の残り")
	# 防壁: 次のミスでライフは減らないが、連続正解は 0・格子は x。1 回で消える
	expect(rs.use_skill("shield"), "防壁")
	expect(not rs.use_skill("shield"), "防壁を重ねて張れた")
	var lives: int = rs.lives
	var col: int = rs.card_index
	var r: Dictionary = rs.answer(_wrong(rs))
	expect(r["shielded"] and not r["correct"], "防壁がミスを受けた")
	expect_eq(rs.lives, lives, "防壁でライフが減った")
	expect_eq(rs.streak, 0, "防壁でも連続正解は 0")
	expect_eq(rs.grid[0][col], "x", "防壁でも格子は x")
	_tick_for(rs, B.FEEDBACK_SEC + B.MAX_DELTA)
	rs.answer(_wrong(rs))
	expect_eq(rs.lives, lives - 1, "防壁は 1 回で消える")
	expect_eq(rs.skills_used, 4, "使った回数(解析 1・凍結 2・防壁 1)")
	return true


# AC-17・INV-2
func test_no_engine_random_in_core_and_ui() -> bool:
	var pattern := RegEx.create_from_string(FORBIDDEN)
	var checked := 0
	for dir: String in ["res://core", "res://ui"]:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			checked += 1
			var lines := FileAccess.get_file_as_string(dir.path_join(file)).split("\n")
			for i in lines.size():
				var hit := pattern.search(lines[i])
				if hit:
					errors.append("%s/%s:%d に %s" % [dir, file, i + 1, hit.get_string()])
	expect(checked > 0, "調べたファイルが無い")
	return true


func _tick_for(rs: RefCounted, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		rs.tick(minf(left, B.MAX_DELTA))
		left -= B.MAX_DELTA


# AC-18・INV-4: 自分のスクリプトに外のドメインへの URL が無い(SHARE_URL を除く)
func test_no_external_urls_in_sources() -> bool:
	var url := RegEx.create_from_string("https?://")
	var checked := 0
	for dir: String in ["res://core", "res://ui", "res://ui/shaders", "res://audio", "res://save"]:
		for file: String in DirAccess.get_files_at(dir):
			if not (file.ends_with(".gd") or file.ends_with(".gdshader")):
				continue
			checked += 1
			var lines := FileAccess.get_file_as_string(dir.path_join(file)).split("
")
			for i in lines.size():
				if url.search(lines[i]) and not lines[i].contains("SHARE_URL"):
					errors.append("%s/%s:%d に URL" % [dir, file, i + 1])
	expect(checked > 0, "調べたファイルが無い")
	return true
