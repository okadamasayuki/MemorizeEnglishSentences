#!/usr/bin/env python3
# 基礎訳語辞書 + ブロック別オーバーライドから、アプリ取り込み用の word_senses.json を生成する。
# 全 (ブロック, 単語) の網羅を検証し、欠けがあればエラー終了する。
#
# 使い方:
#   python3 build_word_senses.py words_by_block.json base_gloss.json [overrides.tsv]
#     base_gloss.json: {"word": {"pos": 品詞, "meaning": 訳語}, ...}
#     overrides.tsv:   ブロックハッシュ<TAB>単語<TAB>品詞<TAB>訳語(文脈で訳が変わる語のみ)
#       単語は「word#N」形式も可(N=ブロック内でのその単語の出現番号、0始まり)。
#       同じ単語がブロック内で別の意味で使われる場合に、N回目の出現だけ訳を変えられる。
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

    # オーバーライドの (hash, word) が実在するか(word#N はベースの単語で確認)
    pairs = {(b['hash'], w) for b in blocks for w in b['words']}
    bad = [k for k in overrides if (k[0], k[1].split('#')[0]) not in pairs]
    if bad:
        print('ERROR: invalid overrides (hash, word):', bad, file=sys.stderr)
        sys.exit(1)

    out, missing = [], []
    for b in blocks:
        for w in b['words']:
            if (b['hash'], w) in overrides:
                pos, mean = overrides[(b['hash'], w)]
            elif w in base:
                pos, mean = base[w]['pos'], base[w]['meaning']
            else:
                missing.append(w)
                continue
            out.append({'key': f"{w}|{b['hash']}", 'word': w, 'pos': pos, 'meaning': mean})

    # 出現番号つきオーバーライド(word#N)は、ブロック共通の訳とは別のエントリとして追加する
    for (h, w), (pos, mean) in overrides.items():
        if '#' in w:
            out.append({'key': f"{w}|{h}", 'word': w.split('#')[0], 'pos': pos, 'meaning': mean})

    if missing:
        print('ERROR: words without gloss:', sorted(set(missing)), file=sys.stderr)
        sys.exit(1)

    json.dump(out, open('word_senses.json', 'w'), ensure_ascii=False)
    print('word_senses.json written:', len(out), 'senses')


if __name__ == '__main__':
    main()
