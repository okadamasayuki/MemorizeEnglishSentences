import SwiftData
import SwiftUI

/// ブロックカード。英文は常に表示し、カードをタップすると日本語訳を表示/非表示。
/// 単語タップで意味、単語を長押しするとその単語を含む文だけを構文解析し、
/// 役割ごとに文字色を変える(主語=赤、動詞=青、目的語=緑、補語=オレンジ、助動詞=紫)。
struct BlockCardView: View {
    @Environment(\.modelContext) private var context

    let block: Block
    let isExpanded: Bool
    let onToggle: () -> Void
    let onWordTap: (String) -> Void

    @State private var analysesBySentence: [Int: SyntaxAnalysis] = [:]
    @State private var analyzedIndex: Int?
    @State private var loadingIndex: Int?
    @State private var syntaxError: String?

    private var sentences: [String] {
        TextSplitter.sentences(block.englishText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 4, lineSpacing: 6) {
                ForEach(Array(sentences.enumerated()), id: \.offset) { sentenceIndex, sentence in
                    if analyzedIndex == sentenceIndex, let analysis = analysesBySentence[sentenceIndex] {
                        analyzedWords(analysis)
                    } else {
                        plainWords(sentence, sentenceIndex: sentenceIndex)
                    }
                }
            }

            if loadingIndex != nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("構文を解析中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let syntaxError {
                Text(syntaxError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if isExpanded {
                Text(block.japaneseText ?? "(未翻訳 — ネットワークまたは言語データを確認してください)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - 通常表示(タップ=意味、長押し=その文を構文解析)

    private func plainWords(_ sentence: String, sentenceIndex: Int) -> some View {
        ForEach(WordTokenizer.tokenize(sentence)) { token in
            Text(token.display)
                .font(.body)
                .onTapGesture {
                    let word = token.normalized.isEmpty ? token.display : token.normalized
                    onWordTap(word)
                }
                .onLongPressGesture {
                    analyzeSentence(at: sentenceIndex)
                }
        }
    }

    // MARK: - 解析済み表示(役割ごとに文字色を変える。長押しで元に戻す)

    private func analyzedWords(_ analysis: SyntaxAnalysis) -> some View {
        ForEach(Array(analysis.elements.enumerated()), id: \.offset) { _, element in
            let words = element.text.split(whereSeparator: { $0.isWhitespace })
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(String(word))
                    .font(.body)
                    .foregroundStyle(roleColor(element.role))
                    .onTapGesture {
                        let normalized = WordTokenizer.normalize(String(word))
                        onWordTap(normalized.isEmpty ? String(word) : normalized)
                    }
                    .onLongPressGesture {
                        analyzedIndex = nil
                    }
            }
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "S": .red
        case "V": .blue
        case "O": .green
        case "C": .orange
        case "Aux": .purple
        default: .primary
        }
    }

    private func analyzeSentence(at index: Int) {
        syntaxError = nil
        if analysesBySentence[index] != nil {
            analyzedIndex = index
            return
        }
        guard loadingIndex == nil, index < sentences.count else { return }
        let sentence = sentences[index]
        Task {
            loadingIndex = index
            defer { loadingIndex = nil }
            do {
                let analysis = try await SyntaxAnalyzer.analyze(sentence: sentence, context: context)
                analysesBySentence[index] = analysis
                analyzedIndex = index
            } catch {
                syntaxError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
