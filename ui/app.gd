# 画面の土台: 背景のシェーダー、720 × 1280 の舞台(縦横比を保って中央。余白は背景で埋める。FR-19・E-12)、
# 仕上げのシェーダー、タイトル・プレイ・結果の切り替え、保存、画面の揺れと色ずれの演出をまとめる。
# スマホ(タッチ端末)では、横向きのときに縦向きの案内を出し、描画が重ければ仕上げのシェーダーを外す。
extends Control

const P := preload("res://ui/palette.gd")
const Rng := preload("res://core/rng.gd")
const RunState := preload("res://core/run_state.gd")
const SaveStore := preload("res://save/save_store.gd")
const TitleScreen := preload("res://ui/title.gd")
const PlayScreen := preload("res://ui/play.gd")
const ResultScreen := preload("res://ui/result.gd")
const BASE_SIZE := Vector2(720, 1280)
const SHAKE_DECAY := 6.0
const GLITCH_DECAY := 3.5
const FLASH_DECAY := 4.0
const PERF_WINDOW_SEC := 4.0  # タッチ端末で描画の速さを測る長さ
const PERF_MIN_FPS := 40.0  # これより遅ければ仕上げのシェーダーを外す
const VIBRATE_MS := 90
const LOW_FLASH := 0.35  # 「演出 弱」の閃光の強さ
const LOW_BG_SPEED := 0.3  # 「演出 弱」の背景の速さ

var save: RefCounted = SaveStore.new()
var stage: Control  # 画面を置く 720 × 1280 の舞台
var _screen: Control
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _crt_mat: ShaderMaterial
var _crt: ColorRect
var _rotate: Control
var _touch := false
var _perf_time := 0.0
var _perf_frames := 0
var _shake := 0.0
var _glitch := 0.0
var _flash := 0.0
var _bg_flash := 0.0
var _jitter: RefCounted = Rng.new(Rng.fnv1a("jitter"))  # 見た目の揺れ用。進行用の乱数とは別(INV-2)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	save.load_data()
	Sfx.enabled = save.sound_on

	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = preload("res://ui/shaders/background.gdshader")
	_bg.material = _bg_mat
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	stage = Control.new()
	stage.size = BASE_SIZE
	stage.clip_contents = false
	add_child(stage)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_crt = ColorRect.new()
	_crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt_mat = ShaderMaterial.new()
	_crt_mat.shader = preload("res://ui/shaders/crt.gdshader")
	_crt.material = _crt_mat
	layer.add_child(_crt)

	_touch = DisplayServer.is_touchscreen_available()
	_build_rotate_hint()

	_apply_effects()
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_title()


func _layout() -> void:
	var view := get_viewport_rect().size
	_bg_mat.set_shader_parameter("rect_size", view)
	stage.position = ((view - BASE_SIZE) / 2.0).round()
	_rotate.visible = _touch and view.x > view.y


func _process(delta: float) -> void:
	_measure(delta)
	var d := minf(delta, 0.1)
	_shake = maxf(_shake - d * SHAKE_DECAY, 0.0)
	_glitch = maxf(_glitch - d * GLITCH_DECAY, 0.0)
	_flash = maxf(_flash - d * FLASH_DECAY, 0.0)
	_bg_flash = maxf(_bg_flash - d * FLASH_DECAY * 0.5, 0.0)
	var base := ((get_viewport_rect().size - BASE_SIZE) / 2.0).round()
	var amp := _shake * _shake * 22.0
	stage.position = base + Vector2(_jitter_unit(), _jitter_unit()) * amp
	_crt_mat.set_shader_parameter("glitch", _glitch)
	_crt_mat.set_shader_parameter("flash", _flash)
	_bg_mat.set_shader_parameter("flash", _bg_flash)


# タッチ端末で最初の PERF_WINDOW_SEC 秒の速さを測り、遅ければ画面全体の仕上げ(画面の写しを読むシェーダー)を外す
func _measure(delta: float) -> void:
	if not _touch or _perf_time < 0.0:
		return
	_perf_time += delta
	_perf_frames += 1
	if _perf_time >= PERF_WINDOW_SEC:
		if _perf_frames / _perf_time < PERF_MIN_FPS:
			_crt.visible = false
		_perf_time = -1.0  # 測るのは 1 回だけ


