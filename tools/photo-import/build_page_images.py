#!/usr/bin/env python3
# 各英文ブロックに対応する「元スクショの、そのブロックだけを切り出した画像」を端末投入用に書き出す。
# 音読タブのブロック右上の写真ボタンから、読み取りが正しいかすぐ確認するためのデータ。
#
# 使い方:
#   python3 build_page_images.py parsed.json passages.json photos_dir out_dir
#     parsed.json:   [{"file": UUID先頭, "topic":..., "blocks":[{"english":..., "y0":.., "y1":..}]}]
#                    (parse.py の出力。y0/y1 は 上=0 の正規化縦座標)
#     passages.json: [{"english": 最終英文, ...}]  (端末の passages_export.json)
#     photos_dir:    Photos からエクスポートした元画像(<UUID>/**/画像)のディレクトリ
#     out_dir:       生成先。out_dir/manifest.json と out_dir/<ブロック英文ハッシュ>.jpg
#
# 出力を `devicectl device copy to --destination Documents/page_images`(フォルダごと)で転送する。
# manifest.json は {ブロック英文ハッシュ(sha256[:16]): 同ハッシュ}(画像ファイル名=ハッシュ)。
# 端末英文がOCR補正後で parsed とずれるブロックは difflib で近い parsed ブロックに対応づける。
import difflib
import glob
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter


def H(t):
    return hashlib.sha256(t.strip().encode()).hexdigest()[:16]


def _max_dark_run(row_mask):
    best = run = 0
    for v in row_mask:
        run = run + 1 if v else 0
        if run > best:
            best = run
    return best


def crop_block(path, y0, y1, padtop=0.010, thr=240, padx=14, white=242):
    """元画像から1ブロック分(ヘッダー込み)を切り出し、左右・下の余白を削って鮮明化する。

    下端は「次ブロックのヘッダー黒四角」または「本文後の連続した白帯(8行)」の早い方で切る。
    次ブロックとの白ギャップは数pxしかないため、黒四角(連続黒の塊)を目印にして混入を防ぐ。
    """
    img = Image.open(path).convert('RGB')
    w, h = img.size
    top = int(max(0.0, y0 - padtop) * h)
    bot_gen = int(min(1.0, y1 + 0.035) * h)   # 広めに取ってから内容で下端を決める
    band = img.crop((0, top, w, bot_gen))
    gray = np.asarray(band.convert('L'))
    n = gray.shape[0]
    hdr_thr = max(18, int(0.015 * w))
    is_header = np.array([_max_dark_run(gray[r] < 60) > hdr_thr for r in range(n)])
    row_med = np.median(gray, axis=1)

    i = 0
    while i < n and not is_header[i]:
        i += 1                     # ヘッダー上の白帯を抜ける
    while i < n and is_header[i]:
        i += 1                     # 現ブロックのヘッダー黒四角を抜ける
    cut, run = band.height, 0
    k = i                          # 本文開始
    while k < n:
        if is_header[k]:           # 次ブロックのヘッダー黒四角 → その直上の白帯の上で切る
            j = k
            while j > 0 and row_med[j - 1] >= white:
                j -= 1
            cut = max(j, 1)
            break
        if row_med[k] >= white:    # 本文後の連続した白帯
            run += 1
            if run >= 8:
                cut = k - 7
                break
        else:
            run = 0
        k += 1
    band = band.crop((0, 0, w, cut))

    gray2 = np.asarray(band.convert('L'))
    xs = np.where(np.any(gray2 < thr, axis=0))[0]
    if len(xs):
        band = band.crop((max(0, xs[0] - padx), 0, min(band.width, xs[-1] + padx), band.height))
    return band.filter(ImageFilter.UnsharpMask(radius=1.2, percent=90, threshold=2))


def main():
    parsed = json.load(open(sys.argv[1]))
    passages = json.load(open(sys.argv[2]))
    photos_dir = sys.argv[3]
    out_dir = sys.argv[4]
    os.makedirs(out_dir, exist_ok=True)

    dirs = os.listdir(photos_dir)
    final = [b['english'] for b in passages]
    final_hash = set(H(e) for e in final)

    def final_hash_for(parsed_en):
        h = H(parsed_en)
        if h in final_hash:
            return h
        best = max(final, key=lambda r: difflib.SequenceMatcher(None, parsed_en, r).ratio())
        return H(best) if difflib.SequenceMatcher(None, parsed_en, best).ratio() > 0.7 else None

    manifest = {}
    made = skipped = 0
    for pg in parsed:
        hit = [d for d in dirs if d.startswith(pg['file'])]
        if not hit:
            print('WARN: no photo dir for', pg['file'], file=sys.stderr)
            continue
        imgs = [f for f in glob.glob(os.path.join(photos_dir, hit[0], '**', '*'), recursive=True)
                if os.path.isfile(f)]
        if not imgs:
            continue
        path = imgs[0]
        blocks = pg['blocks']
        for j, b in enumerate(blocks):
            fh = final_hash_for(b['english'])
            if not fh:
                skipped += 1
                continue
            crop_block(path, b['y0'], b['y1']).save(
                os.path.join(out_dir, f'{fh}.jpg'), 'JPEG', quality=92)
            manifest[fh] = fh
            made += 1

    json.dump(manifest, open(os.path.join(out_dir, 'manifest.json'), 'w'), ensure_ascii=False)
    print('block images:', made, '/ skipped:', skipped, '/ manifest:', len(manifest))


if __name__ == '__main__':
    main()
