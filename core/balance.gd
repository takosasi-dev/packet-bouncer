# 調整値(秒数・得点・重み・枚数)を、ここだけに置く(仕様書 §9.7・INV-10)。
# 秒数と重みは仮の値で、§8.2 の観察で決め直す。
extends RefCounted

const LIVES := 3
const STAGES := 8
const CARDS_PER_STAGE := 10  # 変えるなら §9.6 の「5 枚ずつ」も直す
const FREE_CARDS := 2
const TIME_LIMIT_SEC: Array[float] = [8.0, 7.0, 7.0, 7.0, 6.5, 6.0, 6.0, 4.5]
const FEEDBACK_SEC := 1.2
const PANEL_GUARD_SEC := 0.5
const WARN_RATIO := 0.25
const BASE_SCORE := 100
const MULT_STEP := 5
const MULT_MAX := 5
const TIME_BONUS_MAX := 50
const SWIPE_PX := 120.0
const GEN_MAX_TRIES := 2000
const SHARE_URL := "https://takosasi-dev.github.io/packet-bouncer/"
const MAX_DELTA := 0.1  # 1 フレームの delta の上限(INV-3)
const DAILY_KEEP := 7  # 保存する日替わりの件数(§9.8)

# カードの生成(§9.6)
const PROTO_WEIGHTS := {"tcp": 65, "udp": 35}  # ステージ 3 以降
const PORT_WEIGHTS := {"focus": 60, "trap": 40}
const TRAP_PORTS: Array[int] = [8443, 21, 23, 25, 3389]
const TRAP_PORT_NO_RANGE := 8080  # ルール表に range が無い間だけ足す
# 送信元の種類の重み。キーは「このステージ以下で使う」上限のステージ番号
const SRC_WEIGHTS := {
	3: {"EXT": 100, "NETB": 0, "INT": 0, "NEAR": 0},
	4: {"EXT": 40, "NETB": 45, "INT": 15, "NEAR": 0},
	6: {"EXT": 30, "NETB": 30, "INT": 25, "NEAR": 15},
	8: {"EXT": 25, "NETB": 45, "INT": 20, "NEAR": 10},
}
const NETB_WEIGHTS_4_6 := {"exact": 60, "adjacent": 40}
const NETB_WEIGHTS_7_8 := {"exact": 35, "adjacent": 20, "any": 45}
