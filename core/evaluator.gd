# 「通す・落とす」の正解と決め手の行を決める、ただ 1 つの場所(仕様書 §9.4・INV-1)。
# 上から順に見て、最初に合った行で決まる。どれにも合わなければ落とす(rule_index は -1)。
extends RefCounted


static func evaluate(rules: Array, packet: RefCounted) -> Dictionary:
	for i in rules.size():
		if _matches(rules[i], packet):
			return {"action": rules[i].action, "rule_index": i}
	return {"action": "drop", "rule_index": -1}


# 順序のひっかけ(§9.4): 決め手の行より後ろに、同じパケットに合い、action が違う行がある
static func is_order_trap(rules: Array, packet: RefCounted) -> bool:
	var result := evaluate(rules, packet)
	var index: int = result["rule_index"]
	if index < 0:
		return false
	for j in range(index + 1, rules.size()):
		if rules[j].action != result["action"] and _matches(rules[j], packet):
			return true
	return false


static func _matches(rule: RefCounted, packet: RefCounted) -> bool:
	if rule.proto != "any" and rule.proto != packet.proto:
		return false
	if rule.src_prefix != 0:
		var shift: int = 32 - rule.src_prefix
		if (packet.src >> shift) != (rule.src_net >> shift):
			return false
	match rule.ports["kind"]:
		"list":
			return packet.dport in rule.ports["values"]
		"range":
			return rule.ports["lo"] <= packet.dport and packet.dport <= rule.ports["hi"]
	return true
