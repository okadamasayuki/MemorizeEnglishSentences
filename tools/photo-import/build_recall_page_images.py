#!/usr/bin/env python3
# 暗記タブの各文の元スクショ(1ページ=1文の書籍)を OCR で対応づけ、
# 白余白トリミング+鮮明化して端末投入用フォルダに生成する。
# 音読タブの写真ボタンと同じ仕組み(Documents/page_images/<ブロック英文ハッシュ>.jpg)。
#
# 使い方:
#   python3 build_recall_page_images.py passages.json photos_dir ocr_bin out_dir
#     passages.json: [{"english":..., "purpose":"recall"}]  (端末の passages_export.json)
#     photos_dir:    各スクショを含むディレクトリ(サブフォルダ内の画像も再帰的に探索)
#     ocr_bin:       Vision OCR バイナリ(ocr.swift をビルドしたもの)
#     out_dir:       生成先。out_dir/manifest.json({ハッシュ:同ハッシュ})と <ハッシュ>.jpg
#
# 各ページ上半分の OCR テキストを暗記文と difflib で照合して対応づける。
# 端末の manifest とマージしてから devicectl で Documents/page_images へ転送する。
import difflib
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter


def H(t):
    return hashlib.sha256(t.strip().encode()).hexdigest()[:16]


def norm(s):
    return re.sub(r'\s+', ' ', s.lower()).strip()


def ocr_text(ocr_bin, img):
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    out = subprocess.run([ocr_bin, img], capture_output=True, text=True, env=env)
    try:
        data = json.loads(out.stdout)
    except Exception:
        return ''
    lines = data[0].get('lines', []) if isinstance(data, list) and data else []
    top = [l['text'] for l in lines if l.get('y', 1) < 0.5]  # ボックスの英文はページ上部
    return ' '.join(top)


def trim(img, thr=240, pad=16):
    g = np.asarray(img.convert('L'))
    ys = np.where(np.any(g < thr, axis=1))[0]
    xs = np.where(np.any(g < thr, axis=0))[0]
    if len(ys) and len(xs):
        img = img.crop((max(0, xs[0] - pad), max(0, ys[0] - pad),
                        min(img.width, xs[-1] + pad), min(img.height, ys[-1] + pad)))
    return img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=90, threshold=2))


def main():
    passages, photos_dir, ocr_bin, out_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    recall = [b['english'] for b in json.load(open(passages)) if b.get('purpose') == 'recall']
    os.makedirs(out_dir, exist_ok=True)

    manifest, used = {}, set()
    for d in sorted(glob.glob(os.path.join(photos_dir, '*'))):
        imgs = [f for f in glob.glob(os.path.join(d, '**', '*'), recursive=True) if os.path.isfile(f)]
        if not imgs:
            continue
        text = norm(ocr_text(ocr_bin, imgs[0]))
        best = max(recall, key=lambda e: difflib.SequenceMatcher(None, text, norm(e)).ratio())
        ratio = difflib.SequenceMatcher(None, text, norm(best)).ratio()
        if ratio < 0.35 or best in used:
            continue
        used.add(best)
        trim(Image.open(imgs[0]).convert('RGB')).save(
            os.path.join(out_dir, f'{H(best)}.jpg'), 'JPEG', quality=90)
        manifest[H(best)] = H(best)

    json.dump(manifest, open(os.path.join(out_dir, 'manifest.json'), 'w'), ensure_ascii=False)
    print('matched:', len(manifest), '/ recall:', len(recall))
    missing = [e for e in recall if e not in used]
    if missing:
        print('UNMATCHED:', len(missing), file=sys.stderr)
        for e in missing:
            print(' ', e[:60], file=sys.stderr)


if __name__ == '__main__':
    main()
