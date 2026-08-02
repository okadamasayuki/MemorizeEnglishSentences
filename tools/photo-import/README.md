# photo-import — 書籍ページ写真の抽出・検証パイプライン

書籍ページのスクショから英文を抽出して MemorizeEnglishSentences に投入するためのツール一式。
使い方・チェックリスト・運用ポリシーは `.claude/skills/photo-import/SKILL.md` を参照。

**注意**: 教材の本文・生成される JSON(`parsed.json` / `import_passages.json` / `corrections.json` など)は
リポジトリに置かず、scratchpad 等の作業ディレクトリで扱うこと。ここにはコードのみを置く。

| ファイル | 役割 |
| --- | --- |
| `ocr.swift` | ページ全体のOCR(行+座標をJSON出力)。`OCR_LANGS=ja` で日本語優先 |
| `cropocr.swift` | 帯域切り出し+拡大の再OCR。`OCR_SCALE` / `OCR_NOCORRECT=1` / `OCR_JA=1` |
| `parse.py` | 2パスのOCR結果をページ構造(トピック/ブロック/トラック番号)に整形 |
| `repair.py` | 文頭・文末が壊れたブロックを再OCRで自動修復 |
| `checks.py` | 形式・スペル・文法lint・重複・語数の一括機械チェック |
| `verify_pass.py` | 独立した再OCRとの単語列・句読点列の突き合わせ |
| `verify_titles.py` | 日本語見出しの突き合わせ |
| `make_import_json.py` | 確定データからアプリ取り込み用JSONを生成 |
| `word_inventory.py` | 単語の意味の事前生成の対象語を抽出(アプリと同一のトークナイズ規則) |
| `preview_senses.py` | 各ブロックの英文と割り当て予定の訳語を並べて表示(文脈レビュー用) |
| `build_word_senses.py` | 訳語辞書+オーバーライドから word_senses.json を網羅検証つきで生成 |
| `build_sentence_pairs.py` | 英文↔和訳を文ごとのペアに分割し sentence_pairs.json を生成(音読タブの交互表示用) |
| `build_page_images.py` | 各ブロックだけを切り出した元スクショと manifest.json を生成(読み取り確認用) |
| `build_recall_page_images.py` | 暗記文の元スクショをOCRで対応づけ、ページ画像と manifest.json を生成 |

スクリプトのレイアウト前提(「Content Block」ラベル、右端の音声トラック番号、下端のページ番号)は
特定の教材シリーズ向けなので、別レイアウトの教材では `parse.py` の調整が必要。
