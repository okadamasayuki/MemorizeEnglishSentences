#!/usr/bin/env python3
# ARPAbet(CMU発音辞書)→カタカナ変換。
import re
CV = {
    '':  ['ア','イ','ウ','エ','オ'],
    'K': ['カ','キ','ク','ケ','コ'], 'G': ['ガ','ギ','グ','ゲ','ゴ'],
    'S': ['サ','スィ','ス','セ','ソ'], 'Z': ['ザ','ズィ','ズ','ゼ','ゾ'],
    'T': ['タ','ティ','トゥ','テ','ト'], 'D': ['ダ','ディ','ドゥ','デ','ド'],
    'N': ['ナ','ニ','ヌ','ネ','ノ'], 'HH':['ハ','ヒ','フ','ヘ','ホ'],
    'F': ['ファ','フィ','フ','フェ','フォ'], 'B': ['バ','ビ','ブ','ベ','ボ'],
    'P': ['パ','ピ','プ','ペ','ポ'], 'M': ['マ','ミ','ム','メ','モ'],
    'Y': ['ヤ','イ','ユ','イェ','ヨ'], 'R': ['ラ','リ','ル','レ','ロ'],
    'W': ['ワ','ウィ','ウ','ウェ','ウォ'], 'L': ['ラ','リ','ル','レ','ロ'],
    'SH':['シャ','シ','シュ','シェ','ショ'], 'CH':['チャ','チ','チュ','チェ','チョ'],
    'JH':['ジャ','ジ','ジュ','ジェ','ジョ'], 'ZH':['ジャ','ジ','ジュ','ジェ','ジョ'],
    'V': ['ヴァ','ヴィ','ヴ','ヴェ','ヴォ'], 'TH':['サ','スィ','ス','セ','ソ'],
    'DH':['ザ','ズィ','ズ','ゼ','ゾ'],
}
FINAL = {'K':'ク','G':'グ','S':'ス','Z':'ズ','T':'ト','D':'ド','N':'ン','NG':'ング',
    'HH':'フ','F':'フ','B':'ブ','P':'プ','M':'ム','L':'ル','V':'ヴ',
    'SH':'シュ','CH':'チ','JH':'ジ','ZH':'ジュ','TH':'ス','DH':'ズ','Y':'イ','W':'ウ'}
CONS = set(CV) - {''}
VOW = {'AA':(0,''),'AE':(0,''),'AH':(0,''),'AO':(4,'ー'),'AW':(0,'ウ'),'AY':(0,'イ'),
    'EH':(3,''),'ER':(0,'ー'),'EY':(3,'イ'),'IH':(1,''),'IY':(1,'ー'),'OW':(4,'ウ'),
    'OY':(4,'イ'),'UH':(2,''),'UW':(2,'ー')}
SMALL = {0:'ャ',2:'ュ',4:'ョ',3:'ェ'}  # 拗音の小書き(iは無し)

def coda_r(prev_vowel):
    # 語末・子音前の R の色付け
    if prev_vowel in ('EH','AE'): return 'ア'   # air/care→エア, -are
    if prev_vowel in ('IH','IY'): return 'ア'   # ear/near→イア
    if prev_vowel in ('UH','UW'): return 'ア'   # ュア
    return 'ー'                                  # ar→アー, or→オー 等

def to_kana(phones):
    ph = [re.sub(r'\d','',p) for p in phones.split()]
    out=[]; i=0; last_vowel=None
    while i < len(ph):
        p=ph[i]
        if p in VOW:
            col,extra=VOW[p]; out.append(CV[''][col]+extra); last_vowel=p; i+=1
        elif p=='NG':
            out.append('ング'); i+=1
        elif p in CONS:
            nxt = ph[i+1] if i+1<len(ph) else None
            # 子音 + Y + 母音 → 拗音(ビュ, ミュ, キュ…)
            if p not in ('Y','SH','CH','JH','ZH') and nxt=='Y' and i+2<len(ph) and ph[i+2] in VOW:
                col,extra=VOW[ph[i+2]]
                base=CV[p][1]  # i段
                out.append(base + (SMALL.get(col,'') ) + extra)
                last_vowel=ph[i+2]; i+=3
            elif nxt in VOW:
                col,extra=VOW[nxt]; out.append(CV[p][col]+extra); last_vowel=nxt; i+=2
            elif p=='R':
                out.append(coda_r(last_vowel)); i+=1
            else:
                out.append(FINAL.get(p,'')); i+=1
        else:
            i+=1
    s=''.join(out)
    s=s.replace('シャン','ション').replace('ジャン','ジョン').replace('チャン','チョン')  # -tion/-sion は慣用のション
    s=re.sub('ー+','ー',s)          # 長音の重複除去
    s=re.sub('([アイウエオ])ー','\\1ー',s)
    return s

if __name__=='__main__':
    import pronouncing
    tests=['mining','above','any','mountain','airport','ability','achieve','active','water',
     'world','beautiful','island','iron','busy','answer','science','area','create','idea',
     'museum','nuclear','energy','society','government','economy','environment','university',
     'opportunity','question','few','music','human','computer','future','nature','care','near','car','more']
    for w in tests:
        ph=pronouncing.phones_for_word(w); print(w,'->',to_kana(ph[0]) if ph else '(no dict)')
