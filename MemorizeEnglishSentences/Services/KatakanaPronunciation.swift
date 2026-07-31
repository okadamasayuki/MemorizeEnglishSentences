import Foundation

/// 英単語のおおよその発音をカタカナで表す(音声が聞けない場面用の「読み方の目安」)。
/// よく使う単語は辞書で正確に、それ以外は綴り→音の規則で近似変換する。完全オフライン。
enum KatakanaPronunciation {
    static func katakana(for word: String) -> String {
        let normalized = word.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = dictionary[normalized] {
            return exact
        }
        let letters = normalized.filter { $0.isLetter }
        if letters.isEmpty { return "" }
        if let exact = dictionary[String(letters)] {
            return exact
        }
        let tokens = tokenize(Array(letters))
        return synthesize(tokens)
    }

    // MARK: - よく使う単語の辞書(規則変換より優先)

    private static let dictionary: [String: String] = [
        "the": "ザ", "a": "ア", "an": "アン",
        "i": "アイ", "you": "ユー", "he": "ヒー", "she": "シー", "we": "ウィー",
        "they": "ゼイ", "it": "イット", "me": "ミー", "us": "アス", "him": "ヒム",
        "my": "マイ", "your": "ユア", "his": "ヒズ", "her": "ハー", "its": "イッツ",
        "our": "アワー", "their": "ゼア", "them": "ゼム", "mine": "マイン",
        "is": "イズ", "am": "アム", "are": "アー", "was": "ワズ", "were": "ワー",
        "be": "ビー", "been": "ビーン", "being": "ビーイング",
        "do": "ドゥー", "does": "ダズ", "did": "ディッド", "done": "ダン",
        "have": "ハブ", "has": "ハズ", "had": "ハッド",
        "will": "ウィル", "would": "ウッド", "can": "キャン", "could": "クッド",
        "shall": "シャル", "should": "シュッド", "may": "メイ", "might": "マイト",
        "must": "マスト",
        "of": "オブ", "to": "トゥー", "in": "イン", "on": "オン", "at": "アット",
        "by": "バイ", "for": "フォー", "with": "ウィズ", "from": "フロム",
        "as": "アズ", "and": "アンド", "but": "バット", "or": "オア", "not": "ノット",
        "no": "ノー", "yes": "イエス", "if": "イフ", "so": "ソウ", "too": "トゥー",
        "this": "ディス", "that": "ザット", "these": "ジーズ", "those": "ゾーズ",
        "there": "ゼア", "here": "ヒア", "where": "ウェア", "when": "ウェン",
        "why": "ワイ", "how": "ハウ", "what": "ワット", "who": "フー",
        "whose": "フーズ", "which": "ウィッチ", "whom": "フーム",
        "one": "ワン", "two": "トゥー", "once": "ワンス", "only": "オンリー",
        "other": "アザー", "another": "アナザー", "some": "サム", "any": "エニー",
        "many": "メニー", "much": "マッチ", "more": "モア", "most": "モウスト",
        "very": "ベリー", "also": "オールソウ", "again": "アゲイン",
        "said": "セッド", "says": "セズ", "because": "ビコーズ",
        "before": "ビフォア", "after": "アフター", "about": "アバウト",
        "above": "アバブ", "under": "アンダー", "over": "オウバー",
        "into": "イントゥ", "out": "アウト", "up": "アップ", "down": "ダウン",
        "off": "オフ", "through": "スルー", "between": "ビトウィーン",
        "people": "ピープル", "woman": "ウーマン", "women": "ウィミン",
        "water": "ウォーター", "love": "ラブ", "live": "リブ", "give": "ギブ",
        "come": "カム", "gone": "ゴーン", "move": "ムーブ", "lose": "ルーズ",
        "son": "サン", "sun": "サン", "one's": "ワンズ", "than": "ザン",
        "then": "ゼン", "music": "ミュージック", "busy": "ビジー",
        "does't": "ダズント",
        "i'm": "アイム", "i'll": "アイル", "i've": "アイブ", "i'd": "アイド",
        "it's": "イッツ", "don't": "ドント", "doesn't": "ダズント",
        "didn't": "ディドント", "can't": "キャント", "isn't": "イズント",
        "aren't": "アーント", "wasn't": "ワズント", "won't": "ウォント",
        "you're": "ユア", "we're": "ウィア", "they're": "ゼア",
        "let's": "レッツ", "that's": "ザッツ", "there's": "ゼアズ",
        "future": "フューチャー", "beautiful": "ビューティフル",
        "language": "ラングウィッジ", "english": "イングリッシュ",
        "japanese": "ジャパニーズ", "world": "ワールド",
        "minute": "ミニット", "minutes": "ミニッツ",
        "practice": "プラクティス", "office": "オフィス",
        "courage": "カレッジ", "continue": "コンティニュー",
        "immediately": "イミーディエットリー", "suitcase": "スーツケース",
    ]

