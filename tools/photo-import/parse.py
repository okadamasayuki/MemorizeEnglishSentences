#!/usr/bin/env python3
# OCR 2パス(英語優先/日本語優先)の結果を統合し、ページ構造(トピック/ブロック/英文)に整形する
import json, re, sys, unicodedata

EN = json.load(open('ocr_raw.json'))
JA = json.load(open('ocr_raw_ja.json'))

def has_cjk(s):
    return any('　' <= c <= '鿿' or '＀' <= c <= '￯' for c in s)

def normalize(s):
    s = s.replace('’', "'").replace('‘', "'")
    s = s.replace('“', '"').replace('”', '"')
    s = s.replace('ﬁ', 'fi').replace('ﬂ', 'fl')
    s = s.replace('—', '-').replace('–', '-').replace('ı', 'i')
    return s

def strip_leading_number(text):
    """段落頭に混入した左端の小さなブロック通し番号を除く"""
    return re.sub(r'^(?:\d{1,2}[-–•]?|[-–•])\s+(?=[A-Z"])', '', text)

WORDS = set(w.strip().lower() for w in open('/usr/share/dict/words'))
hyphen_log = []

def rows_from(lines):
    """y が近い行を1つの行(row)にまとめ、x順に結合する"""
    rows = []
    for l in sorted(lines, key=lambda l: (l['y'], l['x'])):
        if rows and abs(l['y'] - rows[-1]['y']) < 0.007:
            rows[-1]['parts'].append(l)
        else:
            rows.append({'y': l['y'], 'parts': [l]})
    out = []
    for r in rows:
        parts = sorted(r['parts'], key=lambda p: p['x'])
        out.append({'y': r['y'], 'x': parts[0]['x'],
                    'text': ' '.join(p['text'] for p in parts),
                    'parts': parts})
    return out

def join_paragraph(row_texts, page_file, track):
    """行を段落に結合。行末ハイフンは辞書照合で綴じるか残すかを決める"""
    text = ''
    for t in row_texts:
        t = t.strip()
        if not t:
            continue
        if not text:
            text = t
            continue
        if text.endswith('-'):
            head = text[:-1]
            m = re.search(r'[A-Za-z]+$', head)
            m2 = re.match(r'^[A-Za-z]+', t)
            if m and m2:
                joined = (m.group(0) + m2.group(0)).lower()
                if joined in WORDS:
                    hyphen_log.append(f'{page_file} track{track}: JOIN   {m.group(0)}-{m2.group(0)} -> {m.group(0)}{m2.group(0)}')
                    text = head + t
                else:
                    hyphen_log.append(f'{page_file} track{track}: KEEP   {m.group(0)}-{m2.group(0)}')
                    text = text + t
            else:
                text = text + t
        else:
            text = text + ' ' + t
    return re.sub(r'\s+', ' ', text).strip()

