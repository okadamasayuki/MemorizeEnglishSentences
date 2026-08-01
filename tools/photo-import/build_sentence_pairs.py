#!/usr/bin/env python3
# ブロックの英文と和訳を「文ごとのペア」に分割して sentence_pairs.json を生成する。
# 音読タブで英文1文↔和訳1文を交互表示するためのデータ。
#
# 使い方:
#   python3 build_sentence_pairs.py passages.json [manual_pairs.json]
#     passages.json:     [{"english": 英文, "japanese": 和訳}, ...](passages_export.json でも可)
#     manual_pairs.json: {ブロックハッシュ: [[英文, 和訳], ...]}  ← 文数がずれる会話文等を手動指定
#                        (教材由来の内容なので local-data 等 gitignore 領域に置く)
#
# 英文は文末(. ! ?)、和訳は句点(。！?)で分割し、文数が一致すれば自動でペアにする。
# 一致しないブロックは manual_pairs.json に手動ペアが必要(無ければ一覧を出してエラー終了)。
import hashlib
import json
import re
import sys


def split_en(text):
    # 文末(. ! ?、直後の閉じ引用符含む)+空白+大文字/引用符 で分割。語は一切落とさない。
    parts = re.split(r'(?:(?<=[.!?])|(?<=[.!?]["”\')]))\s+(?=[A-Z"“\'])', text)
    return [p.strip() for p in parts if p.strip()]


def split_ja(text):
    return [p.strip() for p in re.findall(r'[^。！？]*[。！？]?', text) if p.strip()]


def block_hash(text):
    return hashlib.sha256(text.strip().encode()).hexdigest()[:16]


def main():
    passages = json.load(open(sys.argv[1]))
    manual = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else {}

    out, errors = [], []
    for b in passages:
        en_text = b['english']
        key = block_hash(en_text)
        if key in manual:
            pairs = [{'en': e, 'ja': j} for e, j in manual[key]]
        else:
            en, ja = split_en(en_text), split_ja(b['japanese'])
            if len(en) != len(ja):
                errors.append({'key': key, 'en_sentences': len(en), 'ja_sentences': len(ja),
                               'english': en_text})
                continue
            pairs = [{'en': e, 'ja': j} for e, j in zip(en, ja)]
        # トークン整合性: ペアのenを連結した語列がブロック全体と一致するか(単語長押しの位置ずれ防止)
        if ' '.join(p['en'] for p in pairs).split() != en_text.split():
            errors.append({'key': key, 'reason': 'token-mismatch', 'english': en_text})
            continue
        out.append({'key': key, 'pairs': pairs})

    if errors:
        print('ERROR: 手動ペアが必要なブロック(manual_pairs.json に追記してください):', file=sys.stderr)
        for e in errors:
            print(' ', json.dumps(e, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)

    json.dump(out, open('sentence_pairs.json', 'w'), ensure_ascii=False)
    print('sentence_pairs.json written:', len(out), 'blocks /',
          sum(len(o['pairs']) for o in out), 'pairs')


if __name__ == '__main__':
    main()
