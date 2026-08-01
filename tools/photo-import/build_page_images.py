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


def crop_block(path, y0, y1, next_top, padtop=0.008, padbot=0.010, thr=240, padx=14, padb=8):
    """元画像から1ブロック分(ヘッダー込み)を切り出し、左右・下の白余白を削って鮮明化する。"""
    img = Image.open(path).convert('RGB')
    w, h = img.size
    top = int(max(0.0, y0 - padtop) * h)
    bot = int(min(y1 + padbot, next_top - 0.002) * h)  # 次ブロックの手前で必ず切る
    band = img.crop((0, top, w, bot))
    gray = np.asarray(band.convert('L'))
    xs = np.where(np.any(gray < thr, axis=0))[0]
    ys = np.where(np.any(gray < thr, axis=1))[0]
    x0 = max(0, xs[0] - padx) if len(xs) else 0
    x1 = min(band.width, xs[-1] + padx) if len(xs) else band.width
    by = min(band.height, ys[-1] + padb) if len(ys) else band.height
    band = band.crop((x0, 0, x1, by))
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
            next_top = blocks[j + 1]['y0'] if j + 1 < len(blocks) else 1.0
            crop_block(path, b['y0'], b['y1'], next_top).save(
                os.path.join(out_dir, f'{fh}.jpg'), 'JPEG', quality=92)
            manifest[fh] = fh
            made += 1

    json.dump(manifest, open(os.path.join(out_dir, 'manifest.json'), 'w'), ensure_ascii=False)
    print('block images:', made, '/ skipped:', skipped, '/ manifest:', len(manifest))


if __name__ == '__main__':
    main()