pages = []
for en_page, ja_page in zip(EN, JA):
    assert en_page['file'] == ja_page['file']
    f = en_page['file'].split('/')[1][:8]
    en_lines = [dict(l, text=normalize(l['text'])) for l in en_page['lines']]
    ja_lines = [dict(l, text=normalize(l['text'])) for l in ja_page['lines']]

    # ブロック区切り: "Content Block"(OCR 崩れ含む)と右側のトラック番号バッジの両方を信号にする
    marker_ys = []
    def add_marker(y):
        if not any(abs(y - e) < 0.012 for e in marker_ys):
            marker_ys.append(y)
    for l in en_lines + ja_lines:
        t = l['text'].strip()
        if 'Content' in t and l['x'] < 0.4:
            add_marker(l['y'])
        # トラック番号バッジ: 右端の小さな数字(アイコン誤認識の混入を許容)
        if l['x'] > 0.75 and l['h'] < 0.012:
            digits = re.sub(r'\D', '', t)
            if 2 <= len(digits) <= 4 and re.fullmatch(r'[^A-Za-z]*', re.sub(r'\d', '', t)):
                if 1 <= int(digits[-3:]) <= 240:
                    add_marker(l['y'])
    marker_ys.sort()
    markers = []
    for y in marker_ys:
        # 副題: 同じ行にある CJK テキスト(JAパス優先)
        sub = ''
        for l in ja_lines:
            if abs(l['y'] - y) < 0.012 and has_cjk(l['text']):
                t = l['text']
                if 'Content Block' in t:
                    t = t.split('Content Block', 1)[1]
                t = re.sub(r'^[^ぁ-ヿ㐀-鿿A-Za-z]*', '', t).strip()
                if t:
                    sub = t
                    break
        markers.append({'y': y, 'subtitle': sub})
    if len(markers) != 5:
        print(f'WARN {f}: {len(markers)} markers', file=sys.stderr)

    # トピック: 最初のマーカーより上にある CJK 行
    topic = None
    cands = [l for l in ja_lines
             if has_cjk(l['text']) and 'Content' not in l['text']
             and l['y'] < markers[0]['y'] - 0.004]
    if cands:
        topic = max(cands, key=lambda l: l['y'])['text'].strip()

    # ページ番号: 下端近くの "132 |..." など先頭3桁
    page_no = None
    for l in sorted(en_lines + ja_lines, key=lambda l: -l['y']):
        m = re.match(r'^(\d{3})\b', l['text'].strip())
        if m and l['y'] > markers[-1]['y']:
            page_no = int(m.group(1))
            break

    # トラック番号: 各マーカー行の右側の数字(スピーカーアイコンの誤認識を除去)
    def track_for(marker_y):
        best = None
        for l in en_lines + ja_lines:
            if l['x'] > 0.7 and abs(l['y'] - marker_y) < 0.012:
                digits = re.sub(r'\D', '', l['text'])
                if len(digits) >= 3:
                    t = int(digits[-3:])
                    if 1 <= t <= 240:
                        best = t
        return best

    blocks = []
    for i, mk in enumerate(markers):
        lo = mk['y'] + 0.004
        hi = markers[i + 1]['y'] - 0.004 if i + 1 < len(markers) else (page_no and 10) or 10
        if i + 1 == len(markers):
            # 最終ブロックはフッター(左端のページ番号行)の手前まで
            foot = [l for l in en_lines
                    if re.match(r'^\d{3}\b', l['text'].strip())
                    and l['x'] < 0.3 and l['y'] > mk['y'] + 0.02]
            hi = min((l['y'] for l in foot), default=1.0) - 0.01
        rows = rows_from([l for l in en_lines if lo < l['y'] < hi])
        texts = []
        for r in rows:
            t = r['text'].strip()
            if 'Content Block' in t:
                continue
            if re.fullmatch(r'\d{1,2}', t):          # 左の小さな通し番号
                continue
            if r['x'] > 0.75 and re.fullmatch(r'[^A-Za-z]*\d{3}[^A-Za-z]*', t):
                continue                             # トラック番号
            if has_cjk(t):
                continue
            texts.append(t)
        track = track_for(mk['y'])
        english = strip_leading_number(join_paragraph(texts, f, track))
        blocks.append({'track': track, 'subtitle': mk['subtitle'], 'english': english,
                       'y0': lo, 'y1': hi})

    # トラック番号の欠けをページ内の連番から補完する(1ページ = 連続する5トラック)
    bases = [b['track'] - i for i, b in enumerate(blocks) if b['track'] is not None]
    if bases:
        base = max(set(bases), key=bases.count)
        if len(set(bases)) > 1:
            print(f'WARN {f}: inconsistent tracks {[b["track"] for b in blocks]}', file=sys.stderr)
        for i, b in enumerate(blocks):
            if b['track'] is None:
                b['track'] = base + i

    pages.append({'file': f, 'page': page_no, 'topic': topic, 'blocks': blocks})

pages.sort(key=lambda p: (p['page'] is None, p['page']))
json.dump(pages, open('parsed.json', 'w'), ensure_ascii=False, indent=1)
open('hyphen_log.txt', 'w').write('\n'.join(hyphen_log))

# ---- 検証サマリ ----
print('pages:', len(pages))
tracks = [b['track'] for p in pages for b in p['blocks']]
print('blocks:', len(tracks))
missing_track = [i for i, t in enumerate(tracks) if t is None]
print('blocks w/o track:', len(missing_track))
got = sorted(t for t in tracks if t)
dup = sorted(set(t for t in got if got.count(t) > 1))
print('duplicate tracks:', dup)
print('missing in 1..240:', sorted(set(range(1, 241)) - set(got))[:20])
print('pages w/o topic:', [p['file'] for p in pages if not p['topic']])
print('page numbers:', [p['page'] for p in pages])
short = [(p['file'], b['track'], len(b['english'])) for p in pages for b in p['blocks'] if len(b['english']) < 200]
print('suspiciously short blocks:', short)
