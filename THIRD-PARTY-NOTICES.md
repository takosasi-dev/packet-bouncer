# 同梱している他者の素材

自分で作った物(コード・効果音)以外に、次のフォントを同梱しています。どちらも SIL Open Font License 1.1 です。

| 同梱ファイル | 元のフォント | 入手元 | ライセンスの原文 | 手を加えた所 |
|---|---|---|---|---|
| `assets/fonts/NotoSansJP-Subset.ttf` | Noto Sans JP(可変フォント) | [google/fonts `ofl/notosansjp`](https://github.com/google/fonts/tree/5bb28733cec313b63fbd415b574b5ae35c8aa8b8/ofl/notosansjp) | `assets/fonts/OFL-NotoSansJP.txt` | 太さを 400 に固定し、画面で使う文字と ASCII だけに絞った |
| `assets/fonts/JetBrainsMono-Subset.ttf` | JetBrains Mono(可変フォント) | [google/fonts `ofl/jetbrainsmono`](https://github.com/google/fonts/tree/5bb28733cec313b63fbd415b574b5ae35c8aa8b8/ofl/jetbrainsmono) | `assets/fonts/OFL-JetBrainsMono.txt` | 太さを 400 に固定し、ASCII だけに絞った |

- 絞る手順は `tools/subset_font.py` にあります。
- Noto Sans JP の Reserved Font Name は「Source」です。絞った物は「Source」を名前に使っていません(フォント名は Noto Sans JP のまま)。JetBrains Mono には Reserved Font Name がありません。
