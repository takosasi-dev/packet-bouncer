# 1 ランぶん(8 ステージ × 10 枚)のカードを、種から作る(仕様書 §9.6)。
# 条件(ひっかけ・新しい行・通す 5 落とす 5)は evaluator.gd の結果で見る。生成器は正解の印を付けない(D-7)。
extends RefCounted

const B := preload("res://core/balance.gd")
const Rng := preload("res://core/rng.gd")
const Packet := preload("res://core/packet.gd")
const Evaluator := preload("res://core/evaluator.gd")
const StageDefs := preload("res://core/stage_defs.gd")


# 成功: {seed, params, stages: [{stage, rules, new_indices, cards}...]}
# 失敗(E-13): {error, seed}
static func generate_run(run_seed: int) -> Dictionary:
	var rng := Rng.new(run_seed)
	var params := StageDefs.roll_params(rng)
	var stages := []
	for stage in range(1, B.STAGES + 1):
		var made := generate_stage(stage, params, rng)
		if made.has("error"):
			return {"error": made["error"], "seed": run_seed}
		stages.append(made)
	return {"seed": run_seed, "params": params, "stages": stages}


static func generate_stage(stage: int, params: Dictionary, rng: RefCounted) -> Dictionary:
	var rules := StageDefs.rules_for(stage, params)
	var new_indices := StageDefs.new_indices(stage)
	var cards := []
	var take := func(condition: Callable) -> bool:
		for _try in B.GEN_MAX_TRIES:
			var c := candidate(stage, rules, params, rng)
			if condition.call(c) and not cards.any(func(other: RefCounted) -> bool: return other.same_as(c)):
				cards.append(c)
				return true
		return false
	var fail := {"error": "stage %d: %d 回引き直してもカードがそろわない" % [stage, B.GEN_MAX_TRIES]}

	var picks := 2
	if stage >= 4:
		for _i in picks:
			if not take.call(func(c: RefCounted) -> bool: return Evaluator.is_order_trap(rules, c)):
				return fail
	if not new_indices.is_empty():
		for _i in picks:
			if not take.call(func(c: RefCounted) -> bool: return Evaluator.evaluate(rules, c)["rule_index"] in new_indices):
				return fail
	var half := B.CARDS_PER_STAGE / 2
	while cards.size() < B.CARDS_PER_STAGE:
		var allows := cards.filter(func(c: RefCounted) -> bool: return Evaluator.evaluate(rules, c)["action"] == "allow").size()
		var need := "allow" if allows < half else "drop"
		if not take.call(func(c: RefCounted) -> bool: return Evaluator.evaluate(rules, c)["action"] == need):
			return fail

	for i in range(cards.size() - 1, 0, -1):  # Fisher–Yates
		var j: int = rng.next_int(i + 1)
		var tmp: RefCounted = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
	return {"stage": stage, "rules": rules, "new_indices": new_indices, "cards": cards}


static func candidate(stage: int, rules: Array, params: Dictionary, rng: RefCounted) -> RefCounted:
	var proto: String = "tcp" if stage <= 2 else rng.pick_weighted(B.PROTO_WEIGHTS)
	var src := _pick_src(stage, params, rng)
	var port := _pick_port(rules, rng)
	return Packet.new(proto, src, port)


static func _pick_src(stage: int, params: Dictionary, rng: RefCounted) -> int:
	var weights: Dictionary = {}
	for upto: int in B.SRC_WEIGHTS:
		if stage <= upto:
			weights = B.SRC_WEIGHTS[upto]
			break
	match rng.pick_weighted(weights):
		"EXT":
			var c: int = [Packet.ip(198, 51, 100, 0), Packet.ip(192, 0, 2, 0)][rng.next_int(2)]
			return c + 1 + rng.next_int(254)
		"NETB":
			var early := stage <= 6
			var center: int = params["b"] if early else params["v"]
			match rng.pick_weighted(B.NETB_WEIGHTS_4_6 if early else B.NETB_WEIGHTS_7_8):
				"exact":
					return Packet.ip(203, 0, 113, center)
				"adjacent":
					return Packet.ip(203, 0, 113, _neighbor(center, 2, 254, rng))
			return Packet.ip(203, 0, 113, 1 + rng.next_int(254))
		"INT":
			return Packet.ip(192, 168, params["n"], 1 + rng.next_int(254))
	return Packet.ip(192, 168, _neighbor(params["n"], 1, 254, rng), 1 + rng.next_int(254))  # NEAR


# 隣(c - 1 か c + 1)。範囲を出るときは反対側の隣
static func _neighbor(c: int, lo: int, hi: int, rng: RefCounted) -> int:
	var d := -1 if rng.next_int(2) == 0 else 1
	var x := c + d
	return x if lo <= x and x <= hi else c - d


static func _pick_port(rules: Array, rng: RefCounted) -> int:
	var ports: Array[int] = []
	if rng.pick_weighted(B.PORT_WEIGHTS) == "focus":
		for r: RefCounted in rules:
			if r.ports["kind"] == "list":
				for v: int in r.ports["values"]:
					ports.append(v)
			elif r.ports["kind"] == "range":
				var lo: int = r.ports["lo"]
				var hi: int = r.ports["hi"]
				ports.append_array([lo, hi, lo + 1 + rng.next_int(hi - lo - 1)])
	else:
		ports.append_array(B.TRAP_PORTS)
		var has_range := false
		for r: RefCounted in rules:
			if r.ports["kind"] == "range":
				has_range = true
				ports.append_array([r.ports["lo"] - 1, r.ports["hi"] + 1])
		if not has_range:
			ports.append(B.TRAP_PORT_NO_RANGE)
	var unique: Array[int] = []
	for p in ports:
		if p not in unique:
			unique.append(p)
	unique.sort()
	return unique[rng.next_int(unique.size())]
