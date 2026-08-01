#!/usr/bin/env python3
# parsed.json のテキスト単体でできる機械チェックをまとめて実行する(全て指摘ゼロが合格)
import json, re, sys
from collections import Counter

parsed = json.load(open('parsed.json'))
blocks = [(p, b) for p in parsed for b in p['blocks']]
issues = 0

WORDS = set(w.strip().lower() for w in open('/usr/share/dict/words'))

def known(w):
    w = w.lower()
    if w in WORDS or len(w) <= 2 or "'" in w:
        return True
    for strip, add in [('s', ''), ('es', ''), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e'),
                       ('ly', ''), ('ies', 'y'), ('er', ''), ('est', ''), ('ers', ''),
                       ('ments', 'ment'), ('ns', 'n')]:
        if w.endswith(strip) and (w[: len(w) - len(strip)] + add) in WORDS:
            return True
    if '-' in w:
        return all(known(x) for x in w.split('-') if x)
    return False

for p, b in blocks:
    e = b['english']
    t = b['track']
    if not re.match(r'^["A-Z]([A-Za-z]| )', e): print('BAD-START', t); issues += 1
    if not re.search(r'[.!?][")]?$', e): print('BAD-END', t); issues += 1
    if re.search(r'[^\x00-\x7F]', e): print('NON-ASCII', t, set(re.findall(r'[^\x00-\x7F]', e))); issues += 1
    if '  ' in e or e != e.strip(): print('WHITESPACE', t); issues += 1
    if re.search(r'\b(\w+) \1\b', e, re.I): print('DUP-WORD', t, re.search(r'\b(\w+) \1\b', e, re.I).group(0)); issues += 1
    if e.count('"') % 2: print('UNBALANCED-QUOTE', t); issues += 1
    if e.count('(') != e.count(')'): print('UNBALANCED-PAREN', t); issues += 1
    if re.search(r'\s[,.;:]', e) or re.search(r'[,.;:]{2}', e): print('PUNCT-SPACING', t); issues += 1
    for m in re.finditer(r'[.!?] ([a-z]\w*)', e):
        print('LOWER-SENT-START', t, m.group(0)); issues += 1
    for m in re.finditer(r'\b(a|an) ([A-Za-z]+)', e):
        art, w = m.group(1), m.group(2).lower()
        v = w[0] in 'aeiou' and not w.startswith(('uni', 'use', 'eur', 'one', 'uti'))
        if (art == 'a' and v) or (art == 'an' and not v):
            print('A/AN', t, m.group(0)); issues += 1
    for tok in re.findall(r"[A-Za-z][A-Za-z'-]*", e):
        if not tok[0].isupper() and not known(tok):
            print('UNKNOWN-WORD', t, tok); issues += 1  # 辞書漏れの正しい語も混ざるので要目視

texts = [b['english'] for _, b in blocks]
for txt, c in Counter(texts).items():
    if c > 1:
        print('DUPLICATE-BLOCK', txt[:50]); issues += 1
for _, b in blocks:
    wc = len(b['english'].split())
    if wc < 30 or wc > 90:
        print('WORDCOUNT-OUTLIER', b['track'], wc); issues += 1

print('total flagged:', issues)
sys.exit(0 if issues == 0 else 1)
