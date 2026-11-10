# ルール表の 1 行のデータ(仕様書 §9.3)と、画面に出す文字への変換。
# 行がパケットに合うかは決めない(INV-1。決めるのは evaluator.gd だけ)。
extends RefCounted

const Packet := preload("res://core/packet.gd")
const Strings := preload("res://core/strings.gd")

var id: String  # WEB1・BLK など(§9.5 の行の名前)
var action: String  # "allow" / "drop"
var proto: String  # "any" / "tcp" / "udp"
var src_net: int
var src_prefix: int  # 0 / 24 / 32
var ports: Dictionary  # {kind:"any"} / {kind:"list", values:[...]} / {kind:"range", lo, hi}


func _init(p_id: String, p_action: String, p_proto: String, p_src_net: int, p_src_prefix: int, p_ports: Dictionary) -> void:
	id = p_id
	action = p_action
	proto = p_proto
	src_net = p_src_net
	src_prefix = p_src_prefix
	ports = p_ports


func action_text() -> String:
	return Strings.ALLOW if action == "allow" else Strings.DROP


func proto_text() -> String:
	return Strings.ANY_PROTO if proto == "any" else proto.to_upper()


func src_text() -> String:
	if src_prefix == 0:
		return Strings.ANY_SRC
	if src_prefix == 32:
		return Packet.ip_text(src_net)
	return "%s/%d" % [Packet.ip_text(src_net), src_prefix]


func ports_text() -> String:
	match ports["kind"]:
		"list":
			return ", ".join(ports["values"].map(func(v: int) -> String: return str(v)))
		"range":
			return "%d-%d" % [ports["lo"], ports["hi"]]
	return Strings.ANY_PORT
