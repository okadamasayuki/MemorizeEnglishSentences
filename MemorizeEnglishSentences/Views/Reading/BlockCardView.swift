import SwiftData
import SwiftUI

/// ブロックカード。英文は常に表示し、カードをタップすると日本語訳を表示/非表示。
/// 単語タップで意味、長押しで英文がその場で構文解析(色分けチップ + S/V/O)に切り替わる。
struct BlockCardView: View {
    @Environment(\.modelContext) private var context

    let block: Block
    let isExpanded: Bool
    let onToggle: () -> Void
    let onWordTap: (String) -> Void

    @State private var analysis: SyntaxAnalysis?
    @State private var showSyntax = false
    @State private var isLoadingSyntax = false
    @State private var syntaxError: String?

    private var tokens: [WordToken] {
        WordTokenizer.tokenize(block.englishText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSyntax, let analysis {
                syntaxView(analysis)
            } else {
                FlowLayout(spacing: 4, lineSpacing: 6) {
                    ForEach(tokens) { token in
                        Text(token.display)
                            .font(.body)
                            .onTapGesture {
                                let word = token.normalized.isEmpty ? token.display : token.normalized
                                onWordTap(word)
                            }
                    }
                }
            }

            if isLoadingSyntax {
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
        .onLongPressGesture {
            toggleSyntax()
        }
    }

    // MARK: - 構文解析(その場で表示)

    private func syntaxView(_ analysis: SyntaxAnalysis) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 10) {
            ForEach(Array(analysis.elements.enumerated()), id: \.offset) { _, element in
                VStack(spacing: 2) {
                    Text(element.text)
                        .font(.body.bold())
                    Text(element.role)
                        .font(.caption.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(roleColor(element.role).opacity(0.18))
                )
                .foregroundStyle(roleColor(element.role))
            }
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "S": .blue
        case "V": .red
        case "O": .green
        case "C": .orange
        case "Aux": .purple
        default: .gray
        }
    }

    private func toggleSyntax() {
        syntaxError = nil
        if showSyntax {
            showSyntax = false
            return
        }
        if analysis != nil {
            showSyntax = true
            return
        }
        guard !isLoadingSyntax else { return }
        Task {
            isLoadingSyntax = true
            defer { isLoadingSyntax = false }
            do {
                analysis = try await SyntaxAnalyzer.analyze(sentence: block.englishText, context: context)
                showSyntax = true
            } catch {
                syntaxError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
