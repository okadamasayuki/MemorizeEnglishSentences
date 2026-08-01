---
name: photo-import
description: 書籍ページのスクショ/写真から英文を抽出してアプリ(音読タブ)に投入する。写真からの教材取り込み・例文追加の依頼が来たら必ずこのスキルに従う。抽出後の検証チェックリストと、教材本文をリポジトリに入れないための転送手順を含む。
---

# 写真→アプリ取り込みパイプライン

書籍ページの写真から英文を抽出し、iPhoneの音読タブへ投入するための確立済み手順。
ツールは `tools/photo-import/` にある。作業ファイルはすべて scratchpad で行い、**リポジトリ内に educational content(教材の本文・タイトル・JSON)を一切置かない**こと。

## 運用ポリシー(必ず守る)

- 市販教材でも、**ユーザー自身の端末に入れる私的利用の範囲**でのみ対応する。本文は「ローカルOCR → JSON → USB経由でiPhoneのアプリ内フォルダ」だけを通し、リポジトリ・GitHub・会話出力には載せない。
- 本文の書き起こしは必ず機械(Vision OCR)が行う。Claudeが手で長文を書き写さない。チェックで見つけた誤りの修正は該当語句のみの置換で行う。

## 手順

1. **写真の入手**: Photosライブラリはシェルから読めない(TCC)。`osascript` で `media item id "<UUID>/L0/001"` をエクスポートする(UUIDは添付画像の派生ファイル名から取れる)。Readツールならライブラリ内も直接読める。
2. **OCR 2パス**: `swiftc -O ocr.swift -o ocr`(要 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)。英語優先(既定)と `OCR_LANGS=ja`(見出し用)の2回実行。
3. **構造化**: `parse.py` — ブロック区切りは「Content Block」文字列(OCR崩れ許容)+右端のトラック番号バッジの両方を信号にする。ページ番号で書籍順に並べる。レイアウトが違う教材ではヒューリスティックの調整が必要。
4. **自動修復**: `repair.py` — 文頭・文末が壊れているブロックを帯域切り出し+2倍拡大(`cropocr`)で再OCRして置き換える。

## 検証チェックリスト(全部やる。過去にこれで計16箇所の誤りを検出した)

1. `checks.py` — 形式・スペル・文法lint・重複・語数分布(指摘ゼロが合格。UNKNOWN-WORDは辞書漏れの正しい語も出るので目視判定)
2. `verify_pass.py` — 第2の読み取り(2倍拡大)との**単語列diff+単語数照合**
3. `OCR_SCALE=3 OCR_NOCORRECT=1 python3 verify_pass.py` — 言語補正OFFの第3の読み取りとの照合(**句読点列もここで照合**)。補正ONの2パスが同じ誤りをした場合を潰す
4. `verify_titles.py` — 日本語見出しの照合
5. **全文通読** — 一語ずつは正しくても意味が破綻するタイプ(語順入れ替わり・語句欠落・別単語化)はOCR照合をすり抜けることがある。全ブロックを読み、意味が通るか確認する
6. 2〜5で出た差分は**必ず原画像をReadして目視で決着**させる(再OCR側の誤読のことも多い。AI→Al、SpaceXのX欠落、行断片の重複読みが常連)
7. 端末反映後、`passages_export.json` を取得して投入元と完全一致・和訳の充足を確認する

## 単語の意味の自動生成(取り込みとセットで必ず行う)

ユーザーの standing request: 本文の取り込み後、各内容語に「その文中での品詞・訳語」を付けて端末キャッシュに投入する。**生成はAPIではなくClaude Code自身が行う(課金なし)**。

1. `python3 word_inventory.py parsed.json ../../local-data/word-glosses/base_gloss.json` — 対象語を抽出し、基礎辞書にない新出語を `new_words.txt` に出す(トークナイズはアプリの WordTokenizer.normalize+機能語除外と完全一致)
2. 新出語に品詞・訳語(目安15文字以内の簡潔な訳語)を割り当て、`local-data/word-glosses/base_gloss.json` に追記する。訳語はこの教材での使われ方に合わせる
3. **文脈レビュー(必須・全ブロック)**: `python3 preview_senses.py words_by_block.json ../../local-data/word-glosses/base_gloss.json ../../local-data/word-glosses/overrides.tsv` の出力を通読し、**既知語も含めて**新しい文章の文脈に訳語が合っているかを1ブロックずつ確認する。基礎辞書は初期値にすぎない — 前回の訳をそのまま流用せず、文脈に合わない語(多義語: run/right/left/work/train/matter 等はとくに注意)は `local-data/word-glosses/overrides.tsv` に「ブロックハッシュ\t単語\t品詞\t訳語」で訳し分けを追記する
4. `python3 build_word_senses.py words_by_block.json ../../local-data/word-glosses/base_gloss.json ../../local-data/word-glosses/overrides.tsv` — 網羅検証つきで `word_senses.json` を生成
5. `word_senses.json` を `Documents/word_senses.json` へ devicectl copy → アプリ起動で取り込み → `word_senses_result.json` を取得して imported 件数を検証

`local-data/` は gitignore 済みのMacローカル保存領域。訳語辞書・教材由来データはリポジトリにコミットしない。

## 端末への反映

- 取り込み: `import_passages.json`(`make_import_json.py` で生成)を `devicectl device copy to ... --destination "Documents/import_passages.json" --domain-type appDataContainer --domain-identifier com.okadamasayuki.MemorizeEnglishSentences` で転送 → アプリ起動で取り込み(タイトル重複はスキップ、取り込み後ファイル自動削除)
- 修正: `corrections.json`(`[{"old","new"}]`、英文完全一致で置換・和訳は自動リセット→再翻訳)
- 削除: `delete_passages.json`(ブロック英文の先頭一致で文章ごと削除)
- 和訳: 入れない。音読タブ表示時に端末内Apple翻訳が一括生成・保存する
- ビルド/インストール手順とデバイスIDはメモリ `iphone-deploy-procedure` を参照