    // MARK: - Phase 1: 綴り → 音素トークン

    private static let vowelTokens: Set<String> = [
        "A", "I", "U", "E", "O",
        "EI", "AI", "OU", "AU", "OI", "II", "UU", "AA", "OO",
    ]

    private static let fixedPatterns: [(String, [String])] = [
        ("ssion", ["SH", "O", "N"]),
        ("ought", ["OO", "T"]),
        ("aught", ["OO", "T"]),
        ("tion", ["SH", "O", "N"]),
        ("sion", ["J", "O", "N"]),
        ("cial", ["SH", "A", "L"]),
        ("tial", ["SH", "A", "L"]),
        ("ture", ["CH", "AA"]),
        ("sure", ["J", "AA"]),
        ("eigh", ["EI"]),
        ("augh", ["OO"]),
        ("ough", ["OO"]),
        ("igh", ["AI"]),
        ("tch", ["ッ", "CH"]),
        ("dge", ["ッ", "J"]),
        ("wor", ["W", "AA"]),
        ("oar", ["OO"]),
        ("alk", ["OO", "K"]),
        ("ck", ["ッ", "K"]),
        ("ph", ["F"]),
        ("sh", ["SH"]),
        ("ch", ["CH"]),
        ("th", ["S"]),
        ("wh", ["W"]),
        ("qu", ["K", "W"]),
        ("ee", ["II"]),
        ("ea", ["II"]),
        ("oo", ["UU"]),
        ("ai", ["EI"]),
        ("ay", ["EI"]),
        ("au", ["OO"]),
        ("aw", ["OO"]),
        ("oi", ["OI"]),
        ("oy", ["OI"]),
        ("oa", ["OU"]),
        ("ou", ["AU"]),
        ("ew", ["Y", "UU"]),
        ("eu", ["Y", "UU"]),
        ("ue", ["UU"]),
        ("ui", ["UU"]),
        ("ar", ["AA"]),
        ("or", ["OO"]),
        ("er", ["AA"]),
        ("ir", ["AA"]),
        ("ur", ["AA"]),
    ]

    private static func isVowelChar(_ c: Character) -> Bool {
        "aeiou".contains(c)
    }

