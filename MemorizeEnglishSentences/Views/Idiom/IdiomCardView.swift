import SwiftUI

/// 熟語カード(音読特化)。例文が主役で、熟語部分は強調表示する。
/// カードをタップすると熟語+意味+例文和訳を表示(音読の自己テスト用に既定は非表示)。
/// 単語の長押しは親へ通知する(熟語部分なら熟語の意味、それ以外は単語の意味)。
struct IdiomCardView: View, Equatable {
    let idiom: Idiom
    let isRevealed: Bool
    let onToggle: () -> Void
    /// 長押しされたトークン(語, ブロック内の同語の出現番号, 熟語部分か)
    let onWordTap: (String, Int, Bool) -> Void
    /// 例文の読み上げ
    let onSpeak: () -> Void
    /// 元スクショの表示(対応する画像があるときだけ渡す)
    var onShowSource: (() -> Void)? = nil

    /// 1枚のカードの状態変更(タップで意味表示など)で、見えている全カードが
    /// 作り直されるのを防ぐ。表示に効く値だけを比べ、同じなら再構築しない
    /// (isBookmarked 等のモデル内の変化は Observation が行単位で拾う)。
    static func == (a: IdiomCardView, b: IdiomCardView) -> Bool {
        a.idiom === b.idiom
            && a.isRevealed == b.isRevealed
            && (a.onShowSource == nil) == (b.onShowSource == nil)
    }

    private var tokens: [WordToken] {
        WordTokenizer.tokenize(idiom.example)
    }

    private var idiomIndexes: Set<Int> {
        idiom.idiomTokenIndexes
    }

    /// 重さ調査用: 何枚のカードが実際に組み立てられたかを数える(原因が取れたら外す)
    private static var buildCount = 0

    var body: some View {
        Self.buildCount += 1
        if Self.buildCount % 50 == 0 {
            PerfLog.log("idiom card builds: \(Self.buildCount)")
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(String(idiom.number))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onSpeak()
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                if let onShowSource {
                    Button {
                        onShowSource()
                    } label: {
                        Image(systemName: "photo")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                }
                if idiom.isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(width: 22, height: 22)
                }
            }

            // 例文(熟語部分を強調)。単語長押しで意味を表示
            FlowLayout(spacing: 4, lineSpacing: 7) {
                ForEach(tokens) { token in
                    let isIdiomPart = idiomIndexes.contains(token.id)
                    Text(token.display)
                        .font(.body)
                        .fontWeight(isIdiomPart ? .semibold : .regular)
                        .foregroundStyle(isIdiomPart ? Color.accentColor : Color.primary)
                        .onLongPressGesture {
                            let word = token.normalized.isEmpty ? token.display : token.normalized
                            onWordTap(word, WordTokenizer.occurrence(of: token, in: tokens), isIdiomPart)
                        }
                }
            }

            if isRevealed {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    // 見出し(長押しでも熟語の意味+発音を出せる)
                    Text(idiom.phrase)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .onLongPressGesture {
                            onWordTap("", 0, true)
                        }
                    Text(idiom.meaning)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !idiom.exampleJa.isEmpty {
                        Text(idiom.exampleJa)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onToggle()
        }
    }
}
