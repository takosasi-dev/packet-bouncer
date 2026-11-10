# テストの共通部品。tests/test_*.gd はこれを継承し、失敗を errors に積む。
# expect は条件と、失敗したときに出す文を受ける。
extends RefCounted

var errors: Array[String] = []


func expect(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func expect_eq(actual: Variant, wanted: Variant, label: String) -> void:
	if actual != wanted:
		errors.append("%s: %s のはずが %s" % [label, str(wanted), str(actual)])
