# 図鑑(FR-32)。出会ったポートは番号・名前・説明・出会った回数、まだの物は「??」。重ね方・閉じ方・送り方は実績の一覧と同じ。
extends "res://ui/achievements_screen.gd"

const PortDex := preload("res://core/port_dex.gd")


func _color() -> Color:
	return P.ACCENT


func _title() -> String:
	return Strings.DEX


func _count() -> String:
	return Strings.ACH_COUNT % [PortDex.found(save.dex), PortDex.ENTRIES.size()]


func _fill(list: VBoxContainer) -> void:
	for e: Array in PortDex.ENTRIES:
		var id := str(e[0])
		var seen := PortDex.count(id, save.dex)
		if seen == 0:
			list.add_child(_row(Strings.DEX_UNKNOWN, "", "", false))
			continue
		var info: Array = Strings.DEX_INFO.get(id, [id, ""])
		list.add_child(_row("%s  %s" % [id, info[0]], Strings.DEX_COUNT % seen, str(info[1]), true))