    private static func tokenize(_ chars: [Character]) -> [String] {
        var tokens: [String] = []
        var i = 0
        let n = chars.count

        func remainder(startsWith pattern: String) -> Bool {
            guard i + pattern.count <= n else { return false }
            return String(chars[i..<(i + pattern.count)]) == pattern
        }

        while i < n {
            let c = chars[i]

            // 語末の "all" → オール(ball, small など)
            if remainder(startsWith: "all"), i + 3 == n {
                tokens.append(contentsOf: ["OO", "L"])
                i += 3
                continue
            }
            // 語頭の kn / wr は最初の文字が無音
            if i == 0, remainder(startsWith: "kn") {
                tokens.append("N"); i += 2; continue
            }
            if i == 0, remainder(startsWith: "wr") {
                tokens.append("R"); i += 2; continue
            }
            // gh: 語頭は g 音、それ以外は無音(right, night)
            if remainder(startsWith: "gh") {
                if i == 0 { tokens.append("G") }
                i += 2
                continue
            }
            // 語末の mb は b が無音(climb)
            if remainder(startsWith: "mb"), i + 2 == n {
                tokens.append("M"); i += 2; continue
            }

            // 固定パターン(長いものから)
            var matched = false
            for (pattern, output) in fixedPatterns where remainder(startsWith: pattern) {
                // ar/or/er などの r 母音は、直後が母音なら適用しない(around → アラウンド)
                if ["ar", "or", "er", "ir", "ur"].contains(pattern),
                   i + pattern.count < n, isVowelChar(chars[i + pattern.count]) {
                    continue
                }
                tokens.append(contentsOf: output)
                i += pattern.count
                matched = true
                break
            }
            if matched { continue }

            // cc: 後ろが e/i/y なら ks(success → サクセス)、それ以外は促音
            if c == "c", i + 1 < n, chars[i + 1] == "c" {
                if i + 2 < n, "eiy".contains(chars[i + 2]) {
                    tokens.append("K")
                    i += 1
                } else {
                    tokens.append("ッ")
                    i += 1
                }
                continue
            }

            // 同じ子音の連続: pp/tt などは促音、ll/ss などは 1 つに縮約
            if i + 1 < n, c == chars[i + 1], !isVowelChar(c) {
                if "ptkdgb".contains(c) {
                    tokens.append("ッ")
                }
                i += 1
                continue
            }

            // マジック e: [母音][子音]e$ / [母音][子音]ed$ → 長母音(make → メイク, shined → シャインド)
            if isVowelChar(c), i + 2 < n,
               (i + 2 == n - 1 || (i + 3 == n - 1 && chars[i + 3] == "d")),
               !isVowelChar(chars[i + 1]), chars[i + 2] == "e" {
                switch c {
                case "a": tokens.append("EI")
                case "i": tokens.append("AI")
                case "o": tokens.append("OU")
                case "u": tokens.append(contentsOf: ["Y", "UU"])
                default: tokens.append("II")
                }
                i += 1
                continue
            }

            // 語末の e は無音(直前が子音のとき)。過去形 -ed の e も無音(wrapped → ラップド)
            if c == "e", n > 2, i > 0, !isVowelChar(chars[i - 1]),
               (i == n - 1 || (i == n - 2 && chars[n - 1] == "d")) {
                i += 1
                continue
            }

            switch c {
            case "a": tokens.append("A")
            case "e": tokens.append("E")
            case "o": tokens.append("O")
            case "u": tokens.append("A") // cut, bus など英語の u は「ア」寄り
            case "i": tokens.append("I")
            case "y":
                if i == 0 {
                    tokens.append("Y")
                } else if i == n - 1 {
                    tokens.append(n <= 3 ? "AI" : "II") // my → マイ / happy → ハッピー
                } else {
                    tokens.append("I")
                }
            case "c":
                if i + 1 < n, "eiy".contains(chars[i + 1]) {
                    tokens.append("S")
                } else {
                    tokens.append("K")
                }
            case "g":
                if i + 1 < n, "eiy".contains(chars[i + 1]) {
                    tokens.append("J")
                } else {
                    tokens.append("G")
                }
            case "x": tokens.append(contentsOf: ["K", "S"])
            case "b": tokens.append("B")
            case "d": tokens.append("D")
            case "f": tokens.append("F")
            case "h": tokens.append("H")
            case "j": tokens.append("J")
            case "k": tokens.append("K")
            case "l": tokens.append("L")
            case "m": tokens.append("M")
            case "n": tokens.append("N")
            case "p": tokens.append("P")
            case "r": tokens.append("R")
            case "s": tokens.append("S")
            case "t": tokens.append("T")
            case "v": tokens.append("V")
            case "w": tokens.append("W")
            case "z": tokens.append("Z")
            default: break
            }
            i += 1
        }
        return tokens
    }

    // MARK: - Phase 2: 音素トークン → カタカナ

    private static let rows: [String: [String]] = [
        // [ア段, イ段, ウ段, エ段, オ段]
        "B": ["バ", "ビ", "ブ", "ベ", "ボ"],
        "V": ["バ", "ビ", "ブ", "ベ", "ボ"],
        "D": ["ダ", "ディ", "ドゥ", "デ", "ド"],
        "F": ["ファ", "フィ", "フ", "フェ", "フォ"],
        "G": ["ガ", "ギ", "グ", "ゲ", "ゴ"],
        "H": ["ハ", "ヒ", "フ", "ヘ", "ホ"],
        "J": ["ジャ", "ジ", "ジュ", "ジェ", "ジョ"],
        "K": ["カ", "キ", "ク", "ケ", "コ"],
        "L": ["ラ", "リ", "ル", "レ", "ロ"],
        "R": ["ラ", "リ", "ル", "レ", "ロ"],
        "M": ["マ", "ミ", "ム", "メ", "モ"],
        "N": ["ナ", "ニ", "ヌ", "ネ", "ノ"],
        "P": ["パ", "ピ", "プ", "ペ", "ポ"],
        "S": ["サ", "シ", "ス", "セ", "ソ"],
        "T": ["タ", "ティ", "トゥ", "テ", "ト"],
        "W": ["ワ", "ウィ", "ウ", "ウェ", "ウォ"],
        "Y": ["ヤ", "イ", "ユ", "イェ", "ヨ"],
        "Z": ["ザ", "ジ", "ズ", "ゼ", "ゾ"],
        "SH": ["シャ", "シ", "シュ", "シェ", "ショ"],
        "CH": ["チャ", "チ", "チュ", "チェ", "チョ"],
    ]

