"""同梱フォントを、画面に出す文字だけに絞る(仕様書 D-15・INV-5)。

core/strings.gd の文字列リテラルの全文字と ASCII の印字可能文字(0x20〜0x7E)を集め、原本を太さ 400 に固定してから絞り、
assets/fonts/ に書く。等幅の数字用(JetBrains Mono)は ASCII だけを持たせる。ライセンスの原文も同じ所に置く。
原本は google/fonts の固定コミットから取り、sha256 を照合する。tools/font_src/ に置き、git には入れない。

    pip install fonttools
    python tools/subset_font.py
"""

import hashlib
import re
import sys
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "font_src"
OUT = ROOT / "assets" / "fonts"
GF = "https://raw.githubusercontent.com/google/fonts/5bb28733cec313b63fbd415b574b5ae35c8aa8b8/ofl/"
WEIGHT = 400
ASCII = "".join(chr(c) for c in range(0x20, 0x7F))

# (原本の URL, 原本の sha256, ライセンスの URL, 書き出す名前, strings.gd の文字も入れるか)
FONTS = [
    (GF + "notosansjp/NotoSansJP%5Bwght%5D.ttf",
     "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f",
     GF + "notosansjp/OFL.txt", "NotoSansJP", True),
    (GF + "jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf",
     "48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda",
     GF + "jetbrainsmono/OFL.txt", "JetBrainsMono", False),
]


def fetch(url: str, dest: Path) -> Path:
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        print(f"取得: {url}")
        urllib.request.urlretrieve(url, dest)
    return dest


def strings_chars() -> set[str]:
    text = (ROOT / "core" / "strings.gd").read_text(encoding="utf-8")
    return set("".join(re.findall(r'"((?:[^"\\\n]|\\.)*)"', text)))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)
    for font_url, sha, license_url, name, with_strings in FONTS:
        src = fetch(font_url, SRC / f"{name}.ttf")
        digest = hashlib.sha256(src.read_bytes()).hexdigest()
        if digest != sha:
            sys.exit(f"{src} の sha256 が違う: {digest}(消して取り直すか、原本を確かめてから表を直す)")
        fetch(license_url, OUT / f"OFL-{name}.txt")

        chars = set(ASCII) | (strings_chars() if with_strings else set())
        font = TTFont(src)
        if "fvar" in font:
            font = instancer.instantiateVariableFont(font, {"wght": WEIGHT}, updateFontNames=True)
        subsetter = subset.Subsetter(subset.Options())
        subsetter.populate(unicodes=[ord(c) for c in chars])
        subsetter.subset(font)
        out = OUT / f"{name}-Subset.ttf"
        font.save(out)
        missing = sorted(c for c in chars if ord(c) not in font.getBestCmap())
        print(f"{out.name}: {src.stat().st_size:,} -> {out.stat().st_size:,} バイト、{len(chars)} 文字")
        if missing:
            sys.exit(f"原本に無い文字: {''.join(missing)}")


if __name__ == "__main__":
    main()
