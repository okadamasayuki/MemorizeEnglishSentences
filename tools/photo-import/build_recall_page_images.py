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


def words(s):
    return set(re.findall(r"[a-z']+", s.lower()))


def ocr_lines(ocr_bin, img):
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    out = subprocess.run([ocr_bin, img], capture_output=True, text=True, env=env)
    try:
        return json.loads(out.stdout)[0].get('lines', [])
    except Exception:
        return []


def _maxrun(mask):
    best = run = 0
    for v in mask:
        run = run + 1 if v else 0
        if run > best:
            best = run
    return best


def box_crop(img, lines, sentence, thr=240, pad=10):
    """一致した英文のボックス(例文)を、上下の枠線込みで切り出す。解説は含めない。"""
    w, h = img.size
    sw = words(sentence)
    # 一致した英文の単語を多く含む行=ボックスの本文行
    bl = [l for l in lines if l['text'].strip()
          and len(words(l['text']) & sw) / max(1, len(words(l['text']))) >= 0.6
          and l.get('y', 1) < 0.6]
    if not bl:
        return None
    bl.sort(key=lambda l: l['y'])
    # 上部の連続した行だけに限定(解説に例文の語句が再登場して拾われるのを防ぐ)
    grp = [bl[0]]
    for prev, cur in zip(bl, bl[1:]):
        if cur['y'] - (prev['y'] + prev['h']) < 0.05:
            grp.append(cur)
        else:
            break
    ttop = int(grp[0]['y'] * h)
    tbot = int((grp[-1]['y'] + grp[-1]['h']) * h)
    g = np.asarray(img.convert('L'))

    def is_border(r):  # 幅の 55% 以上が連続して暗い行=ボックスの横罫(枠)
        return _maxrun(g[r] < 235) > 0.55 * w

    # 本文の下→最初の横罫線(枠下端)まで含める。見つからなければ小さめ余白。
    y1 = min(h, tbot + int(0.030 * h))
    for r in range(tbot + 3, min(h, tbot + int(0.22 * h))):
        if is_border(r):
            y1 = min(h, r + 10)
            break
    # 本文の上→最初の横罫線(枠上端)まで含める。
    y0 = max(0, ttop - int(0.030 * h))
    for r in range(ttop - 3, max(0, ttop - int(0.22 * h)), -1):
        if is_border(r):
            y0 = max(0, r - 10)
            break

    band = img.crop((0, y0, w, y1))
    gb = np.asarray(band.convert('L'))
    xs = np.where(np.any(gb < thr, axis=0))[0]
    ys = np.where(np.any(gb < thr, axis=1))[0]
    if len(xs) and len(ys):
        band = band.crop((max(0, xs[0] - pad), max(0, ys[0] - pad),
                          min(band.width, xs[-1] + pad), min(band.height, ys[-1] + pad)))
    return band.filter(ImageFilter.UnsharpMask(radius=1.2, percent=90, threshold=2))


def main():
    passages, photos_dir, ocr_bin, out_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    recall = [b['english'] for b in json.load(open(passages)) if b.get('purpose') == 'recall']
    os.makedirs(out_dir, exist_ok=True)

    manifest, used = {}, set()
    for d in sorted(glob.glob(os.path.join(photos_dir, '*'))):
        imgs = [f for f in glob.glob(os.path.join(d, '**', '*'), recursive=True) if os.path.isfile(f)]
        if not imgs:
            continue
        lines = ocr_lines(ocr_bin, imgs[0])
        if not lines:
            continue
        top = norm(' '.join(l['text'] for l in lines if l.get('y', 1) < 0.5))
        best = max(recall, key=lambda e: difflib.SequenceMatcher(None, top, norm(e)).ratio())
        if difflib.SequenceMatcher(None, top, norm(best)).ratio() < 0.35 or best in used:
            continue
        crop = box_crop(Image.open(imgs[0]).convert('RGB'), lines, best)
        if crop is None:
            continue
        used.add(best)
        crop.save(os.path.join(out_dir, f'{H(best)}.jpg'), 'JPEG', quality=92)
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
