"""URL を貼ったときのプレビュー画像 docs/images/og.png(1200 × 630)を、tools/og.html から作る。

窓なし・消音の Chrome(使い捨てのプロフィール)の --screenshot で撮る。CI は docs/images/og.png を build/web/og.png に写す。
docs/images/ の画面の画像を撮り直したら、これも流し直す。

    python tools/make_og.py
"""

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHROME = Path("C:/Program Files/Google/Chrome/Application/chrome.exe")
OUT = ROOT / "docs" / "images" / "og.png"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not CHROME.exists():
        sys.exit(f"Chrome が無い: {CHROME}")
    with tempfile.TemporaryDirectory() as profile:
        subprocess.run([
            str(CHROME), "--headless=new", "--mute-audio", f"--user-data-dir={profile}", "--no-first-run",
            "--hide-scrollbars", "--allow-file-access-from-files", "--window-size=1200,630",
            f"--screenshot={OUT}", (ROOT / "tools" / "og.html").as_uri(),
        ], check=True, capture_output=True, timeout=120)
    print(f"{OUT.relative_to(ROOT).as_posix()}: {OUT.stat().st_size:,} バイト")


if __name__ == "__main__":
    main()
