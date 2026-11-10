# 画面に出す文言を、ここだけに置く(仕様書 INV-5)。
# 同梱フォントはここの全文字を持つ。文言を足したら tools/subset_font.py を流し直す(tests/run_tests.gd が確かめる)。
extends RefCounted

const TITLE := "パケット検問"
const PRODUCT := "PacketBouncer"
const VERSION_FORMAT := "v%s"
