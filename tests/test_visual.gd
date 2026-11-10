# 見た目の確かめ(FR-27 ステージごとの背景・FR-29 共有の画像)。画面の写しはヘッドレスでは撮れないので、
# 切り抜いて PNG にする所だけここで確かめ、撮る所は tests/shoot_web.mjs --play で渡った PNG を見る。
extends "res://tests/suite.gd"

const SaveStore := preload("res://save/save_store.gd")
const ResultScreen := preload("res://ui/result.gd")
const SAVE_PATH := "user://test_visual_save.json"
const PNG_HEAD := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const KEYS := ["grid_color", "glow", "alarm", "pulse"]


func _new_app(low: bool) -> Control:
	DirAccess.remove_absolute(SAVE_PATH)
	var root := (Engine.get_main_loop() as SceneTree).root
	var app: Control = load("res://ui/app.tscn").instantiate()
	root.add_child(app)
	root.get_node("Sfx").enabled = false
	app.save = SaveStore.new(SAVE_PATH)
	app.save.load_data()
	app.save.effects_low = low
	return app


# 切り替えの Tween を終わりまで進めて、背景の今の値を読む
func _settle(app: Control, stage_no: int) -> Dictionary:
	app.set_stage_theme(stage_no)
	app._theme_tween.custom_step(10.0)
	var got := {"floor_speed": app._theme["floor_speed"]}
	for key: String in KEYS:
		got[key] = app._bg_mat.get_shader_parameter(key)
	return got


func _done(app: Control) -> void:
	app.queue_free()
	DirAccess.remove_absolute(SAVE_PATH)


func test_stage_theme_changes_background() -> bool:
	var app := _new_app(false)
	var title := _settle(app, 0)
	var s1 := _settle(app, 1)
	var s4 := _settle(app, 4)
	var s8 := _settle(app, 8)
	expect(s4["grid_color"] != s1["grid_color"], "ステージ 4 は 1 と色が違う")
	expect(s8["grid_color"] != s4["grid_color"], "ステージ 8 は 4 と色が違う")
	expect(s4["floor_speed"] > s1["floor_speed"] and s8["floor_speed"] > s4["floor_speed"], "床はステージが進むと速くなる")
	expect(s8["glow"] > s1["glow"], "ステージ 8 は光が強い")
	expect_eq(s8["alarm"], 1.0, "ステージ 8 は警報の赤")
	expect_eq(s8["pulse"], 1.0, "ステージ 8 は脈打つ")
	expect_eq(s1["alarm"], 0.0, "ステージ 1 は警報なし")
	var back := _settle(app, 0)
	for key: String in back:
		expect_eq(back[key], title[key], "0 で元に戻る: " + key)
	expect_eq(back["grid_color"], Color(0.18, 0.55, 0.80), "0 はシェーダーの既定の色")
	expect_eq(back["floor_speed"], 1.0, "0 は床の速さが元のまま")
	_done(app)
	return true


func test_effects_low_keeps_color_only() -> bool:
	var app := _new_app(true)
	var s1 := _settle(app, 1)
	var s8 := _settle(app, 8)
	expect(s8["grid_color"] != s1["grid_color"], "演出 弱でも色は変わる")
	expect_eq(s8["alarm"], 1.0, "演出 弱でもステージ 8 は赤い")
	expect_eq(s8["pulse"], 0.0, "演出 弱では脈打たない")
	expect_eq(s8["floor_speed"], 1.0, "演出 弱では床の速さを変えない")
	_done(app)
	return true


# 床の速さを変えても進みが飛ばない(上乗せ分を毎フレーム積み上げる)。速さが 1 なら上乗せは増えない
func test_floor_offset_accumulates() -> bool:
	var app := _new_app(false)
	_settle(app, 0)
	app._floor_offset = 0.0
	app._theme_tick(0.1)
	expect_eq(app._floor_offset, 0.0, "速さ 1 では上乗せなし")
	_settle(app, 8)
	app._floor_offset = 0.0
	app._theme_tick(0.1)
	var step: float = app._floor_offset
	expect(step > 0.0 and step < 0.1, "ステージ 8 では少しずつ進む: %f" % step)
	expect_eq(app._bg_mat.get_shader_parameter("floor_offset"), step, "シェーダーに渡る")
	_done(app)
	return true


func test_share_png_crop() -> bool:
	var screen: Control = ResultScreen.new()
	var img := Image.create(540, 960, false, Image.FORMAT_RGB8)
	img.fill(Color(0.03, 0.04, 0.08))
	img.fill_rect(Rect2i(0, 0, 540, 626), Color(0.2, 0.9, 0.7))
	var png: PackedByteArray = screen._crop_png(img, Rect2i(0, 0, 540, 626))
	expect(png.size() > 100, "PNG の大きさが 0 でない: %d" % png.size())
	expect_eq(Array(png.slice(0, 8)), PNG_HEAD, "PNG の頭のバイト")
	var back := Image.new()
	expect_eq(back.load_png_from_buffer(png), OK, "PNG として読める")
	expect_eq(back.get_size(), Vector2i(720, 834), "大きさは 720 × 834 にそろう")
	expect(screen._crop_png(img, Rect2i(600, 0, 50, 50)).is_empty(), "画面の外なら空(文字だけの共有になる)")
	screen.free()
	return true
