# 図鑑(FR-32)の項目。このゲームで出るポートだけ(stage_defs.gd のルール表の番号・範囲、balance.gd の TRAP_PORTS・
# TRAP_PORT_NO_RANGE、generator.gd の範囲の両隣)。8000〜8099 は 1 項目にまとめ、8080 だけ別の項目にする。
# 名前と説明は strings.gd の DEX_INFO(フォントの絞り込みが strings.gd だけを読むため)。
extends RefCounted

# [見出し, 下限, 上限]。上から見て、最初に入った項目にする(8080 を 8000-8099 より先に置く)
const ENTRIES: Array = [
	["21", 21, 21], ["22", 22, 22], ["23", 23, 23], ["25", 25, 25], ["53", 53, 53], ["80", 80, 80], ["443", 443, 443],
	["3389", 3389, 3389], ["7999", 7999, 7999], ["8080", 8080, 8080], ["8000-8099", 8000, 8099], ["8100", 8100, 8100],
	["8443", 8443, 8443],
]


# ポートの項目の見出し。図鑑に無い番号なら ""
static func id_for(port: int) -> String:
	for e: Array in ENTRIES:
		if port >= int(e[1]) and port <= int(e[2]):
			return str(e[0])
	return ""


# 項目に出会った回数(dex はポートの文字列 -> 回数。save_store.gd の dex)
static func count(id: String, dex: Dictionary) -> int:
	var n := 0
	for key: Variant in dex:
		if key is String and key.is_valid_int() and id_for(int(key)) == id and dex[key] is int:
			n += dex[key]
	return n


static func found(dex: Dictionary) -> int:
	return ENTRIES.filter(func(e: Array) -> bool: return count(str(e[0]), dex) > 0).size()
