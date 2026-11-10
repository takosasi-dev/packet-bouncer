# 画面に出す文言を、ここだけに置く(仕様書 INV-5)。
# 同梱フォントはここの全文字を持つ。文言を足したら tools/subset_font.py を流し直す(tests が確かめる)。
extends RefCounted

const TITLE := "パケット検問"
const PRODUCT := "PacketBouncer"
const VERSION_FORMAT := "v%s"

# タイトル
const TAGLINE := "ファイアウォールになって、パケットを仕分けよう"
const DAILY := "今日の検問"
const DAILY_SUB := "%s の出題 / みんな同じ問題"
const DAILY_PLAYED := "今日 %d 回目"
const RANDOM := "ランダム"
const RANDOM_SUB := "毎回ちがう問題"
const SOUND_ON := "音 入"
const SOUND_OFF := "音 切"
const EFFECTS_FULL := "演出 強"
const EFFECTS_LOW := "演出 弱"
const HOWTO := "あそびかた"
const BEST := "自己ベスト %d"
const HOWTO_LINES: Array[String] = [
	"出てくるパケットを、上のルール表に照らして仕分ける。",
	"表は上から順に見て、最初に合った行で決まる。どれにも合わなければ落とす。",
	"左(← か A)で落とす、右(→ か D)で通す。カードを左右に振ってもよい。下の技は 1・2・3 キーでも使える。",
]
# 難易度(FR-20)。並びは balance.gd の LEVELS と同じ
const LEVEL_NAMES := {"easy": "やさしい", "normal": "ふつう", "hard": "むずかしい"}
const LEVEL_SUBS := {"easy": "ライフ 5 / 時間 長め", "normal": "ライフ 3", "hard": "ライフ 2 / 時間 短め"}
const CLOSE := "閉じる"
const GEN_ERROR := "出題を作れませんでした(種: %d)"
const ROTATE_HINT := "スマホは縦向きで遊んでください"

# ルール表とカード
const ALLOW := "通す"
const DROP := "落とす"
const ANY_PROTO := "すべて"
const ANY_SRC := "どこからでも"
const ANY_PORT := "すべて"
const COL_NO := "#"
const COL_ACTION := "動作"
const COL_PROTO := "プロトコル"
const COL_SRC := "送信元"
const COL_PORT := "宛先ポート"
const DEFAULT_ROW := "どれにも合わない"
const CARD_TITLE := "パケット %d / %d"
const NO_LIMIT := "制限時間なし"

# プレイ
const STAGE := "ステージ %d / %d"
const SCORE := "得点"
const LIVES := "ライフ"
const MULT := "x%d"
const COMBO := "%d 連続"
const GAIN := "+%d"
const BTN_DROP := "← 落とす"
const BTN_ALLOW := "通す →"
const SWIPE_HINT := "カードを左右に振っても答えられる"
const REASON_ROW := "%d 行目で決まり → %s"
const REASON_DEFAULT := "どの行にも合わない → 落とす"
const MISS := "ミス"
const TIMEOUT := "時間切れ"
const PANEL_TITLE := "ルール更新"
const PANEL_STAGE := "ステージ %d"
const PANEL_NEW := "新しい行"
const PANEL_GO := "タップ / Space で開始"
# 技(FR-21)。並びは balance.gd の SKILLS と同じで、キーは 1・2・3
const SKILL_NAMES := {"freeze": "凍結", "scan": "解析", "shield": "防壁"}
const SKILL_SUBS := {"freeze": "時間を止める", "scan": "決め手を光らせる", "shield": "次のミスを防ぐ"}
const SKILL_BUTTON := "%d %s ×%d"
const SHIELD_SAVED := "防壁で ライフ 守った"
const SHIELD_ON := "防壁 展開中"
const FEVER := "最大倍率"
# 一時停止(依頼者の追加 2026-11-10)
const PAUSE_BTN := "II 止める"
const PAUSED := "一時停止"
const RESUME := "つづける"
const RESTART := "はじめから"
const PAUSE_KEYS := "Esc / P で一時停止、Space で再開"
const STAGE_HINTS: Array[String] = [
	"ポートを見る",
	"ポートが 2 つになった",
	"プロトコルも見る",
	"送信元を見る。上の行が先に決まる",
	"送信元の範囲(/24)",
	"ポートの範囲",
	"例外を上に置く",
	"表は同じ。制限時間が短くなる",
]

# 結果
const RESULT_TITLE := "検問終了"
const RESULT_LIVES_OUT := "ライフ切れ"
const RESULT_ALL_DONE := "全 %d 枚 完了"
const R_SCORE := "得点"
const R_CORRECT := "正解"
const R_STREAK := "最大連続"
const R_STAGE := "到達ステージ"
const NEW_BEST := "自己ベスト更新"
const RANK := "ランク"
const COPY := "結果をコピー"
const SEND := "結果を送る"
const COPY_TRIED := "コピーを試しました。貼れないときは下の文字を選んでコピーしてください"
const RETRY := "もう一度"
const TO_TITLE := "タイトルへ"

# 共有テキスト(§9.9)
const SHARE_FIRST := "(初回)"
const SHARE_NTH := "(%d回目)"
const SHARE_RANDOM := "ランダム"
const SHARE_SUMMARY := "%d点 / 正解 %d/%d / ステージ%d"
const SHARE_SKILLS := " / 技 %d回"


# 知らない値でも落ちない(リリース版の Web では辞書の引き損ないが黙って止まる)
static func level_name(level: String) -> String:
	return str(LEVEL_NAMES.get(level, LEVEL_NAMES["normal"]))
