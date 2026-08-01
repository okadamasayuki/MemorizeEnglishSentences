#!/usr/bin/env python3
# 各ブロックの英文と「割り当てられる予定の訳語」を並べて表示する文脈レビュー用ツール。
# Claude Code がこの出力を通読し、文脈に合わない訳語を overrides.tsv に追加してから
# build_word_senses.py で最終生成する。
#
# 使い方:
#   python3 preview_senses.py words_by_block.json base_gloss.json [overrides.tsv]
import json
import sys


def main():
    blocks = json.load(open(sys.argv[1]))
    base = json.load(open(sys.argv[2]))
    overrides = {}
    if len(sys.argv) > 3:
        for line in open(sys.argv[3]):
            line = line.rstrip('\n')
            if not line.strip():
                continue
            h, w, pos, mean = line.split('\t')
            overrides[(h, w)] = (pos, mean)

    for b in blocks:
        print(f"=== {b['hash']}")
        print(b['text'])
        parts = []
        for w in b['words']:
            if (b['hash'], w) in overrides:
                pos, mean = overrides[(b['hash'], w)]
                parts.append(f"{w}={mean}※")  # ※ = オーバーライド適用済み
            elif w in base:
                parts.append(f"{w}={base[w]['meaning']}")
            else:
                parts.append(f"{w}=【未収録】")
        # 出現番号つきオーバーライド(word#N: N回目の出現だけ別訳)も表示する
        for (h, w), (pos, mean) in overrides.items():
            if h == b['hash'] and '#' in w:
                parts.append(f"{w}={mean}※")
        print('  ' + ' / '.join(parts))
        print()


if __name__ == '__main__':
    main()
