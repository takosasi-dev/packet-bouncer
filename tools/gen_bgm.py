"""BGM のループ曲を合成して assets/bgm/loop.wav に書く(仕様書 FR-30)。

標準ライブラリだけで作り、乱数を使わないので何度走らせても同じバイト列になる。
16bit PCM・モノラル・22050 Hz(Web の書き出しを軽くする)、最大音量は約 -12 dBFS(効果音 -3 dBFS の下に敷く)。
A マイナー、120 BPM、8 小節(16 秒)。Am F C G | Am F G E を、パッド・8 分のオクターブベース・
16 分のアルペジオ(やまびこ付き)・キック・ハイハットで鳴らす。
尻からはみ出した音は頭に重ねる(輪にして混ぜる)ので、頭と尻の波形がつながり、継ぎ目なくループする。
最後の小節のパッドは尻で消し切り、継ぎ目の前後を静かにする(Web のサンプル再生はループで 10 ms ほど途切れる)。
ステージで速くするのは Godot 側(audio/sfx.gd の pitch_scale)。

    python tools/gen_bgm.py
"""

import math
import struct
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "bgm" / "loop.wav"
RATE = 22050
BPM = 120
BARS = 8
BEAT = 60 / BPM
LENGTH = int(BARS * 4 * BEAT * RATE)  # 352800 サンプル = 16 秒ちょうど
PEAK = 10 ** (-12 / 20)  # -12 dBFS

# 倍音の並び (倍数, 振幅)。上の倍音を少なくして耳に痛くしない
TRI = [(1, 1.0), (3, -1 / 9), (5, 1 / 25)]
BELL = [(1, 1.0), (2, 0.3), (3, 0.1)]
SAW = [(k, 1 / k) for k in range(1, 7)]  # 上を切った鋸波(こもったシンセベース)
METAL = [(1, 1.0), (1.47, 0.8), (1.81, 0.7), (2.27, 0.5)]  # ハイハット用の金属っぽい非整数倍音

# 和音(MIDI 番号)。声部が滑らかにつながるように並べる。最後の E は頭の Am に戻る
CHORDS = [
    (57, 60, 64),  # Am
    (57, 60, 65),  # F
    (55, 60, 64),  # C
    (55, 59, 62),  # G
    (57, 60, 64),  # Am
    (57, 60, 65),  # F
    (55, 59, 62),  # G
    (56, 59, 64),  # E
]
ROOTS = [33, 29, 36, 31, 33, 29, 31, 28]  # ベースの根音(A1 F1 C2 G1 A1 F1 G1 E1)
ARP = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 1, 2, 3]  # 16 分 1 小節の並び(3 以上は 1 オクターブ上)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def note(f0, dur, harm, f1=None, decay=0.0, attack=0.005, release=0.02, detune=0.0):
    """1 音。f0→f1 へ指数で滑らせ、exp(-decay*t) で減衰させる。detune はセントで、2 つ目の発振器をずらす。"""
    f1 = f0 if f1 is None else f1
    n = int(dur * RATE)
    out = []
    phase = 0.0
    phase2 = 0.0
    spread = 2 ** (detune / 1200)
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        phase += 2 * math.pi * f / RATE
        s = sum(a * math.sin(k * phase) for k, a in harm if k * f < RATE / 2)
        if detune:
            phase2 += 2 * math.pi * f * spread / RATE
            s = (s + sum(a * math.sin(k * phase2) for k, a in harm if k * f * spread < RATE / 2)) / 2
        env = min(1.0, t / attack, (dur - t) / release) * math.exp(-decay * t)
        out.append(s * env)
    return out


def mix(buf, samples, at, gain=1.0):
    """輪にして混ぜる: 尻からはみ出た分は頭に足す(ループの継ぎ目が切れない)。"""
    start = int(round(at * RATE))
    for i, s in enumerate(samples):
        buf[(start + i) % LENGTH] += s * gain


def compose():
    buf = [0.0] * LENGTH
    bar = 4 * BEAT
    step = BEAT / 4  # 16 分
    for b in range(BARS):
        t0 = b * bar
        chord = CHORDS[b]
        # パッド: ゆっくり立ち上がる三角波を 2 つずらして重ね、次の小節に少しかぶせる。
        # 最後の小節だけは尻で消し切る(Web はループの頭に戻るとき 10 ms ほど途切れるので、継ぎ目を静かにしておく)
        pad = bar - 0.02 if b == BARS - 1 else bar + 0.3
        for m in chord:
            mix(buf, note(hz(m), pad, TRI, attack=0.35, release=0.45, detune=6), t0, 0.16)
        # ベース: 8 分の刻み。裏で 1 オクターブ上がる
        for k in range(8):
            r = ROOTS[b] + (12 if k % 2 else 0) + 12
            mix(buf, note(hz(r), BEAT / 2 * 0.9, SAW, decay=7, attack=0.004, release=0.03), t0 + k * BEAT / 2, 0.42)
        # アルペジオ: 1 オクターブ上の和音を 16 分で。付点 8 分のやまびこを 2 回
        tones = [m + 12 for m in chord] + [m + 24 for m in chord]
        for k, idx in enumerate(ARP):
            if b % 4 == 3 and k >= 12:
                continue  # 4 小節ごとに尻を空けて息をつく
            n = note(hz(tones[idx]), step * 1.6, BELL, decay=11, attack=0.003, release=0.04)
            at = t0 + k * step
            mix(buf, n, at, 0.11)
            mix(buf, n, at + step * 3, 0.045)
            mix(buf, n, at + step * 6, 0.02)
        # キック: 1・3 拍目(4 小節目と 8 小節目は 4 拍目の裏にもう 1 つ)
        kicks = [0, 2] + ([3.5] if b % 4 == 3 else [])
        for beat in kicks:
            mix(buf, note(120.0, 0.22, [(1, 1.0)], f1=42.0, decay=14, attack=0.002, release=0.03), t0 + beat * BEAT, 0.75)
        # ハイハット: 8 分の裏、4 小節目以降は 16 分も軽く
        for k in range(16):
            if k % 4 == 2:
                g = 0.05
            elif b >= 4 and k % 2 == 1:
                g = 0.018
            else:
                continue
            mix(buf, note(5200.0, 0.06, METAL, decay=70, attack=0.001, release=0.01), t0 + k * step, g)
    return buf


def finish(buf):
    scale = PEAK / max(abs(s) for s in buf)
    pcm = [max(-32768, min(32767, round(s * scale * 32767))) for s in buf]
    return struct.pack("<%dh" % len(pcm), *pcm)


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(finish(compose()))
    print(f"{OUT.name}: {OUT.stat().st_size} bytes, {LENGTH / RATE:.2f} 秒")


if __name__ == "__main__":
    main()
