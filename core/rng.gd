# ゲームの進行に使う乱数(xorshift32)と、種を作る FNV-1a(仕様書 §9.2・D-8・INV-2)。
# 整数演算だけなので、どの端末でも同じ列になる。見た目の揺れには、進行用とは別のインスタンスを使う。
extends RefCounted

const MASK := 0xFFFFFFFF

var _x: int


func _init(p_seed: int = 1) -> void:
	_x = p_seed & MASK
	if _x == 0:
		_x = 1


func next() -> int:
	_x ^= (_x << 13) & MASK
	_x ^= _x >> 17
	_x ^= (_x << 5) & MASK
	return _x


func next_int(n: int) -> int:
	return next() % n


# 重み付きで 1 つ選ぶ。weights は {名前: 重み}。重み 0 の物は選ばない
func pick_weighted(weights: Dictionary) -> Variant:
	var total := 0
	for w: int in weights.values():
		total += w
	var r := next_int(total)
	for key: Variant in weights:
		r -= weights[key]
		if r < 0:
			return key
	return weights.keys().back()


static func fnv1a(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h ^= b
		h = (h * 16777619) & MASK
	return h


static func daily_seed(date: String) -> int:
	return fnv1a("PB1:" + date)


static func random_seed() -> int:
	return fnv1a("PBR:%d:%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])


# 端末のローカルの日付(D-9)を YYYY-MM-DD で返す
static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
