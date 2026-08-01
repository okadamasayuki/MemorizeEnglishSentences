#!/usr/bin/env python3
# 文末が途切れている等の疑いがあるブロックを、帯域切り出し+拡大の再OCRで置き換える
import json, re, subprocess, glob, sys

WORDS = set(w.strip().lower() for w in open('/usr/share/dict/words'))

def has_cjk(s):
    return any('　' <= c <= '鿿' for c in s)

def normalize(s):
    return (s.replace('’', "'").replace('‘', "'").replace('“', '"').replace('”', '"')
             .replace('ﬁ', 'fi').replace('ﬂ', 'fl').replace('—', '-').replace('–', '-')
             .replace('ı', 'i'))

def join_paragraph(texts):
    text = ''
    for t in texts:
        t = t.strip()
        if not t:
            continue
        if not text:
            text = t
        elif text.endswith('-'):
            head = text[:-1]
            m = re.search(r'[A-Za-z]+$', head); m2 = re.match(r'^[A-Za-z]+', t)
            if m and m2 and (m.group(0) + m2.group(0)).lower() in WORDS:
                text = head + t
            else:
                text = text + t
        else:
            text = text + ' ' + t
    return re.sub(r'\s+', ' ', text).strip()

def extract(img, y0, y1):
    out = subprocess.run(['./cropocr', img, str(y0), str(y1)],
                         capture_output=True, text=True, check=True)
    texts = []
    for l in json.loads(out.stdout):
        t = normalize(l['text']).strip()
        if not t or has_cjk(t) or 'Content' in t:
            continue
        if re.fullmatch(r'\d{1,2}', t):
            continue
        if l['x'] > 0.75 and re.fullmatch(r'[^A-Za-z]*\d{2,4}[^A-Za-z]*', t):
            continue
        texts.append(t)
    text = join_paragraph(texts)
    return re.sub(r'^(?:\d{1,2}[-–•]?|[-–•])\s+(?=[A-Z"])', '', text)

def clean(e):
    # 末尾: 最後の文末記号の後に残った小文字を含まない短い断片(フッター等の誤認識)を落とす
    e = re.sub(r'([.!?]["\)]?)\s+[^a-z]{2,24}$', r'\1', e)
    # 先頭: 大文字始まりの単語になるまで、記号・数字混じりのゴミトークンを落とす(最大3個)
    for _ in range(3):
        if re.match(r'^["A-Z]([A-Za-z]| )', e):
            break
        stripped = re.sub(r'^\S+\s+', '', e)
        if stripped == e:
            break
        e = stripped
    return e

def needs_repair(e):
    return not re.search(r'[.!?][")]?$', e) or not re.match(r'^["A-Z]([A-Za-z]| )', e)

parsed = json.load(open('parsed.json'))
repaired = 0
for p in parsed:
    for b in p['blocks']:
        b['english'] = clean(b['english'])
        if not needs_repair(b['english']):
            continue
        img = glob.glob(f"photos/*{p['file']}*/*")[0]
        # マーカー行の少し上からフッター/次マーカーまで、下端は少し余裕を持たせる
        new = clean(extract(img, max(b['y0'] - 0.012, 0), min(b['y1'] + 0.012, 0.79)))
        status = 'OK ' if not needs_repair(new) else 'STILL-BAD'
        print(f"{status} track{b['track']}: {len(b['english'])} -> {len(new)} chars", file=sys.stderr)
        if not needs_repair(new) or len(new) >= len(b['english']):
            b['english'] = new
            repaired += 1
json.dump(parsed, open('parsed.json', 'w'), ensure_ascii=False, indent=1)
print('repaired:', repaired, file=sys.stderr)
