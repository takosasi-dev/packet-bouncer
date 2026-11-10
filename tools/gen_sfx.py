"""効果音 6 つ(5 つ + 技の音)を合成して assets/sfx/ に書く(仕様書 FR-16)。

標準ライブラリだけで作り、乱数を使わないので何度走らせても同じバイト列になる。
16bit PCM・モノラル・44100 Hz、最大音量は約 -3 dBFS、頭と尻に短いフェードを付ける。

    python tools/gen_sfx.py
"""

import math
import struct
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "sfx"
RATE = 44100
PEAK = 10 ** (-3 / 20)  # -3 dBFS
EDGE_FADE = 0.004  # 秒。頭と尻のプチッを消す

# 倍音の並び (倍数, 振幅)。上の倍音を少なくして耳に痛くしない
SINE = [(1, 1.0)]
BELL = [(1, 1.0), (2, 0.25), (3, 0.08)]
TRI = [(1, 1.0), (3, -1 / 9), (5, 1 / 25), (7, -1 / 49)]
BUZZ = [(1, 1.0), (2, 0.35), (3, 0.3), (4, 0.15), (5, 0.12), (7, 0.06)]


def note(f0, dur, harm, f1=None, decay=0.0, attack=0.005, release=0.02, vib=0.0):
    """1 音。f0→f1 へ指数で滑らせ、exp(-decay*t) で減衰させる。vib は揺れの深さ(半音の割合)。"""
    f1 = f0 if f1 is None else f1
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        if vib:
            f *= 2 ** (vib * math.sin(2 * math.pi * 5.5 * t) / 12)
        phase += 2 * math.pi * f / RATE
        s = sum(a * math.sin(k * phase) for k, a in harm if k * f < RATE / 2)
        env = min(1.0, t / attack, (dur - t) / release) * math.exp(-decay * t)
        out.append(s * env)
    return out


def mix(buf, samples, at, gain=1.0):
    start = int(at * RATE)
    need = start + len(samples) - len(buf)
    if need > 0:
        buf.extend([0.0] * need)
    for i, s in enumerate(samples):
        buf[start + i] += s * gain
    return buf


def correct():
    # B5 → E6 の明るい 2 音
    buf = mix([], note(987.77, 0.07, BELL, decay=18), 0.0)
    return mix(buf, note(1318.51, 0.09, BELL, decay=22), 0.06)


def wrong():
    # 低いブザーが 2 段で下がる。倍音は少なめで耳に刺さらない
    buf = mix([], note(233.08, 0.16, BUZZ, f1=207.65, decay=4), 0.0)
    return mix(buf, note(174.61, 0.2, BUZZ, f1=155.56, decay=6), 0.15)


def warn():
    # 柔らかい三角波のピッ・ピッ
    buf = mix([], note(880.0, 0.09, TRI, decay=12), 0.0)
    return mix(buf, note(880.0, 0.09, TRI, decay=12), 0.2)


def rule_update():
    # C5-E5-G5-C6-E6 を駆け上がり、下に上昇スイープを敷く
    buf = mix([], note(261.63, 0.6, TRI, f1=523.25, decay=3, attack=0.05, release=0.15), 0.0, 0.35)
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.51]):
        mix(buf, note(f, 0.18, BELL, decay=10), i * 0.085, 0.6)
    return buf


def skill():
    # 技(FR-21): 上へ滑るきらめきと、E6-B6 の短い 2 音
    buf = mix([], note(659.25, 0.28, SINE, f1=1975.53, decay=6, attack=0.01, release=0.08), 0.0, 0.45)
    mix(buf, note(1318.51, 0.12, BELL, decay=14), 0.05, 0.5)
    return mix(buf, note(1975.53, 0.16, BELL, decay=12), 0.13, 0.45)


def result():
    # G4-C5-E5 の短い前打ちから C メジャーの和音へ解決し、ゆっくり消える
    buf = []
    for i, f in enumerate([392.0, 523.25, 659.25]):
        mix(buf, note(f, 0.12, BELL, decay=12), i * 0.09, 0.7)
    for f, g in [(261.63, 0.5), (523.25, 0.6), (659.25, 0.5), (783.99, 0.5), (1046.5, 0.3)]:
        mix(buf, note(f, 0.93, TRI, decay=2.2, attack=0.01, release=0.3, vib=0.08), 0.27, g)
    return buf


def finish(buf):
    scale = PEAK / max(abs(s) for s in buf)
    n = len(buf)
    edge = int(EDGE_FADE * RATE)
    pcm = []
    for i, s in enumerate(buf):
        fade = min(1.0, i / edge, (n - 1 - i) / edge)
        pcm.append(max(-32768, min(32767, round(s * scale * fade * 32767))))
    return struct.pack("<%dh" % n, *pcm)


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in [("correct", correct), ("wrong", wrong), ("warn", warn),
                       ("rule_update", rule_update), ("result", result), ("skill", skill)]:
        path = OUT / (name + ".wav")
        with wave.open(str(path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(finish(make()))
        print(f"{path.name}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
