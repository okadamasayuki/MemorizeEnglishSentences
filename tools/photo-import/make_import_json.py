#!/usr/bin/env python3
# parsed.json からアプリ取り込み用の import_passages.json を生成する
# (1トピック = 1文章、ブロックはトラック番号順。和訳は端末側で自動生成させるため入れない)
import json

parsed = json.load(open('parsed.json'))
out = []
for p in parsed:  # parsed.json はページ番号順(書籍順)
    blocks = sorted(p['blocks'], key=lambda b: b['track'])
    out.append({
        'title': p['topic'],
        'blocks': [{'english': b['english']} for b in blocks],
    })
json.dump(out, open('import_passages.json', 'w'), ensure_ascii=False, indent=1)
print('passages:', len(out), '/ blocks:', sum(len(o['blocks']) for o in out))
