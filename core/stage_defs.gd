# ステージ 1〜8 のルール表(仕様書 §9.5)。ランの最初に種の乱数から P・b・n・v を引き、行を組み立てる。
# ここにある IP とポートの数は §9.5 が決めた定数。
extends RefCounted

const Rule := preload("res://core/rule.gd")
const Packet := preload("res://core/packet.gd")

# ステージごとの行(上から)と、そのステージで新しい行
const TABLES := [
	["WEB1"],
	["WEB2"],
	["WEB", "DNS"],
	["BLK", "WEB", "DNS"],
	["BLK", "WEB", "DNS", "SSH"],
	["BLK", "WEB", "DNS", "SSH", "HIGH"],
	["EXC", "BLKNET", "WEB", "DNS", "SSH", "HIGH"],
	["EXC", "BLKNET", "WEB", "DNS", "SSH", "HIGH"],
]
const NEW_ROWS := [["WEB1"], ["WEB2"], ["WEB", "DNS"], ["BLK"], ["SSH"], ["HIGH"], ["EXC", "BLKNET"], []]


# 順番は §9.5 のとおり(P → b → n → v。v == b の間は v を引き直す)
static func roll_params(rng: RefCounted) -> Dictionary:
	var p: int = [80, 443][rng.next_int(2)]
	var b: int = 2 + rng.next_int(253)
	var n: int = 1 + rng.next_int(254)
	var v: int = 2 + rng.next_int(253)
	while v == b:
		v = 2 + rng.next_int(253)
	return {"P": p, "b": b, "n": n, "v": v}


static func make_rule(id: String, params: Dictionary) -> RefCounted:
	var any := {"kind": "any"}
	match id:
		"WEB1":
			return Rule.new(id, "allow", "any", 0, 0, {"kind": "list", "values": [params["P"]]})
		"WEB2":
			return Rule.new(id, "allow", "any", 0, 0, {"kind": "list", "values": [80, 443]})
		"WEB":
			return Rule.new(id, "allow", "tcp", 0, 0, {"kind": "list", "values": [80, 443]})
		"DNS":
			return Rule.new(id, "allow", "udp", 0, 0, {"kind": "list", "values": [53]})
		"BLK":
			return Rule.new(id, "drop", "any", Packet.ip(203, 0, 113, params["b"]), 32, any)
		"SSH":
			return Rule.new(id, "allow", "tcp", Packet.ip(192, 168, params["n"], 0), 24, {"kind": "list", "values": [22]})
		"HIGH":
			return Rule.new(id, "allow", "tcp", 0, 0, {"kind": "range", "lo": 8000, "hi": 8099})
		"EXC":
			return Rule.new(id, "allow", "tcp", Packet.ip(203, 0, 113, params["v"]), 32, {"kind": "list", "values": [443]})
		"BLKNET":
			return Rule.new(id, "drop", "any", Packet.ip(203, 0, 113, 0), 24, any)
	push_error("stage_defs: 知らない行 %s" % id)
	return null


# stage は 1 始まり
static func rules_for(stage: int, params: Dictionary) -> Array:
	return TABLES[stage - 1].map(func(id: String) -> RefCounted: return make_rule(id, params))


# 新しい行の、ルール表の中での番号(0 始まり)
static func new_indices(stage: int) -> Array:
	var ids: Array = TABLES[stage - 1]
	return NEW_ROWS[stage - 1].map(func(id: String) -> int: return ids.find(id))
