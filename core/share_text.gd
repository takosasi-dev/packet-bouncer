# 結果の共有テキストを組み立てる(仕様書 §9.9)。絵文字は使わない。
# 日替わりは保存済みの attempts(このランより前に終えた回数)で「(初回)」「(N回目)」を決める。
extends RefCounted

const B := preload("res://core/balance.gd")
const Strings := preload("res://core/strings.gd")


static func build(mode: String, date: String, attempts_before: int, score: int, correct: int, total: int,
		stage: int, grid: Array, share_url: String = B.SHARE_URL, level: String = "normal", skills_used: int = 0, streak: int = 0) -> String:
	var lines: Array[String] = []
	if mode == "daily":
		var nth := Strings.SHARE_FIRST if attempts_before == 0 else Strings.SHARE_NTH % (attempts_before + 1)
		lines.append("%s %s %s" % [Strings.PRODUCT, date, nth])
	else:
		lines.append("%s %s" % [Strings.PRODUCT, Strings.SHARE_RANDOM])
	if level != "normal":  # FR-22: ふつうで技なしなら §9.9 の形のまま
		lines[0] += " " + Strings.level_name(level)
	if mode == "practice":
		lines[0] = "%s %s" % [Strings.PRODUCT, Strings.SHARE_PRACTICE]
	elif mode == "daily" and streak >= 2:  # FR-26
		lines[0] += Strings.SHARE_STREAK % streak
	lines.append(Strings.SHARE_SUMMARY % [score, correct, total, stage])
	if skills_used > 0:
		lines[1] += Strings.SHARE_SKILLS % skills_used
	for row: String in grid:
		lines.append(row)
	if share_url != "":
		lines.append(share_url)
	return "\n".join(lines)
