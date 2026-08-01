#!/usr/bin/env python3
# parsed.json からアプリ取り込み用の import_passages.json を生成する
# (1トピック = 1文章、ブロックはトラック番号順)
#
# 和訳は Claude Code が作成した ja_translations.tsv(sha256(英文.strip()).hex[:16]<TAB>和訳)
# があれば埋め込む。ない場合は英文のみ(端末側でApple翻訳がフォールバック生成)。
import hashlib
import json
import os

def block_hash(text):
    return hashlib.sha256(text.strip().encode()).hexdigest()[:16]

translations = {}
if os.path.exists('ja_translations.tsv'):
    for line in open('ja_translations.tsv'):
        line = line.rstrip('\n')
        if line.strip():
            h, ja = line.split('\t')
            translations[h] = ja

parsed = json.load(open('parsed.json'))
out, untranslated = [], 0
for p in parsed:  # parsed.json はページ番号順(書籍順)
    blocks = sorted(p['blocks'], key=lambda b: b['track'])
    items = []
    for b in blocks:
        item = {'english': b['english']}
        ja = translations.get(block_hash(b['english']))
        if ja:
            item['japanese'] = ja
        else:
            untranslated += 1
        items.append(item)
    out.append({'title': p['topic'], 'blocks': items})
json.dump(out, open('import_passages.json', 'w'), ensure_ascii=False, indent=1)
print('passages:', len(out), '/ blocks:', sum(len(o['blocks']) for o in out),
      '/ 和訳なし:', untranslated)