func _build_rotate_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)
	_rotate = Control.new()
	_rotate.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rotate.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_rotate)
	var shade := ColorRect.new()
	shade.color = Color(P.BG, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rotate.add_child(shade)
	var l := P.label(preload("res://core/strings.gd").ROTATE_HINT, 64, P.TEXT, P.bold())
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rotate.add_child(l)
	_rotate.visible = false


# 横向きの案内を出している間は、ゲームの時間を止める(play.gd が見る)
func blocked() -> bool:
	return _rotate.visible


# ミスのときの短い振動(音が入のときだけ。Web では navigator.vibrate で、対応していない端末では何も起きない)
func vibrate(ms: int = VIBRATE_MS) -> void:
	if _touch and save.sound_on:
		Input.vibrate_handheld(ms)


func _jitter_unit() -> float:
	return float(_jitter.next_int(2001)) / 1000.0 - 1.0


# 演出: 揺れ・色ずれ・閃光(強さは 0〜1)
# 「演出 弱」では揺れと色ずれを止め、閃光を弱め、背景をゆっくりにする
func shake(strength: float) -> void:
	if not save.effects_low:
		_shake = maxf(_shake, strength)


func glitch(strength: float) -> void:
	if not save.effects_low:
		_glitch = maxf(_glitch, strength)


func flash(color: Color, strength: float) -> void:
	var s := strength * (LOW_FLASH if save.effects_low else 1.0)
	_crt_mat.set_shader_parameter("flash_color", color)
	_flash = maxf(_flash, s)
	_bg_mat.set_shader_parameter("flash_color", color)
	_bg_flash = maxf(_bg_flash, s)


func set_effects_low(low: bool) -> void:
	save.set_effects_low(low)
	_apply_effects()


func _apply_effects() -> void:
	_bg_mat.set_shader_parameter("speed", LOW_BG_SPEED if save.effects_low else 1.0)
	if save.effects_low:
		_shake = 0.0
		_glitch = 0.0


func _swap(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	screen.set("app", self)
	screen.size = BASE_SIZE
	stage.add_child(screen)


func show_title(message: String = "") -> void:
	var title := TitleScreen.new()
	title.message = message
	_swap(title)


func start_daily() -> void:
	var date := Rng.today()
	_start("daily", date, Rng.daily_seed(date), save.level)


func start_random() -> void:
	_start("random", "", Rng.random_seed(), save.level)


# 「もう一度」: 日替わりなら同じ日付の種、ランダムなら新しい種。難易度はそのランの物を引き継ぐ(FR-20)
func retry(rs: RefCounted) -> void:
	if rs.mode == "daily":
		_start("daily", rs.date, Rng.daily_seed(rs.date), rs.level)
	else:
		_start("random", "", Rng.random_seed(), rs.level)


func _start(mode: String, date: String, run_seed: int, level: String) -> void:
	var rs: RefCounted = RunState.new()
	var error: String = rs.start(run_seed, mode, date, level)
	if error != "":
		push_error(error)
		show_title(preload("res://core/strings.gd").GEN_ERROR % run_seed)  # E-13: 得点は保存しない
		return
	var play := PlayScreen.new()
	play.rs = rs
	_swap(play)


# ランが終わったら 1 回呼ぶ(保存して結果画面へ)
func finish_run(rs: RefCounted) -> void:
	var attempts_before: int = save.daily_attempts(rs.date) if rs.mode == "daily" else 0
	var new_best: bool = save.record_run(rs.mode, rs.date, rs.score, rs.correct, rs.stage(), rs.grid, rs.level)
	var result := ResultScreen.new()
	result.rs = rs
	result.attempts_before = attempts_before
	result.new_best = new_best
	_swap(result)


func set_sound(on: bool) -> void:
	save.set_sound(on)
	Sfx.enabled = on
