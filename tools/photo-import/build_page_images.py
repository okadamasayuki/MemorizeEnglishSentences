#!/usr/bin/env python3
# 各英文ブロックに対応する「元スクショ(教材ページ画像)」を端末投入用フォルダに書き出す。
# 音読タブのブロック右上の写真ボタンから、読み取りが正しいかすぐ確認するためのデータ。
#
# 使い方:
#   python3 build_page_images.py parsed.json passages.json photos_dir out_dir
#     parsed.json:  [{"file": UUID先頭, "topic":..., "blocks":[{"english":...}]}]  (parse.py の出力)
#     passages.json: [{"english": 最終英文, "japanese":...}]  (端末の passages_export.json)
#     photos_dir:   Photos からエクスポートした元画像(<UUID>/**/画像)のディレクトリ
#     out_dir:      生成先。out_dir/manifest.json と out_dir/<ページ番号>.jpg を作る
#
# 出力を `devicectl device copy to --destination Documents/page_images` で端末へ転送する。
# manifest.json は {ブロック英文ハッシュ(sha256[:16]): "ページ番号"}。
# 端末英文がOCR補正後で parsed とずれるブロックは difflib で近い parsed ブロックに対応づける。
import difflib
import glob
import hashlib
import json
import os
import subprocess
import sys


def H(t):
    return hashlib.sha256(t.strip().encode()).hexdigest()[:16]


def main():
    parsed = json.load(open(sys.argv[1]))
    passages = json.load(open(sys.argv[2]))
    photos_dir = sys.argv[3]
    out_dir = sys.argv[4]
    os.makedirs(out_dir, exist_ok=True)

    dirs = os.listdir(photos_dir)
    page_src = {}          # ページ番号 -> 元画像パス
    parsed_blocks = []     # (英文, ページ番号)
    for i, pg in enumerate(parsed):
        hit = [d for d in dirs if d.startswith(pg['file'])]
        if not hit:
            print('WARN: no photo dir for', pg['file'], file=sys.stderr); continue
        imgs = [f for f in glob.glob(os.path.join(photos_dir, hit[0], '**', '*'), recursive=True)
                if os.path.isfile(f)]
        if imgs:
            page_src[i] = imgs[0]
        for b in pg['blocks']:
            parsed_blocks.append((b['english'], i))
    parsed_hash = {H(en): pi for en, pi in parsed_blocks}

    # 各(最終)英文ブロック -> ページ番号
    manifest = {}
    for b in passages:
        en = b['english']; h = H(en)
        if h in parsed_hash:
            manifest[h] = str(parsed_hash[h])
        else:
            best = max(parsed_blocks, key=lambda pb: difflib.SequenceMatcher(None, en, pb[0]).ratio())
            if difflib.SequenceMatcher(None, en, best[0]).ratio() > 0.7:
                manifest[h] = str(best[1])

    json.dump(manifest, open(os.path.join(out_dir, 'manifest.json'), 'w'), ensure_ascii=False)

    # 使うページだけ 1400px 幅に縮小して jpeg 保存
    used = set(int(v) for v in manifest.values())
    for i in used:
        if i in page_src:
            subprocess.run(['sips', '-s', 'format', 'jpeg', '-Z', '1400', page_src[i],
                            '--out', os.path.join(out_dir, f'{i}.jpg')],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    print('manifest entries:', len(manifest), '/ page images:', len(used))


if __name__ == '__main__':
    main()
