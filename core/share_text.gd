# 結果の共有テキストを組み立てる(仕様書 §9.9)。絵文字は使わない。
# 日替わりは保存済みの attempts(このランより前に終えた回数)で「(初回)」「(N回目)」を決める。
extends RefCounted

const B := preload("res://core/balance.gd")
const Strings := preload("res://core/strings.gd")


static func build(mode: String, date: String, attempts_before: int, score: int, correct: int, total: int,
		stage: int, grid: Array, share_url: String = B.SHARE_URL) -> String:
	var lines: Array[String] = []
	if mode == "daily":
		var nth := Strings.SHARE_FIRST if attempts_before == 0 else Strings.SHARE_NTH % (attempts_before + 1)
		lines.append("%s %s %s" % [Strings.PRODUCT, date, nth])
	else:
		lines.append("%s %s" % [Strings.PRODUCT, Strings.SHARE_RANDOM])
	lines.append(Strings.SHARE_SUMMARY % [score, correct, total, stage])
	for row: String in grid:
		lines.append(row)
	if share_url != "":
		lines.append(share_url)
	return "\n".join(lines)