    private static let standalone: [String: String] = [
        "B": "ブ", "V": "ブ", "D": "ド", "F": "フ", "G": "グ", "H": "フ",
        "J": "ジ", "K": "ク", "L": "ル", "R": "ー", "M": "ム", "N": "ン",
        "P": "プ", "S": "ス", "T": "ト", "W": "ウ", "Y": "イ", "Z": "ズ",
        "SH": "シュ", "CH": "チ", "ッ": "ッ",
    ]

    private static func vowelIndex(_ vowel: String) -> Int? {
        switch vowel {
        case "A": 0
        case "I": 1
        case "U": 2
        case "E": 3
        case "O": 4
        default: nil
        }
    }

    private static func kana(consonant: String?, vowel: String) -> String {
        switch vowel {
        case "EI": kana(consonant: consonant, vowel: "E") + "イ"
        case "AI": kana(consonant: consonant, vowel: "A") + "イ"
        case "OU": kana(consonant: consonant, vowel: "O") + "ウ"
        case "AU": kana(consonant: consonant, vowel: "A") + "ウ"
        case "OI": kana(consonant: consonant, vowel: "O") + "イ"
        case "II": kana(consonant: consonant, vowel: "I") + "ー"
        case "UU": kana(consonant: consonant, vowel: "U") + "ー"
        case "AA": kana(consonant: consonant, vowel: "A") + "ー"
        case "OO": kana(consonant: consonant, vowel: "O") + "ー"
        default:
            if let consonant, let row = rows[consonant], let index = vowelIndex(vowel) {
                row[index]
            } else {
                ["A": "ア", "I": "イ", "U": "ウ", "E": "エ", "O": "オ"][vowel] ?? ""
            }
        }
    }

    private static func smallYoon(_ vowel: String) -> String? {
        switch vowel {
        case "A": "ャ"
        case "U": "ュ"
        case "UU": "ュー"
        case "O": "ョ"
        case "OO", "OU": "ョー"
        default: nil
        }
    }

    private static func synthesize(_ tokens: [String]) -> String {
        var result = ""
        var i = 0
        let n = tokens.count

        while i < n {
            let token = tokens[i]

            if token == "ッ" {
                result += "ッ"
                i += 1
                continue
            }

            if vowelTokens.contains(token) {
                result += kana(consonant: nil, vowel: token)
                i += 1
                continue
            }

            // 子音 + Y + 母音 → 拗音(new → ニュー)
            if i + 2 <= n - 1, tokens[i + 1] == "Y", vowelTokens.contains(tokens[i + 2]),
               let row = rows[token], let yoon = smallYoon(tokens[i + 2]) {
                result += row[1] + yoon
                i += 3
                continue
            }

            // 子音 + 母音
            if i + 1 < n, vowelTokens.contains(tokens[i + 1]) {
                result += kana(consonant: token, vowel: tokens[i + 1])
                i += 2
                continue
            }

            // 子音単独
            if token == "R" {
                result += result.isEmpty ? "ル" : "ー"
            } else if token == "M", i + 1 < n, tokens[i + 1] == "P" || tokens[i + 1] == "B" {
                // p/b の前の m は「ン」(impossible → インポシブル)
                result += "ン"
            } else if i == n - 1, "TPKDGJ".contains(token), lastIsShortVowel(tokens, at: i) {
                // 短母音 + 語末子音は促音に(not → ノット)
                result += "ッ" + (standalone[token] ?? "")
            } else {
                result += standalone[token] ?? ""
            }
            i += 1
        }
        return result
    }

    private static func lastIsShortVowel(_ tokens: [String], at index: Int) -> Bool {
        guard index > 0 else { return false }
        return ["A", "I", "U", "E", "O"].contains(tokens[index - 1])
    }
}
