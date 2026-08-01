#!/usr/bin/env python3
# 取り込んだ英文から「単語の意味の事前生成」の対象語を洗い出す。
# アプリ(WordTokenizer.normalize + 機能語除外 + 2文字以上 + 文字を含む)と完全に同じ規則で抽出すること。
#
# 使い方:
#   python3 word_inventory.py parsed.json [base_gloss.json]
#     → words_by_block.json(ブロックごとの対象語とハッシュ)
#     → unique_words.txt(ユニーク語と出現ブロック数)
#     → base_gloss.json を渡した場合は new_words.txt(未収録の新出語のみ)
import hashlib
import json
import sys
from collections import Counter

FUNCTION_WORDS = set("""a an the i you he she it we they me him her us them my your his its our their mine yours
myself yourself himself herself itself ourselves themselves this that these those there here
is am are was were be been being do does did done doing have has had having
will would can could should shall may might must and or but so because if when while as than then
to of in on at by for with from about into over under after before between through
out up down off not no nor who whom whose what which how where why whether
some any such only just also too very don't doesn't didn't won't wouldn't can't couldn't
shouldn't isn't aren't wasn't weren't you'll i'm it's""".split())

APOS = "'’"


def normalize(token):
    t = token.lower()
    start, end = 0, len(t)
    while start < end and not (t[start].isalnum() or t[start] in APOS):
        start += 1
    while end > start and not (t[end - 1].isalnum() or t[end - 1] in APOS):
        end -= 1
    return t[start:end]


def content_words(text):
    seen, words = set(), []
    for token in text.split():
        w = normalize(token)
        if len(w) >= 2 and any(c.isalpha() for c in w) and w not in FUNCTION_WORDS and w not in seen:
            seen.add(w)
            words.append(w)
    return words


def block_hash(text):
    return hashlib.sha256(text.strip().encode()).hexdigest()[:16]


def iter_block_texts(data):
    # parsed.json(ページ→blocks)と、english を持つフラットな配列の両方に対応
    for item in data:
        if 'blocks' in item:
            for b in item['blocks']:
                yield b['english']
        elif 'english' in item:
            yield item['english']


def main():
    data = json.load(open(sys.argv[1]))
    base = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else None

    blocks, seen_hash = [], set()
    for text in iter_block_texts(data):
        h = block_hash(text)
        if h in seen_hash:
            continue
        seen_hash.add(h)
        blocks.append({'hash': h, 'text': text, 'words': content_words(text)})

    json.dump(blocks, open('words_by_block.json', 'w'), ensure_ascii=False, indent=1)
    counter = Counter(w for b in blocks for w in b['words'])
    with open('unique_words.txt', 'w') as f:
        for w in sorted(counter):
            f.write(f"{w}\t{counter[w]}\n")

    print('blocks:', len(blocks))
    print('unique words:', len(counter))
    print('(block, word) pairs:', sum(len(b['words']) for b in blocks))
    if base is not None:
        new_words = sorted(w for w in counter if w not in base)
        with open('new_words.txt', 'w') as f:
            f.write('\n'.join(new_words) + ('\n' if new_words else ''))
        print('new words (not in base gloss):', len(new_words))


if __name__ == '__main__':
    main()
