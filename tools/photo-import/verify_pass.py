#!/usr/bin/env python3
# 確定済み parsed.json を、独立した再OCR(帯域切り出し+拡大)と単語列・句読点列で突き合わせる。
#   通常パス:  python3 verify_pass.py
#   補正OFFパス: OCR_SCALE=3 OCR_NOCORRECT=1 python3 verify_pass.py
# 差分は「本文の誤り」ではなく再OCR側の誤読・ゴミ拾いのこともあるため、
# 出た差分は必ず原画像を目視して判定すること。
import os, json, re, subprocess, glob, difflib

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
                         capture_output=True, text=True, check=True, env={**os.environ})
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
    return join_paragraph(texts)

def tokens(s):
    return re.findall(r"[a-z0-9]+(?:['-][a-z0-9]+)*", s.lower())

def puncts(s):
    return re.findall(r'[.,;:!?]', s)

parsed = json.load(open('parsed.json'))
word_mismatch = punct_mismatch = checked = 0
for p in parsed:
    img = glob.glob(f"photos/*{p['file']}*/*")[0]
    for b in p['blocks']:
        checked += 1
        ocr2 = extract(img, max(b['y0'] - 0.012, 0), min(b['y1'] + 0.012, 0.79))
        t_final, t_ocr = tokens(b['english']), tokens(ocr2)
        # 再OCR側先頭のゴミトークンを最大3つまで読み飛ばして最良整列
        best = None
        for skip in range(0, 4):
            cand = t_ocr[skip:]
            r = difflib.SequenceMatcher(None, t_final, cand).ratio()
            if best is None or r > best[0]:
                best = (r, cand)
        t_ocr = best[1]
        sm = difflib.SequenceMatcher(None, t_final, t_ocr)
        ops = [o for o in sm.get_opcodes() if o[0] != 'equal']
        # 先頭・末尾への挿入(帯域外のラベル・フッターのゴミ)は無視する
        core = [o for o in ops if not (o[0] == 'insert' and (o[1] == 0 or o[1] == len(t_final)))]
        if core:
            word_mismatch += 1
            print(f"=W= track {b['track']} words final={len(t_final)} reocr={len(t_ocr)}")
            for op, i1, i2, j1, j2 in core:
                print(f"   {op}: final={t_final[i1:i2]} reocr={t_ocr[j1:j2]}")
        elif puncts(b['english']) != puncts(ocr2):
            punct_mismatch += 1
            print(f"=P= track {b['track']} punct final={''.join(puncts(b['english']))} reocr={''.join(puncts(ocr2))}")
print(f"checked: {checked} / word mismatches: {word_mismatch} / punct mismatches: {punct_mismatch}")
