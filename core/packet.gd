# パケット 1 枚のデータ(仕様書 §9.3)。IPv4 は 0〜4294967295 の整数で持つ。
# 通すか落とすかは決めない(INV-1。決めるのは evaluator.gd だけ)。
extends RefCounted

var proto: String  # "tcp" / "udp"
var src: int
var dport: int


func _init(p_proto: String = "tcp", p_src: int = 0, p_dport: int = 1) -> void:
	proto = p_proto
	src = p_src
	dport = p_dport


func same_as(other: RefCounted) -> bool:
	return proto == other.proto and src == other.src and dport == other.dport


func _to_string() -> String:
	return "%s %s -> %d" % [proto, ip_text(src), dport]


static func ip(a: int, b: int, c: int, d: int) -> int:
	return (a << 24) | (b << 16) | (c << 8) | d


static func ip_text(value: int) -> String:
	return "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]
