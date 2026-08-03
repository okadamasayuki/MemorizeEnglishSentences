#!/usr/bin/env python3
# 長押しポップアップのカタカナ発音を、規則生成が誤る不規則語だけ CMU 発音辞書で上書きする
# word_katakana.json(word→カタカナ)を生成する。端末 Documents/word_katakana.json へ転送する。
#
# 前提: pip install pronouncing(CMU 発音辞書)。同ディレクトリの arpa2kana.py を使う。
# 入力: katakana_dump.json … アプリが書き出す {word: 規則生成カタカナ}(全内容語)
#       builtin_keys.json  … アプリ内蔵辞書のキー一覧(上書き対象外)
#
# 方針: 内蔵辞書語は除外。1〜2 音節で規則生成と CMU が食い違う語=不規則語として CMU で上書き。
#       3 音節以上でも規則が誤る少数の語は CURATED で個別指定。学術系の多音節語は規則生成が
#       慣用的なので上書きしない。
import json
import sys

import pronouncing
from arpa2kana import to_kana

# 3 音節以上でも規則生成が誤る/CMU が不慣用な語の個別指定(慣用カタカナ)
CURATED = {
    'idea': 'アイディア', 'ideas': 'アイディアズ', 'area': 'エリア', 'areas': 'エリアズ',
    'energy': 'エネルギー', 'computer': 'コンピューター', 'computers': 'コンピューターズ',
    'media': 'メディア', 'nuclear': 'ニュークリア', 'radio': 'ラジオ', 'video': 'ビデオ',
    'data': 'データ', 'image': 'イメージ', 'images': 'イメージズ', 'item': 'アイテム', 'items': 'アイテムズ',
}


def cmu_kana(word):
    base = word.replace("'", "")
    ph = pronouncing.phones_for_word(base)
    if not ph and base.endswith('s'):
        p2 = pronouncing.phones_for_word(base[:-1])
        if p2:
            ph = [p2[0] + ' Z']
    return to_kana(ph[0]) if ph else None


def syllables(word):
    ph = pronouncing.phones_for_word(word.replace("'", ""))
    return pronouncing.syllable_count(ph[0]) if ph else 99


def main():
    heur = json.load(open(sys.argv[1]))              # katakana_dump.json
    builtin = set(json.load(open(sys.argv[2])))      # builtin_keys.json
    out = sys.argv[3] if len(sys.argv) > 3 else 'word_katakana.json'

    override = {}
    for w in heur:
        if w in CURATED:
            continue
        if w in builtin:
            continue
        ck = cmu_kana(w)
        if ck and heur[w] != ck and syllables(w) <= 2:
            override[w] = ck
    for w, k in CURATED.items():
        override[w] = k

    json.dump(override, open(out, 'w'), ensure_ascii=False)
    print('override entries:', len(override), '/ corpus:', len(heur))


if __name__ == '__main__':
    main()
