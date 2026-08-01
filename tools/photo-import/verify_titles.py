#!/usr/bin/env python3
# 各ページの日本語見出し(タイトル)を、見出し帯の再OCR(日本語優先)と突き合わせる。
# 差分が出たら原画像を目視して、どちらが正しいかを判定すること。
import os, json, re, subprocess, glob

os.environ.setdefault('OCR_JA', '1')
os.environ.setdefault('OCR_SCALE', '3')

def norm(s):
    return re.sub(r'[\s、。]', '', s)

parsed = json.load(open('parsed.json'))
bad = 0
for p in parsed:
    img = glob.glob(f"photos/*{p['file']}*/*")[0]
    out = subprocess.run(['./cropocr', img, '0.205', '0.226'],
                         capture_output=True, text=True, check=True, env={**os.environ})
    lines = [l['text'] for l in json.loads(out.stdout)]
    if norm(p['topic']) != norm(''.join(lines)):
        bad += 1
        print('DIFF page', p['page'])
        print('  final:', p['topic'])
        print('  reocr:', ' / '.join(lines))
print('title diffs:', bad, '/', len(parsed))
