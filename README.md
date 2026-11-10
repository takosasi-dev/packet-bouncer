# PacketBouncer(パケット検問ゲーム)

> **開発中です。** いまはタイトル画面だけで、まだ遊べません。

ブラウザで開くだけで遊べる、1 プレイ 3〜4 分のゲームです。プレイヤーはファイアウォール役になり、1 枚ずつ出てくるパケットを、画面のルール表に従って「通す」か「落とす」かに仕分けます。

- 遊ぶ: https://takosasi-dev.github.io/packet-bouncer/
- 動作環境: デスクトップ版の Chrome・Edge・Firefox(インストール不要)

## ソースから動かす

[Godot 4.7.2](https://godotengine.org/)(標準版。.NET 版ではない)と、Web の書き出しテンプレートが要ります。

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --export-release "Web" build/web/index.html
```

`main` に push すると、GitHub Actions がテスト → Web 書き出し → GitHub Pages への配置を行います(`.github/workflows/pages.yml`)。テストが 1 件でも落ちたら配置しません。

同梱フォントを作り直すとき(画面の文言を増やしたとき)は `pip install fonttools` の後に `python tools/subset_font.py` を実行します。

## ライセンス

MIT(`LICENSE`)。同梱フォントは SIL Open Font License 1.1 です(`THIRD-PARTY-NOTICES.md`)。
